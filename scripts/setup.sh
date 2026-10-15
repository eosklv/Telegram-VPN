#!/usr/bin/env bash
# Sets this repository up in your AWS account and on GitHub: applies terraform/bootstrap, sets the
# repository variables and secrets and deploys the Telegram bot. Safe to re-run.
#
# Usage: scripts/setup.sh [--dry-run]
#   --dry-run   plans terraform/bootstrap in a temporary copy and prints the GitHub changes,
#               nothing is changed in AWS, on GitHub or in the working tree
#
# Environment:
#   AWS_PROFILE      AWS credentials to use (admin rights in the target account)
#   TERRAFORM        Terraform >= 1.10 binary, terraform by default
#   SETUP_REGION, SETUP_BUCKET, SETUP_CHAT_IDS, SETUP_TELEGRAM_TOKEN, SETUP_GITHUB_BOT_TOKEN
#                    answers to the prompts, for non-interactive runs

set -euo pipefail

DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) sed -n '5,7p' "$0" >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TF_DIR="$ROOT/terraform/bootstrap"
TF=${TERRAFORM:-terraform}
STATE_KEY=bootstrap/terraform.tfstate
MIN_TF_VERSION=1.10.0

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if $DRY_RUN; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

version_ge() {
  local i a b
  IFS=. read -r -a a <<< "${1%%-*}"
  IFS=. read -r -a b <<< "${2%%-*}"
  for i in 0 1 2; do
    ((${a[i]:-0} > ${b[i]:-0})) && return 0
    ((${a[i]:-0} < ${b[i]:-0})) && return 1
  done
  return 0
}

# ask <var> <prompt> [default], SETUP_<var> answers without a prompt
ask() {
  local preset="SETUP_$1" value
  value=${!preset:-}
  if [ -z "$value" ]; then
    read -r -p "$2${3:+ [$3]}: " value
  fi
  printf -v "$1" '%s' "${value:-${3:-}}"
}

# ask_secret <var> <prompt> <has current value>, empty keeps the current value
ask_secret() {
  local preset="SETUP_$1" value
  value=${!preset:-}
  if [ -z "$value" ]; then
    if $3; then
      read -r -s -p "$2 (Enter keeps the current one): " value
    else
      read -r -s -p "$2: " value
    fi
    echo
  fi
  printf -v "$1" '%s' "$value"
}

confirm() {
  local answer
  read -r -p "$1 [Y/n]: " answer
  case "$answer" in [nN]*) return 1 ;; esac
}

tfvar() {
  if [ -f "$TFVARS" ]; then
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$TFVARS" | head -n 1
  fi
}

# set_tfvar <name> <HCL value>, replaces the uncommented assignment or appends one
set_tfvar() {
  local tmp
  tmp=$(mktemp)
  awk -v k="$1" -v v="$2" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { if (!done) print k " = " v; done = 1; next }
    { print }
    END { if (!done) print k " = " v }' "$TFVARS" > "$tmp"
  mv "$tmp" "$TFVARS"
}

tf() { "$TF" -chdir="$WORK_DIR" "$@"; }

gh_variable() { gh api "repos/$REPO/actions/variables/$1" --jq .value 2> /dev/null || true; }

set_secret() {
  if $DRY_RUN; then
    printf '[dry-run] gh secret set %s -R %s\n' "$1" "$REPO"
  else
    printf '%s' "$2" | gh secret set "$1" -R "$REPO"
  fi
}

say "Checking the tools"
for cmd in aws gh curl awk "$TF"; do
  command -v "$cmd" > /dev/null || die "$cmd is not installed"
done
tf_version=$("$TF" version -json | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p')
version_ge "$tf_version" "$MIN_TF_VERSION" ||
  die "Terraform $tf_version is too old, $MIN_TF_VERSION or newer is required (set TERRAFORM to another binary)"
gh auth status > /dev/null 2>&1 || die "gh is not logged in, run: gh auth login"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text) ||
  die "No AWS credentials, set AWS_PROFILE or run: aws configure"

cd "$ROOT"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
IFS=$'\t' read -r OWNER OWNER_ID NAME REPO_ID < <(gh api "repos/$REPO" --jq '[.owner.login, .owner.id, .name, .id] | @tsv') ||
  die "Cannot read $REPO from GitHub"
echo "Terraform $tf_version, AWS account $ACCOUNT, GitHub repository $REPO"
$DRY_RUN || confirm "Set up the bot in this account and repository?" || exit 1

# A dry run works on a copy, so the working tree and its .terraform keep pointing at the real state
if $DRY_RUN; then
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  cp "$TF_DIR"/*.tf "$TF_DIR"/.terraform.lock.hcl "$WORK_DIR"/
  for f in terraform.tfvars terraform.tfstate; do
    if [ -f "$TF_DIR/$f" ]; then
      cp "$TF_DIR/$f" "$WORK_DIR"/
    fi
  done
  rm -f "$WORK_DIR"/*_override.tf
else
  WORK_DIR=$TF_DIR
fi
TFVARS="$WORK_DIR/terraform.tfvars"
OVERRIDE="$WORK_DIR/local_backend_override.tf"
LOCAL_STATE="$WORK_DIR/terraform.tfstate"

say "Settings"
default_region=$(tfvar region)
[ -n "$default_region" ] || default_region=$(gh_variable AWS_REGION)
[ -n "$default_region" ] || default_region=$(aws configure get region || true)
ask REGION "AWS region" "$default_region"
[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || die "Not an AWS region: '$REGION'"

default_bucket=$(tfvar bucket_name)
[ -n "$default_bucket" ] || default_bucket=$(gh_variable S3_BUCKET)
[ -n "$default_bucket" ] || default_bucket="vpn-$ACCOUNT-$REGION"
ask BUCKET "S3 bucket for Terraform states and VPN profiles (globally unique)" "$default_bucket"
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || die "Not a valid bucket name: '$BUCKET'"

ask CHAT_IDS "Telegram chat IDs allowed to use the bot, comma-separated (@userinfobot shows yours)" \
  "$(gh_variable TELEGRAM_ALLOWED_CHAT_IDS)"
[[ "$CHAT_IDS" =~ ^-?[0-9]+(,-?[0-9]+)*$ ]] || die "Chat IDs must be numbers separated by commas: '$CHAT_IDS'"

secrets=$(gh secret list -R "$REPO" --json name --jq '.[].name' 2>/dev/null || true)
has_secret() { grep -qx "$1" <<< "$secrets"; }

ask_secret TELEGRAM_TOKEN "Telegram bot token from @BotFather" "$(has_secret TELEGRAM_TOKEN && echo true || echo false)"
if [ -n "$TELEGRAM_TOKEN" ]; then
  bot=$(printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$TELEGRAM_TOKEN" | curl -sSf -K - |
    sed -n 's/.*"username":"\([^"]*\)".*/\1/p') || die "Telegram does not accept the bot token"
  echo "Telegram bot: @$bot"
elif ! has_secret TELEGRAM_TOKEN; then
  die "The Telegram bot token is required"
fi

# Not GH_TOKEN: gh itself reads that variable
ask_secret GITHUB_BOT_TOKEN "GitHub fine-grained token for the bot (this repository, Actions: read and write)" \
  "$(has_secret GH_TOKEN && echo true || echo false)"
if [ -n "$GITHUB_BOT_TOKEN" ]; then
  printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_BOT_TOKEN" |
    curl -sSf -K - -o /dev/null "https://api.github.com/repos/$REPO/actions/workflows" ||
    die "The GitHub token cannot read the Actions of $REPO"
elif ! has_secret GH_TOKEN; then
  die "The GitHub token is required"
fi

# The role trusts the exact OIDC subject the repository issues
sub_prefix=$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null || true)
case "$sub_prefix" in
  "repo:$OWNER@$OWNER_ID/$NAME@$REPO_ID") IMMUTABLE=true ;;
  "repo:$OWNER/$NAME") IMMUTABLE=false ;;
  "")
    IMMUTABLE=true
    warn "Cannot read the OIDC subject format of $REPO, assuming immutable subjects"
    ;;
  *) die "The custom OIDC subject '$sub_prefix' of $REPO is not supported, see terraform/bootstrap/main.tf" ;;
esac

say "Bootstrap: state bucket and GitHub role"
[ -f "$TFVARS" ] || cp "$TF_DIR/terraform.tfvars.example" "$TFVARS"
set_tfvar region "\"$REGION\""
set_tfvar bucket_name "\"$BUCKET\""
set_tfvar github_owner "\"$OWNER\""
set_tfvar github_owner_id "$OWNER_ID"
set_tfvar github_repository "\"$NAME\""
set_tfvar github_repository_id "$REPO_ID"
set_tfvar github_immutable_subject "$IMMUTABLE"
"$TF" fmt "$TFVARS" > /dev/null

# The bootstrap state lives in the bucket it creates: the first apply runs with a local state,
# which is then migrated into the bucket
if head=$(aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>&1); then
  if aws s3api head-object --bucket "$BUCKET" --key "$STATE_KEY" --region "$REGION" > /dev/null 2>&1; then
    MODE=remote
  elif [ -f "$LOCAL_STATE" ]; then
    MODE=local
  elif [ "$(tfvar import_existing)" = true ]; then
    MODE=remote
  else
    die "Bucket $BUCKET exists but has no $STATE_KEY: choose another name, or set import_existing = true in terraform/bootstrap/terraform.tfvars to adopt it"
  fi
elif grep -qE "Not Found|404" <<< "$head"; then
  MODE=local
else
  die "Bucket $BUCKET is not accessible (owned by another account or in another region): $head"
fi

backend_config=(-backend-config="bucket=$BUCKET" -backend-config="region=$REGION")
if [ "$MODE" = local ]; then
  echo "First run: the state stays local until the bucket exists"
  printf 'terraform {\n  backend "local" {}\n}\n' > "$OVERRIDE"
  tf init -input=false -reconfigure > /dev/null
else
  echo "State: s3://$BUCKET/$STATE_KEY"
  rm -f "$OVERRIDE"
  tf init -input=false -reconfigure "${backend_config[@]}" > /dev/null
fi

# An account can have one GitHub OIDC provider only, an existing one outside this state is reused
managed=$(tf state list 2> /dev/null || true)
if ! grep -q '^aws_iam_openid_connect_provider\.github' <<< "$managed" && [ -z "$(tfvar github_oidc_provider_arn)" ]; then
  oidc_arn=$(aws iam list-open-id-connect-providers --output text \
    --query "OpenIDConnectProviderList[?ends_with(Arn, '/token.actions.githubusercontent.com')].Arn")
  if [ -n "$oidc_arn" ] && [ "$oidc_arn" != None ]; then
    echo "Reusing the GitHub OIDC provider $oidc_arn"
    set_tfvar github_oidc_provider_arn "\"$oidc_arn\""
    "$TF" fmt "$TFVARS" > /dev/null
  fi
fi

if $DRY_RUN; then
  tf plan -input=false -lock=false
  role_name=$(tfvar github_role_name)
  GH_ROLE="arn:aws:iam::$ACCOUNT:role/${role_name:-vpn-github-actions}"
  [ "$MODE" = remote ] || printf '[dry-run] then: terraform init -migrate-state into s3://%s/%s\n' "$BUCKET" "$STATE_KEY"
else
  tf apply
  if [ "$MODE" = local ]; then
    echo "Moving the state into s3://$BUCKET/$STATE_KEY"
    rm -f "$OVERRIDE"
    tf init -input=false -migrate-state -force-copy "${backend_config[@]}" > /dev/null
    tf state list > /dev/null
    if [ -f "$LOCAL_STATE" ]; then
      mv "$LOCAL_STATE" "$LOCAL_STATE.migrated"
    fi
  fi
  GH_ROLE=$(tf output -raw github_role_arn)
fi

say "GitHub repository variables and secrets"
run gh variable set GH_ROLE -R "$REPO" --body "$GH_ROLE"
run gh variable set AWS_REGION -R "$REPO" --body "$REGION"
run gh variable set S3_BUCKET -R "$REPO" --body "$BUCKET"
run gh variable set TELEGRAM_ALLOWED_CHAT_IDS -R "$REPO" --body "$CHAT_IDS"
[ -z "$TELEGRAM_TOKEN" ] || set_secret TELEGRAM_TOKEN "$TELEGRAM_TOKEN"
[ -z "$GITHUB_BOT_TOKEN" ] || set_secret GH_TOKEN "$GITHUB_BOT_TOKEN"

say "Amazon Bedrock quotas in $REGION"
quotas=$(aws service-quotas list-service-quotas --service-code bedrock --region "$REGION" --output text \
  --query "Quotas[?contains(QuotaName, 'requests per minute for Amazon Nova Micro') || contains(QuotaName, 'max tokens per day for Amazon Nova Micro')].[Value, QuotaName]" \
  2> /dev/null || true)
if [ -n "$quotas" ]; then
  echo "$quotas"
fi
if [ -z "$quotas" ] || grep -q '^0\.0' <<< "$quotas"; then
  warn "Amazon Nova Micro needs non-zero quotas in Service Quotas ($REGION, Amazon Bedrock); new accounts may have" \
    "them at 0 and only an AWS Support case raises them. Until then the bot understands commands and keywords only."
fi

say "Deploying the bot"
actions_enabled=$(gh api "repos/$REPO/actions/permissions" --jq .enabled 2> /dev/null || echo unknown)
workflow_state=$(gh api "repos/$REPO/actions/workflows/deploy_bot.yml" --jq .state 2> /dev/null || echo unknown)
if [ "$actions_enabled" != true ] || [ "$workflow_state" != active ]; then
  warn "GitHub Actions or its workflows are disabled in $REPO (actions enabled: $actions_enabled, deploy_bot: $workflow_state)." \
    "Enable them on https://github.com/$REPO/actions and run: gh workflow run deploy_bot.yml -R $REPO --ref main"
elif $DRY_RUN || confirm "Run the deploy_bot workflow now?"; then
  run gh workflow run deploy_bot.yml -R "$REPO" --ref main
  echo "Follow it with: gh run watch -R $REPO \$(gh run list -R $REPO -w deploy_bot.yml -L 1 --json databaseId --jq '.[0].databaseId')"
  bot_name=${bot:+@$bot}
  echo "When it is green, write /start to ${bot_name:-the bot} in Telegram."
fi
