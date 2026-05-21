#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
scope="${1:-${AI_REVIEW_HOOK_SCOPE:-}}"
repo_root=""
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
      *) printf 'Invalid value / 无效输入: %s\n' "$value" >&2 ;;
    esac
  done
}

write_config() {
  {
    printf '%s\n' "# AI review git hook config. Do not commit this file. / AI review Git Hook 配置文件，请勿提交。"
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
    printf '%s\n' "AI_REVIEW_CONTEXT_ENABLED=$context_enabled"
    printf '%s\n' "AI_REVIEW_CONTEXT_MAX_BYTES=$context_max_bytes"
    printf '%s\n' "AI_REVIEW_CONTEXT_MAX_FILE_BYTES=$context_max_file_bytes"
    printf '%s\n' "AI_REVIEW_TIMEOUT_SECONDS=90"
    printf '%s\n' ""
    printf '%s\n' "AI_REVIEW_NOTIFY_ON=$notify_on"
    printf '%s\n' "AI_REVIEW_DESKTOP_NOTIFY=$desktop_notify"
    printf '%s\n' "AI_REVIEW_DESKTOP_NOTIFY_SECONDS=$desktop_notify_seconds"
    printf '%s\n' "AI_REVIEW_DESKTOP_OPEN_MODE=$desktop_open_mode"
    printf '%s\n' "AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT=$desktop_auto_open_report"
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
    printf '%s\n' "Updated .gitignore with .ai-review.env and /githooks/ / 已更新 .gitignore，忽略 .ai-review.env 和 /githooks/"
  else
    printf '%s\n' ".gitignore already ignores .ai-review.env and /githooks/ / .gitignore 已包含 .ai-review.env 和 /githooks/"
  fi
}

ensure_dependencies() {
  missing=""

  command -v git >/dev/null 2>&1 || missing="$missing git"
  if ! command -v sh >/dev/null 2>&1 && ! command -v bash >/dev/null 2>&1; then
    missing="$missing sh-or-bash"
  fi
  python_ok="false"
  for candidate in python python3 "py -3"; do
    # Intentionally expand fixed candidates so "py -3" works as command + arg.
    if $candidate -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      python_ok="true"
      break
    fi
  done
  [ "$python_ok" = "true" ] || missing="$missing python3"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"

  if [ -n "$missing" ]; then
    printf '%s\n' "Missing dependencies / 缺失依赖:$missing" >&2
    printf '%s\n' "Install them and re-run this script. / 请安装依赖后重新运行本脚本。" >&2
    printf '%s\n' "macOS example: brew install git python curl" >&2
    printf '%s\n' "Debian/Ubuntu example: sudo apt-get install git python3 curl" >&2
    printf '%s\n' "RHEL/CentOS example: sudo yum install git python3 curl" >&2
    exit 1
  fi

  printf '%s\n' "Dependencies OK. / 依赖检查通过。"
}

ensure_dependencies
if [ -z "$scope" ]; then
  default_scope="local"
  git rev-parse --show-toplevel >/dev/null 2>&1 || default_scope="global"
  scope="$(ask_choice "Install scope / 安装范围" "local global" "$default_scope")"
fi

case "$scope" in
  local|global) ;;
  *) printf '%s\n' "Invalid scope / 无效安装范围: $scope. Use local or global / 请使用 local 或 global。" >&2; exit 1 ;;
esac

if [ "$scope" = "local" ] && ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf '%s\n' "Local install requires running inside a Git repository. / 当前项目安装需要在 Git 仓库内运行。" >&2
  exit 1
fi

if [ "$scope" = "global" ]; then
  env_file="$HOME/.ai-review.env"
  git config --global core.hooksPath "$script_dir"
  chmod +x "$script_dir/pre-commit" "$script_dir/scripts/ai-review.sh" 2>/dev/null || true
else
  repo_root="$(git rev-parse --show-toplevel)"
  cd "$repo_root"
  env_file=".ai-review.env"
  git config core.hooksPath githooks
  chmod +x githooks/pre-commit githooks/scripts/ai-review.sh 2>/dev/null || true
  ensure_gitignore
fi

if [ "$scope" = "global" ]; then
  printf '\nConfigure AI review hook for / 配置 AI review hook: global\n'
else
  printf '\nConfigure AI review hook for / 配置 AI review hook: %s\n' "$repo_root"
fi
printf 'Press Enter to keep the value shown in brackets. / 直接回车保留方括号中的默认值。\n\n'

base_url="$(ask_default "AI base URL / AI 接口地址" "$(get_existing AI_REVIEW_BASE_URL || true)")"
[ -n "$base_url" ] || base_url="https://api.openai.com/v1"
model="$(ask_default "AI model / AI 模型" "$(get_existing AI_REVIEW_MODEL || true)")"
[ -n "$model" ] || model="gpt-4o-mini"
ai_key="$(ask_default "AI API key / AI API 密钥" "$(get_existing AI_REVIEW_API_KEY || true)")"
context_enabled="$(ask_choice "Send related project context / 发送相关项目上下文" "true false" "$(get_existing AI_REVIEW_CONTEXT_ENABLED || true)")"
[ -n "$context_enabled" ] || context_enabled="true"
context_max_bytes="$(ask_default "Max context bytes / 最大上下文字节数" "$(get_existing AI_REVIEW_CONTEXT_MAX_BYTES || true)")"
[ -n "$context_max_bytes" ] || context_max_bytes="80000"
context_max_file_bytes="$(ask_default "Max bytes per context file / 单个上下文文件最大字节数" "$(get_existing AI_REVIEW_CONTEXT_MAX_FILE_BYTES || true)")"
[ -n "$context_max_file_bytes" ] || context_max_file_bytes="20000"
notify_on="$(ask_choice "Notify when / 何时通知" "always fail error never" "$(get_existing AI_REVIEW_NOTIFY_ON || true)")"
[ -n "$notify_on" ] || notify_on="always"
desktop_notify="$(ask_choice "Enable desktop notification / 启用桌面通知" "true false" "$(get_existing AI_REVIEW_DESKTOP_NOTIFY || true)")"
[ -n "$desktop_notify" ] || desktop_notify="true"
desktop_notify_seconds="$(get_existing AI_REVIEW_DESKTOP_NOTIFY_SECONDS || true)"
[ -n "$desktop_notify_seconds" ] || desktop_notify_seconds="8"
desktop_open_mode="$(ask_choice "Desktop report open mode / 桌面报告打开方式" "native file" "$(get_existing AI_REVIEW_DESKTOP_OPEN_MODE || true)")"
[ -n "$desktop_open_mode" ] || desktop_open_mode="native"
desktop_auto_open_report="$(ask_choice "Auto open report dialog on macOS / macOS 自动弹出报告窗口" "false true" "$(get_existing AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT || true)")"
[ -n "$desktop_auto_open_report" ] || desktop_auto_open_report="false"
notify_type="$(ask_choice "Notification channel / 通知渠道" "none feishu wechat dingtalk email" "none")"

case "$notify_type" in
  feishu)
    feishu_webhook="$(ask_default "Feishu robot webhook / 飞书机器人 webhook" "$(get_existing AI_REVIEW_FEISHU_WEBHOOK || true)")"
    ;;
  wechat)
    wechat_webhook="$(ask_default "WeCom robot webhook / 企业微信机器人 webhook" "$(get_existing AI_REVIEW_WECHAT_WEBHOOK || true)")"
    ;;
  dingtalk)
    dingtalk_webhook="$(ask_default "DingTalk robot webhook / 钉钉机器人 webhook" "$(get_existing AI_REVIEW_DINGTALK_WEBHOOK || true)")"
    ;;
  email)
    email_to="$(ask_default "Email recipient / 收件邮箱" "$(get_existing AI_REVIEW_EMAIL_TO || true)")"
    email_from="$(ask_default "Email sender / 发件邮箱" "$(get_existing AI_REVIEW_EMAIL_FROM || true)")"
    [ -n "$email_from" ] || email_from="$email_to"
    smtp_host="$(ask_default "SMTP host / SMTP 服务器" "$(get_existing AI_REVIEW_SMTP_HOST || true)")"
    [ -n "$smtp_host" ] || smtp_host="smtp.163.com"
    smtp_port="$(ask_default "SMTP port / SMTP 端口" "$(get_existing AI_REVIEW_SMTP_PORT || true)")"
    [ -n "$smtp_port" ] || smtp_port="465"
    smtp_username="$(ask_default "SMTP username / SMTP 用户名" "$(get_existing AI_REVIEW_SMTP_USERNAME || true)")"
    [ -n "$smtp_username" ] || smtp_username="$email_from"
    smtp_password="$(ask_default "SMTP password/auth code / SMTP 密码或授权码" "$(get_existing AI_REVIEW_SMTP_PASSWORD || true)")"
    smtp_ssl="$(ask_choice "SMTP SSL" "true false" "$(get_existing AI_REVIEW_SMTP_SSL || true)")"
    [ -n "$smtp_ssl" ] || smtp_ssl="true"
    smtp_starttls="$(ask_choice "SMTP STARTTLS" "true false" "$(get_existing AI_REVIEW_SMTP_STARTTLS || true)")"
    [ -n "$smtp_starttls" ] || smtp_starttls="false"
    ;;
esac

write_config

if [ "$scope" = "global" ]; then
  printf '\nGit hooks installed for / Git hooks 已安装到: global\n'
  printf '%s\n' "global core.hooksPath=$(git config --global core.hooksPath)"
else
  printf '\nGit hooks installed for / Git hooks 已安装到: %s\n' "$repo_root"
  printf '%s\n' "core.hooksPath=$(git config core.hooksPath)"
fi
printf '%s\n' "Config written to / 配置已写入: $env_file"
if [ "$scope" = "global" ]; then
  printf '%s\n' "Global config is stored in your user home and is not part of project commits. / 全局配置保存在用户目录，不属于项目提交内容。"
else
  printf '%s\n' "Keep .ai-review.env ignored because it contains secrets. / .ai-review.env 包含密钥，请保持忽略，不要提交。"
fi
