#!/usr/bin/env sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

env_file=".ai-review.env"

get_existing() {
  key="$1"
  if [ -f "$env_file" ]; then
    sed -n "s/^[[:space:]]*$key=//p" "$env_file" | tail -n 1
  fi
}

ask_default() {
  prompt="$1"
  default="$2"
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r value || value=""
  if [ -z "$value" ]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$value"
  fi
}

ask_choice() {
  prompt="$1"
  allowed="$2"
  default="$3"
  while :; do
    value="$(ask_default "$prompt ($allowed)" "$default")"
    case " $allowed " in
      *" $value "*) printf '%s\n' "$value"; return ;;
      *) printf 'Invalid value: %s\n' "$value" >&2 ;;
    esac
  done
}

write_config() {
  {
    printf '%s\n' "# AI review git hook config. Do not commit this file."
    printf '%s\n' "AI_REVIEW_ENABLED=true"
    printf '%s\n' "AI_REVIEW_API_KEY=$ai_key"
    printf '%s\n' "AI_REVIEW_MODEL=$model"
    printf '%s\n' "AI_REVIEW_BASE_URL=$base_url"
    printf '%s\n' ""
    printf '%s\n' "AI_REVIEW_COMPILE=false"
    printf '%s\n' "AI_REVIEW_RUN_TESTS=false"
    printf '%s\n' "AI_REVIEW_REQUIRE_API=false"
    printf '%s\n' "AI_REVIEW_FAIL_ON_AI_ERROR=false"
    printf '%s\n' "AI_REVIEW_FAIL_ON_FINDINGS=false"
    printf '%s\n' "AI_REVIEW_MAX_DIFF_BYTES=120000"
    printf '%s\n' "AI_REVIEW_TIMEOUT_SECONDS=90"
    printf '%s\n' ""
    printf '%s\n' "AI_REVIEW_NOTIFY_ON=$notify_on"
    printf '%s\n' "AI_REVIEW_DESKTOP_NOTIFY=$desktop_notify"
    printf '%s\n' "AI_REVIEW_DESKTOP_NOTIFY_SECONDS=$desktop_notify_seconds"
    [ -n "${feishu_webhook:-}" ] && printf '%s\n' "AI_REVIEW_FEISHU_WEBHOOK=$feishu_webhook"
    [ -n "${wechat_webhook:-}" ] && printf '%s\n' "AI_REVIEW_WECHAT_WEBHOOK=$wechat_webhook"
    [ -n "${dingtalk_webhook:-}" ] && printf '%s\n' "AI_REVIEW_DINGTALK_WEBHOOK=$dingtalk_webhook"
    if [ -n "${email_to:-}" ]; then
      printf '%s\n' "AI_REVIEW_EMAIL_TO=$email_to"
      printf '%s\n' "AI_REVIEW_EMAIL_FROM=$email_from"
      printf '%s\n' "AI_REVIEW_SMTP_HOST=$smtp_host"
      printf '%s\n' "AI_REVIEW_SMTP_PORT=$smtp_port"
      printf '%s\n' "AI_REVIEW_SMTP_USERNAME=$smtp_username"
      printf '%s\n' "AI_REVIEW_SMTP_PASSWORD=$smtp_password"
      printf '%s\n' "AI_REVIEW_SMTP_STARTTLS=$smtp_starttls"
      printf '%s\n' "AI_REVIEW_SMTP_SSL=$smtp_ssl"
    fi
  } > "$env_file"
}

ensure_gitignore() {
  ignore_file=".gitignore"
  [ -f "$ignore_file" ] || : > "$ignore_file"

  changed="false"
  if ! grep -qxF '.ai-review.env' "$ignore_file"; then
    printf '%s\n' '.ai-review.env' >> "$ignore_file"
    changed="true"
  fi

  if ! grep -qxF '/githooks/' "$ignore_file"; then
    printf '%s\n' '/githooks/' >> "$ignore_file"
    changed="true"
  fi

  if [ "$changed" = "true" ]; then
    printf '%s\n' "Updated .gitignore with .ai-review.env and /githooks/"
  else
    printf '%s\n' ".gitignore already ignores .ai-review.env and /githooks/"
  fi
}

ensure_dependencies() {
  missing=""

  command -v git >/dev/null 2>&1 || missing="$missing git"
  if ! command -v sh >/dev/null 2>&1 && ! command -v bash >/dev/null 2>&1; then
    missing="$missing sh-or-bash"
  fi
  command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || missing="$missing python"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"

  if [ -n "$missing" ]; then
    printf '%s\n' "Missing dependencies:$missing" >&2
    printf '%s\n' "Install them and re-run this script." >&2
    printf '%s\n' "macOS example: brew install git python curl" >&2
    printf '%s\n' "Debian/Ubuntu example: sudo apt-get install git python3 curl" >&2
    printf '%s\n' "RHEL/CentOS example: sudo yum install git python3 curl" >&2
    exit 1
  fi

  printf '%s\n' "Dependencies OK."
}

ensure_dependencies
git config core.hooksPath githooks
chmod +x githooks/pre-commit githooks/scripts/ai-review.sh 2>/dev/null || true
ensure_gitignore

printf '\nConfigure AI review hook for: %s\n' "$repo_root"
printf 'Press Enter to keep the value shown in brackets.\n\n'

base_url="$(ask_default "AI base URL" "$(get_existing AI_REVIEW_BASE_URL || true)")"
[ -n "$base_url" ] || base_url="https://api.openai.com/v1"
model="$(ask_default "AI model" "$(get_existing AI_REVIEW_MODEL || true)")"
[ -n "$model" ] || model="gpt-4o-mini"
ai_key="$(ask_default "AI API key" "$(get_existing AI_REVIEW_API_KEY || true)")"
notify_on="$(ask_choice "Notify when" "always fail error never" "$(get_existing AI_REVIEW_NOTIFY_ON || true)")"
[ -n "$notify_on" ] || notify_on="always"
desktop_notify="$(ask_choice "Enable desktop notification" "true false" "$(get_existing AI_REVIEW_DESKTOP_NOTIFY || true)")"
[ -n "$desktop_notify" ] || desktop_notify="true"
desktop_notify_seconds="$(get_existing AI_REVIEW_DESKTOP_NOTIFY_SECONDS || true)"
[ -n "$desktop_notify_seconds" ] || desktop_notify_seconds="8"
notify_type="$(ask_choice "Notification channel" "none feishu wechat dingtalk email" "none")"

case "$notify_type" in
  feishu)
    feishu_webhook="$(ask_default "Feishu robot webhook" "$(get_existing AI_REVIEW_FEISHU_WEBHOOK || true)")"
    ;;
  wechat)
    wechat_webhook="$(ask_default "WeCom robot webhook" "$(get_existing AI_REVIEW_WECHAT_WEBHOOK || true)")"
    ;;
  dingtalk)
    dingtalk_webhook="$(ask_default "DingTalk robot webhook" "$(get_existing AI_REVIEW_DINGTALK_WEBHOOK || true)")"
    ;;
  email)
    email_to="$(ask_default "Email recipient" "$(get_existing AI_REVIEW_EMAIL_TO || true)")"
    email_from="$(ask_default "Email sender" "$(get_existing AI_REVIEW_EMAIL_FROM || true)")"
    [ -n "$email_from" ] || email_from="$email_to"
    smtp_host="$(ask_default "SMTP host" "$(get_existing AI_REVIEW_SMTP_HOST || true)")"
    [ -n "$smtp_host" ] || smtp_host="smtp.163.com"
    smtp_port="$(ask_default "SMTP port" "$(get_existing AI_REVIEW_SMTP_PORT || true)")"
    [ -n "$smtp_port" ] || smtp_port="465"
    smtp_username="$(ask_default "SMTP username" "$(get_existing AI_REVIEW_SMTP_USERNAME || true)")"
    [ -n "$smtp_username" ] || smtp_username="$email_from"
    smtp_password="$(ask_default "SMTP password/auth code" "$(get_existing AI_REVIEW_SMTP_PASSWORD || true)")"
    smtp_ssl="$(ask_choice "SMTP SSL" "true false" "$(get_existing AI_REVIEW_SMTP_SSL || true)")"
    [ -n "$smtp_ssl" ] || smtp_ssl="true"
    smtp_starttls="$(ask_choice "SMTP STARTTLS" "true false" "$(get_existing AI_REVIEW_SMTP_STARTTLS || true)")"
    [ -n "$smtp_starttls" ] || smtp_starttls="false"
    ;;
esac

write_config

printf '\nGit hooks installed for: %s\n' "$repo_root"
printf '%s\n' "core.hooksPath=$(git config core.hooksPath)"
printf '%s\n' "Config written to: $env_file"
printf '%s\n' "Keep .ai-review.env ignored because it contains secrets."
