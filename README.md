
# VPN Telegram AI Bot

This project was created to demonstrate the capabilities of cloud engineering and process automation using various CI/CD and IaC tools.

By talking with the [Telegram chatbot](https://core.telegram.org/bots/api) in plain language (an AI model picks the action) or by tapping its buttons, the user can create his own [WireGuard](https://www.wireguard.com/) or [OpenVPN](https://openvpn.net/) server with a dedicated public IP address either in AWS Stockholm or in Yandex Cloud. When the work is done, the entire infrastructure can be automatically destroyed.

This is just an example of such an implementation that can be (and will be) endlessly improved in many ways.

<a href="url"><img src="images/screenshot.png?raw=true" align="center" height=55% width=55% ></a>
## Tech Stack

**Cloud:** AWS, Yandex Cloud

**IaC:** Terraform

**VPN Server:** WireGuard or OpenVPN, Ubuntu 24.04 LTS, [cloud-init](https://cloud-init.io/)

**Telegram bot:** AWS Lambda (Python 3.13), AWS API Gateway (HTTP API)

**AI:** Amazon Bedrock (Amazon Nova Micro) with tool use for free-text messages, keyword parser as a fallback

**CI/CD:** GitHub Actions

Technically, the process is structured as follows:

When receiving a new message, Telegram calls a webhook configured in AWS API Gateway which launches a handler function in AWS Lambda. The webhook is protected with a secret token, and the bot only talks to allowed chat IDs. The function and the API are deployed with Terraform by GitHub Actions.

Depending on the selected action the bot will respond and launch the `deploy_vpn.yml` workflow in GitHub Actions with the target cloud and protocol. Before applying, the workflow generates a temporary presigned S3 POST that allows uploading files only under `profiles/<cloud>/`. Terraform creates the server with a static public IP and passes the bootstrap script, VPN configs and the upload credentials in the server's user data as a [cloud-init](https://cloud-init.io/) config (cloud-init is the standard first-boot initialization tool of cloud Linux images; the config is rendered by the `terraform/modules/cloud-init` module), so the server needs no cloud credentials at all. The script installs WireGuard (keys and a QR code per client) or OpenVPN (Certification Authority and certificates), configures IP forwarding and the firewall, builds client profiles and uploads them to S3. Download links (temporary S3 presigned URLs) and QR codes are sent to the user by the Telegram bot.

## Bot commands

| Menu command | Same as text | Action |
|---|---|---|
| `/deploy` | `deploy` | WireGuard server in AWS Stockholm |
| `/deploy_openvpn` | `deploy openvpn` | OpenVPN on 443/tcp in AWS, for networks where UDP is blocked |
| `/deploy_yandex` | `deploy yandex` | WireGuard server in Yandex Cloud |
| `/deploy_yandex_openvpn` | `deploy yandex openvpn` | OpenVPN on 443/tcp in Yandex Cloud |
| `/status` | `status`, `profiles`, `link` | Last job status, profile links and QR codes |
| `/why` | `why` | Why the last job failed |
| `/destroy` | `destroy` | Destroy the AWS server, after confirmation |
| `/destroy_yandex` | `destroy yandex` | Destroy the Yandex Cloud server, after confirmation |

The menu is registered in Telegram by the bot deployment workflow. Menu commands cannot contain spaces, so the bot reads `_` as a space; any command also works as plain text, with or without the slash. A few extra text commands are not in the menu: `profile` (profile links only), `qr` (QR codes only, for the WireGuard mobile app) and `start` / `hi` (greeting).

Every reply of the bot carries a persistent keyboard with the main commands, so they are one tap away:

| | | |
|---|---|---|
| 🚀 Deploy | 🔐 Deploy OpenVPN | |
| 🚀 Deploy Yandex | 🔐 Deploy Yandex OpenVPN | |
| 📊 Status | 💥 Destroy | 💥 Destroy Yandex |

A button sends its label as a message, and the bot maps it to the matching command (`deploy yandex openvpn`, `status` and so on), so it works exactly like the typed command.

### Free text

Anything else can be written in plain words: *"spin up a VPN in Yandex that works over TCP"*, *"send me the QR code"*, *"why did the last deploy fail?"*, *"tear it down"*. Such messages go to [Amazon Nova Micro](https://aws.amazon.com/nova/) in Amazon Bedrock through the Converse API with tool use. The model only picks one of the bot's actions (`deploy`, `destroy`, `status`, `profiles`, `profile`, `qr`, `explain_failure`) and its arguments, or replies to small talk; the actions themselves are the same deterministic functions the commands use, and their arguments are validated before use.

- **Exact commands skip the model.** Keyboard buttons, menu commands (with or without `@BotName`) and `start` / `hi` go straight to the handlers, so they are instant and cost nothing.
- **Confirmation.** `destroy` always asks for an inline *✅ Yes, destroy* / *❌ Cancel* confirmation, whether it comes from a button, a command or free text. `deploy` from a button or a command starts at once, while `deploy` understood from free text is confirmed with *✅ Yes, deploy* / *❌ Cancel*, so a misunderstood message never launches a job. The confirmation carries the action in its callback data, so no state is stored; it expires after 10 minutes, and the buttons are removed once pressed.
- **Fallback.** If Bedrock fails, times out (8 s) or returns nothing usable, the message is handled by the keyword parser, so the bot keeps working without the model. An empty `bedrock_model_id` turns the model off completely.
- **Why it failed.** `/why` or a question about a failure fetches the log of the failed job of the last `deploy_vpn.yml` run through the GitHub API and asks the model, with no tools available, for a short explanation and the likely fix. The log is downloaded from GitHub's blob storage without the GitHub token. Without the model, the bot sends the end of the log.

WireGuard creates a profile per device (`phone` and `laptop` by default, see the `wireguard_peers` variable), since one WireGuard key cannot be used by two devices at the same time.

## Architecture

```mermaid
flowchart TD
    user(["User"]) <-->|"deploy / status / destroy, free text<br/>profile links, QR codes"| tg["Telegram"]
    tg -->|"webhook + secret token"| api

    subgraph bot_stack["Telegram bot · terraform/bot"]
        api["API Gateway<br/>HTTP API"] --> bot["Lambda<br/>tg-bot"]
    end

    bot <-->|"free text → tool call<br/>IAM role, no API key"| llm["Amazon Bedrock<br/>Nova Micro"]
    bot -->|"workflow_dispatch<br/>action, cloud, protocol"| gha["GitHub Actions<br/>deploy_vpn.yml"]
    gha -->|"AWS OIDC role /<br/>Yandex Cloud WIF"| tf["Terraform"]

    subgraph servers["VPN server · terraform/aws, terraform/yandex"]
        ec2["EC2 + Elastic IP<br/>AWS Stockholm"]
        ycvm["Compute VM<br/>Yandex Cloud"]
    end

    tf --> ec2
    tf -.-> ycvm
    ec2 -->|"cloud-init: WireGuard / OpenVPN<br/>profiles + QR via presigned POST"| s3[("S3<br/>Terraform state + profiles")]
    ycvm -.-> s3
    s3 -->|"presigned links"| bot
    bot -->|"replies"| tg
```

## Repository layout

| Path | What |
|---|---|
| `terraform/bootstrap` | State bucket, GitHub OIDC provider and role, applied locally (state key `bootstrap/terraform.tfstate`) |
| `terraform/aws` | VPN server in AWS (state key `terraform/terraform.tfstate`) |
| `terraform/yandex` | VPN server in Yandex Cloud (state key `terraform/yandex.tfstate`) |
| `terraform/bot` | Telegram bot: Lambda, HTTP API, IAM (state key `terraform/bot.tfstate`) |
| `terraform/modules/cloud-init` | Renders the cloud-init config (bootstrap script, VPN configs, upload credentials) shared by both clouds |
| `scripts/bootscript.sh`, `configs/` | Server bootstrap, WireGuard and OpenVPN configs |

All states are stored in the same S3 bucket; the bucket and region are passed with `-backend-config`:

```bash
terraform -chdir=terraform/aws init -backend-config="bucket=<bucket>" -backend-config="region=eu-north-1"
```

## Setup

GitHub repository variables:

| Variable | Description |
|---|---|
| `GH_ROLE` | AWS IAM role assumed via GitHub OIDC |
| `AWS_REGION` | AWS region, the same as the bucket region |
| `S3_BUCKET` | Bucket for Terraform states and client profiles |
| `TELEGRAM_ALLOWED_CHAT_IDS` | Comma-separated chat IDs allowed to use the bot |
| `YC_CLOUD_ID`, `YC_FOLDER_ID` | Yandex Cloud cloud and folder |
| `YC_SA_ID` | Yandex Cloud service account used by GitHub Actions |

GitHub repository secrets: `TELEGRAM_TOKEN`, `GH_TOKEN` (fine-grained token with `Actions: read and write` on this repository).

### Amazon Bedrock

The bot calls Bedrock with its Lambda role, so there is no API key to store. The default model is the EU cross-region inference profile `eu.amazon.nova-micro-v1:0` (`bedrock_model_id` in `terraform/bot`): requests from `eu-north-1` are served in EU regions only, and the role gets `bedrock:InvokeModel` on the profile and on the model in the regions it routes to. The bot's permissions boundary (see below) allows only Amazon Nova models, so apply `terraform/bootstrap` before deploying a bot version that uses Bedrock.

Check the account's Bedrock quotas in Service Quotas for `eu-north-1`: *Cross-region model inference requests per minute* and *Model invocation max tokens per day* for Amazon Nova Micro. New and low-spend accounts may have them at 0, and these quotas can only be raised through an AWS Support case. Until then every call is throttled and the bot simply stays on keywords.

At about 2,000 input and 300 output tokens per message, the model costs a small fraction of a cent per message.

### Bootstrap

`terraform/bootstrap` manages what the workflows themselves depend on, so it is applied locally with admin credentials rather than by GitHub Actions:

- the S3 bucket: versioning, SSE-S3 encryption with SSE-C blocked, public access block, TLS-only bucket policy, lifecycle that keeps the last 5 old versions of every file and expires older ones after 30 days, and expires old versions of deleted client profiles after 1 day;
- the GitHub OIDC provider and the `GH_ROLE` role. The role trusts only the `main` branch of this repository by GitHub's immutable OIDC subject, which includes the owner and repository IDs, so a repository recreated under the same name cannot assume it. After a rename update `github_owner` / `github_repository`;
- a least-privilege inline policy of the role: the Terraform states and their locks, `profiles/`, the VPN server in EC2, and the bot's Lambda, HTTP API, log group and IAM role;
- the permissions boundary of the bot's Lambda role. The GitHub role can write the bot role's policies only while this boundary is set, so it cannot grant itself more through the bot. Besides the logs and the profiles, the boundary allows invoking Amazon Nova models in Bedrock.

The state is kept under `bootstrap/`, out of the GitHub role's reach:

```bash
terraform -chdir=terraform/bootstrap init -backend-config="bucket=<bucket>" -backend-config="region=eu-north-1"
terraform -chdir=terraform/bootstrap apply
```

The bucket and the role were originally created by hand and are adopted with `import` blocks (`imports.tf`), so the first apply changes them in place. In a new account, create the bucket by hand first, since the state lives in it, drop the `import` blocks of the OIDC provider and the role, and set the `github_*` variables (IDs: `gh api repos/<owner>/<repo> --jq '.owner.id, .id'`).

### Yandex Cloud

GitHub Actions authenticates in Yandex Cloud with [Workload Identity Federation](https://yandex.cloud/en/docs/iam/concepts/workload-identity), no static keys are stored:

1. Create a service account with the `compute.editor` and `vpc.admin` roles on the folder.
2. Create an OIDC federation: issuer `https://token.actions.githubusercontent.com`, audience `https://github.com/<github_owner>`, JWKS `https://token.actions.githubusercontent.com/.well-known/jwks`.
3. Link the service account to the federation with the subject `repo:<github_owner>/<repository>:ref:refs/heads/main`.
4. Set `YC_SA_ID`, `YC_CLOUD_ID` and `YC_FOLDER_ID` variables in the repository.

## Versions

- [v1.0](https://github.com/eosklv/VPN-Telegram-AI-Bot/releases/tag/v1.0) — the original version: OpenVPN in AWS only, Telegram bot deployed with Serverless Framework.
- v2.0 — WireGuard, Yandex Cloud, everything deployed with Terraform.

## Author

- [Eugeny Sokolov](https://linkedin.com/in/esklv)
