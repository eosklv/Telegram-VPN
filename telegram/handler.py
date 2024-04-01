import json
import os
import sys
import boto3
import datetime

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, "./vendored"))

import requests

TELEGRAM_URL = f"https://api.telegram.org/bot{os.environ['TELEGRAM_TOKEN']}"

GH_AUTH = {"Authorization": f"Bearer {os.environ['GH_TOKEN']}"}
GH_OWNER = "eosklv"
GH_REPO = "vpn"
GH_WORKFLOW = "deploy_vpn.yml"
GH_URL = f"https://api.github.com/repos/{GH_OWNER}/{GH_REPO}/actions"

S3_CLIENT = boto3.client("s3")
S3_BUCKET = "esklv-vpn"
S3_PROFILE = "profiles/client.ovpn"


def gh_dispatch(action=""):
    payload = json.dumps({"ref": "main", "inputs": {"action": action}})
    r = requests.post(GH_URL + f"/workflows/{GH_WORKFLOW}/dispatches", headers=GH_AUTH, data=payload)
    return r.status_code


def gh_track(chat_id):
    t = (datetime.datetime.utcnow() - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M")
    r = requests.get(GH_URL + f"/runs?created=%3E{t}", headers=GH_AUTH)
    runs = r.json()["workflow_runs"]
    if len(runs) > 0:
        send_message(chat_id, f"Job status: {runs[0]['status']}")
        if runs[0]['conclusion']:
            send_message(chat_id, f"Job conclusion: {runs[0]['conclusion']}")
    else:
        send_message(chat_id, "No active jobs.")


def send_message(chat_id, response, parse_mode=""):
    payload = {"text": response.encode("utf8"), "chat_id": chat_id}
    if parse_mode:
        payload["parse_mode"] = parse_mode
    url = TELEGRAM_URL + "/sendMessage"
    requests.post(url, data=payload)


def prefix_exists(bucket, prefix):
    res = S3_CLIENT.list_objects_v2(Bucket=bucket, Prefix=prefix)
    return "Contents" in res


def presented_in(patterns, message):
    for pattern in patterns:
        if pattern in message:
            return True
    return False


def handler(event, context):
    try:
        data = json.loads(event["body"])
        message = str(data["message"]["text"]).lower()
        split = message.split()
        chat_id = data["message"]["chat"]["id"]
        first_name = data["message"]["chat"]["first_name"]
                
        if presented_in(["hi", "hello", "hey"], split):
            send_message(chat_id, f"Long time no see, {first_name}!")

        elif presented_in(["how are you", "how is it going"], message):
            send_message(chat_id, "Not that bad! What are we doing today?")

        elif presented_in(["run", "deploy", "launch"], split):
            rc = gh_dispatch("apply")
            if rc == 204:
                send_message(chat_id, f"The job is launched, please track the status.")
            else:
                send_message(chat_id, f"Cannot call GitHub, response code: {rc}. Please check the logs.")
                raise Exception

        elif presented_in(["status", "now", "track", "profile", "link", "config"], split):
            gh_track(chat_id)
            if prefix_exists(S3_BUCKET, S3_PROFILE):
                s = S3_CLIENT.generate_presigned_url("get_object", Params={"Bucket": S3_BUCKET, "Key": S3_PROFILE},
                                                     ExpiresIn=300)
                send_message(chat_id, f"Download your VPN profile by [this]({s}) link", "MarkdownV2")
            else:
                send_message(chat_id, "The profile is removed or not available yet.")

        elif presented_in(["thank"], message):
            send_message(chat_id, "I know you’d do the same for me.")

        elif presented_in(["destroy"], split):
            rc = gh_dispatch("destroy")
            if rc == 204:
                send_message(chat_id, f"The job is launched, please track the status.")
            else:
                send_message(chat_id, f"Cannot call GitHub, response code: {rc}. Please check the logs.")
                raise Exception
            s = S3_CLIENT.delete_object(Bucket=S3_BUCKET, Key=S3_PROFILE)

        elif presented_in(["bye"], message):
            send_message(chat_id, f"Talk to you soon, {first_name}!")

        else:
            send_message(chat_id, "Thank you... Thank you for being so dumb!")

    except Exception as e:
        print(e)

    return {"statusCode": 200}
