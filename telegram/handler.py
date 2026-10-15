import hmac
import html
import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TELEGRAM_URL = f"https://api.telegram.org/bot{os.environ['TELEGRAM_TOKEN']}"
WEBHOOK_SECRET = os.environ["TELEGRAM_WEBHOOK_SECRET"]
ALLOWED_CHAT_IDS = {int(i) for i in os.environ["ALLOWED_CHAT_IDS"].split(",") if i.strip()}

GH_HEADERS = {
    "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
    "Accept": "application/vnd.github+json",
}
GH_WORKFLOW_URL = f"https://api.github.com/repos/{os.environ['GH_REPO']}/actions/workflows/deploy_vpn.yml"

AWS_REGION = os.environ["AWS_REGION"]
S3_CLIENT = boto3.client("s3", region_name=AWS_REGION, endpoint_url=f"https://s3.{AWS_REGION}.amazonaws.com")
S3_BUCKET = os.environ["S3_BUCKET"]
S3_PROFILE_PREFIX = os.environ["S3_PROFILE_PREFIX"]

CLOUDS = {"aws": "AWS Stockholm", "yandex": "Yandex Cloud"}
YANDEX_WORDS = ["yandex", "yc"]
OPENVPN_WORDS = ["openvpn", "ovpn", "tcp"]
PROFILE_EXTENSIONS = (".conf", ".ovpn")
LINK_TTL = 300

HTTP_TIMEOUT = 10


def http_request(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as r:
            body = r.read()
            return r.status, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        logger.error("%s %s failed: %s %s", method or "GET", url.split("?")[0], e.code, e.read()[:500])
        return e.code, None


def send_message(chat_id, text, parse_mode=""):
    payload = {"chat_id": chat_id, "text": text}
    if parse_mode:
        payload["parse_mode"] = parse_mode
    http_request(TELEGRAM_URL + "/sendMessage", data=urllib.parse.urlencode(payload).encode(), method="POST")


def send_photo(chat_id, photo_url, caption):
    payload = {"chat_id": chat_id, "photo": photo_url, "caption": caption}
    http_request(TELEGRAM_URL + "/sendPhoto", data=urllib.parse.urlencode(payload).encode(), method="POST")


def gh_dispatch(action, cloud, protocol):
    inputs = {"action": action, "cloud": cloud, "protocol": protocol}
    payload = json.dumps({"ref": "main", "inputs": inputs}).encode()
    status, _ = http_request(GH_WORKFLOW_URL + "/dispatches", data=payload, headers=GH_HEADERS, method="POST")
    return status


def gh_track(chat_id):
    status, body = http_request(GH_WORKFLOW_URL + "/runs?per_page=1", headers=GH_HEADERS)
    runs = (body or {}).get("workflow_runs", [])
    if status != 200:
        send_message(chat_id, f"Cannot call GitHub, response code: {status}.")
    elif not runs:
        send_message(chat_id, "No jobs yet.")
    else:
        run = runs[0]
        text = f"Last job: {run['display_title']}\nStatus: {run['status']}"
        if run["conclusion"]:
            text += f"\nConclusion: {run['conclusion']}"
        send_message(chat_id, text)


def presign(key, **response):
    params = {"Bucket": S3_BUCKET, "Key": key, **response}
    return S3_CLIENT.generate_presigned_url("get_object", Params=params, ExpiresIn=LINK_TTL)


def send_profiles(chat_id, links=True, qr_codes=True):
    res = S3_CLIENT.list_objects_v2(Bucket=S3_BUCKET, Prefix=S3_PROFILE_PREFIX)
    keys = sorted(obj["Key"] for obj in res.get("Contents", []))
    found_profiles = sent = False
    for cloud, title in CLOUDS.items():
        prefix = f"{S3_PROFILE_PREFIX}{cloud}/"
        files = [k.removeprefix(prefix) for k in keys if k.startswith(prefix)]
        profiles = [f for f in files if f.endswith(PROFILE_EXTENSIONS)]
        found_profiles = found_profiles or bool(profiles)

        if links and profiles:
            items = []
            for name in profiles:
                disposition = f'attachment; filename="vpn-{cloud}-{name}"'
                url = presign(prefix + name, ResponseContentDisposition=disposition)
                items.append(f'<a href="{html.escape(url)}">{html.escape(name)}</a>')
            send_message(chat_id, f"<b>{title}</b> (links expire in 5 minutes):\n" + "\n".join(items), "HTML")
            sent = True

        if qr_codes:
            for name in files:
                if name.endswith(".png"):
                    url = presign(prefix + name, ResponseContentType="image/png")
                    send_photo(chat_id, url, f"{title}: {name.removesuffix('.png')}")
                    sent = True

    if sent:
        return
    if found_profiles:
        send_message(chat_id, "QR codes are only made for WireGuard, use /profile to get the OpenVPN profile.")
    else:
        send_message(chat_id, "The profile is removed or not available yet.")


def run_workflow(chat_id, action, cloud, protocol):
    rc = gh_dispatch(action, cloud, protocol)
    if rc == 204:
        what = f"{action} {protocol}" if action == "apply" else action
        send_message(chat_id, f"The job is launched ({what} in {CLOUDS[cloud]}), please track the status.")
    else:
        send_message(chat_id, f"Cannot call GitHub, response code: {rc}. Please check the logs.")


def presented_in(patterns, message):
    return any(pattern in message for pattern in patterns)


def handle_message(chat_id, first_name, message):
    # "/deploy_yandex@SomeBot" -> "deploy yandex": menu commands cannot contain spaces
    split = [part for word in message.split() for part in word.lstrip("/").split("@")[0].split("_") if part]
    cloud = "yandex" if presented_in(YANDEX_WORDS, split) else "aws"
    protocol = "openvpn" if presented_in(OPENVPN_WORDS, split) else "wireguard"

    if presented_in(["hi", "hello", "hey", "start"], split):
        send_message(chat_id, f"Long time no see, {first_name}!")

    elif presented_in(["how are you", "how is it going"], message):
        send_message(chat_id, "Not that bad! What are we doing today?")

    elif presented_in(["run", "deploy", "launch"], split):
        run_workflow(chat_id, "apply", cloud, protocol)

    elif presented_in(["qr"], split):
        send_profiles(chat_id, links=False)

    elif presented_in(["profile", "config"], split):
        send_profiles(chat_id, qr_codes=False)

    elif presented_in(["profiles", "status", "now", "track", "link"], split):
        gh_track(chat_id)
        send_profiles(chat_id)

    elif presented_in(["thank"], message):
        send_message(chat_id, "I know you’d do the same for me.")

    elif presented_in(["destroy"], split):
        run_workflow(chat_id, "destroy", cloud, protocol)

    elif presented_in(["bye"], message):
        send_message(chat_id, f"Talk to you soon, {first_name}!")

    else:
        send_message(chat_id, "Thank you... Thank you for being so dumb!")


def handler(event, context):
    headers = event.get("headers") or {}
    if not hmac.compare_digest(headers.get("x-telegram-bot-api-secret-token", ""), WEBHOOK_SECRET):
        logger.warning("Rejected a request without a valid webhook secret")
        return {"statusCode": 401}

    try:
        update = json.loads(event["body"])
        msg = update.get("message") or {}
        chat = msg.get("chat") or {}
        chat_id = chat.get("id")
        text = msg.get("text")

        if chat_id not in ALLOWED_CHAT_IDS:
            logger.warning("Ignoring a message from chat_id=%s", chat_id)
        elif text:
            handle_message(chat_id, chat.get("first_name", "there"), text.lower())
    except Exception:
        # Telegram retries non-2xx responses, so errors are only logged
        logger.exception("Failed to handle the update")

    return {"statusCode": 200}
