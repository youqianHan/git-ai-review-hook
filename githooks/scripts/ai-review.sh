#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

load_config() {
  config_file="$1"
  if [ -f "$config_file" ]; then
    # shellcheck disable=SC1090
    . "$config_file"
  fi
}

load_config "$HOME/.ai-review.env"
load_config "$repo_root/.ai-review.env"

: "${AI_REVIEW_ENABLED:=true}"
: "${AI_REVIEW_COMPILE:=false}"
: "${AI_REVIEW_RUN_TESTS:=false}"
: "${AI_REVIEW_REQUIRE_API:=false}"
: "${AI_REVIEW_FAIL_ON_AI_ERROR:=$AI_REVIEW_REQUIRE_API}"
: "${AI_REVIEW_FAIL_ON_FINDINGS:=false}"
: "${AI_REVIEW_MODEL:=gpt-4o-mini}"
: "${AI_REVIEW_BASE_URL:=https://api.openai.com/v1/chat/completions}"
: "${AI_REVIEW_MAX_DIFF_BYTES:=120000}"
: "${AI_REVIEW_TIMEOUT_SECONDS:=90}"
: "${AI_REVIEW_REPORT_DIR:=.git/ai-review}"
: "${AI_REVIEW_NOTIFY_ON:=always}"
: "${AI_REVIEW_NOTIFY_PREVIEW_LINES:=80}"
: "${AI_REVIEW_ASYNC:=true}"
: "${AI_REVIEW_JOB_ID:=latest}"

if [ "$AI_REVIEW_ENABLED" = "false" ]; then
  log "[ai-review] skipped: AI_REVIEW_ENABLED=false"
  exit 0
fi

if [ -z "${AI_REVIEW_DIFF_FILE:-}" ] && git diff --cached --quiet --exit-code; then
  log "[ai-review] skipped: no staged changes"
  exit 0
fi

mkdir -p "$AI_REVIEW_REPORT_DIR"
report_file="$AI_REVIEW_REPORT_DIR/last-review.md"
diff_file="${AI_REVIEW_DIFF_FILE:-$AI_REVIEW_REPORT_DIR/staged.diff}"
build_file="$AI_REVIEW_REPORT_DIR/build.log"
request_file="$AI_REVIEW_REPORT_DIR/request.json"
response_file="$AI_REVIEW_REPORT_DIR/response.json"
notification_file="$AI_REVIEW_REPORT_DIR/notification.txt"

chat_completions_url() {
  url="${AI_REVIEW_BASE_URL%/}"
  case "$url" in
    */chat/completions)
      printf '%s\n' "$url"
      ;;
    */v1)
      printf '%s/chat/completions\n' "$url"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

detect_build_command() {
  if [ -n "${AI_REVIEW_BUILD_CMD:-}" ]; then
    printf '%s\n' "$AI_REVIEW_BUILD_CMD"
    return
  fi

  if [ -f "mvnw.cmd" ]; then
    printf '%s\n' './mvnw.cmd -q -DskipTests compile'
  elif [ -f "mvnw" ]; then
    printf '%s\n' './mvnw -q -DskipTests compile'
  elif [ -f "pom.xml" ]; then
    printf '%s\n' 'mvn -q -DskipTests compile'
  elif [ -f "gradlew.bat" ]; then
    printf '%s\n' './gradlew.bat compileJava'
  elif [ -f "gradlew" ]; then
    printf '%s\n' './gradlew compileJava'
  elif [ -f "package.json" ]; then
    if command -v npm >/dev/null 2>&1; then
      printf '%s\n' 'npm run build --if-present'
    else
      printf '%s\n' ''
    fi
  else
    printf '%s\n' ''
  fi
}

detect_test_command() {
  if [ -n "${AI_REVIEW_TEST_CMD:-}" ]; then
    printf '%s\n' "$AI_REVIEW_TEST_CMD"
    return
  fi

  if [ -f "mvnw.cmd" ]; then
    printf '%s\n' './mvnw.cmd -q test'
  elif [ -f "mvnw" ]; then
    printf '%s\n' './mvnw -q test'
  elif [ -f "pom.xml" ]; then
    printf '%s\n' 'mvn -q test'
  elif [ -f "gradlew.bat" ]; then
    printf '%s\n' './gradlew.bat test'
  elif [ -f "gradlew" ]; then
    printf '%s\n' './gradlew test'
  elif [ -f "package.json" ]; then
    if command -v npm >/dev/null 2>&1; then
      printf '%s\n' 'npm test -- --runInBand'
    else
      printf '%s\n' ''
    fi
  else
    printf '%s\n' ''
  fi
}

run_command() {
  label="$1"
  command_text="$2"

  if [ -z "$command_text" ]; then
    log "[ai-review] $label skipped: no command detected"
    return 0
  fi

  log "[ai-review] running $label: $command_text"
  if sh -c "$command_text" >"$build_file" 2>&1; then
    log "[ai-review] $label passed"
    return 0
  fi

  warn "[ai-review] $label failed. Log: $build_file"
  tail -n 80 "$build_file" >&2 || true
  return 1
}

send_notifications() {
  status="$1"
  message_file="$2"

  case "$AI_REVIEW_NOTIFY_ON" in
    never)
      return 0
      ;;
    fail)
      if ! grep -qi '^结论:[[:space:]]*FAIL' "$message_file" 2>/dev/null; then
        return 0
      fi
      ;;
    error)
      if [ "$status" != "error" ]; then
        return 0
      fi
      ;;
    always)
      ;;
    *)
      warn "[ai-review] unknown AI_REVIEW_NOTIFY_ON=$AI_REVIEW_NOTIFY_ON, skip notifications"
      return 0
      ;;
  esac

  if [ -n "${AI_REVIEW_WECHAT_WEBHOOK:-}" ]; then
    if command -v python >/dev/null 2>&1; then
      if python - "$message_file" "$repo_root" "$AI_REVIEW_NOTIFY_PREVIEW_LINES" > "$AI_REVIEW_REPORT_DIR/wechat-payload.json" <<'PY'
import json
import pathlib
import sys

message_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
try:
    max_lines = max(1, int(sys.argv[3]))
except ValueError:
    max_lines = 80
text = message_path.read_text(encoding="utf-8", errors="replace")
preview = "\n".join(text.splitlines()[:max_lines])
payload = {
    "msgtype": "markdown",
    "markdown": {
        "content": f"**AI Commit Review**\n> 仓库: {repo_root.name}\n\n{preview}"
    },
}
print(json.dumps(payload, ensure_ascii=False))
PY
      then
        curl -sS --max-time 15 \
          -H "Content-Type: application/json" \
          -X POST "$AI_REVIEW_WECHAT_WEBHOOK" \
          --data-binary "@$AI_REVIEW_REPORT_DIR/wechat-payload.json" >/dev/null \
          || warn "[ai-review] failed to send WeCom notification"
      else
        warn "[ai-review] failed to build WeCom notification payload"
      fi
    else
      warn "[ai-review] python is not available, skip WeCom notification"
    fi
  fi

  if [ -n "${AI_REVIEW_DINGTALK_WEBHOOK:-}" ]; then
    if command -v python >/dev/null 2>&1; then
      if python - "$message_file" "$repo_root" "$AI_REVIEW_NOTIFY_PREVIEW_LINES" > "$AI_REVIEW_REPORT_DIR/dingtalk-payload.json" <<'PY'
import json
import pathlib
import sys

message_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
try:
    max_lines = max(1, int(sys.argv[3]))
except ValueError:
    max_lines = 80
text = message_path.read_text(encoding="utf-8", errors="replace")
preview = "\n".join(text.splitlines()[:max_lines])
payload = {
    "msgtype": "markdown",
    "markdown": {
        "title": "AI Commit Review",
        "text": f"## AI Commit Review\n\n仓库: {repo_root.name}\n\n{preview}",
    },
}
print(json.dumps(payload, ensure_ascii=False))
PY
      then
        curl -sS --max-time 15 \
          -H "Content-Type: application/json" \
          -X POST "$AI_REVIEW_DINGTALK_WEBHOOK" \
          --data-binary "@$AI_REVIEW_REPORT_DIR/dingtalk-payload.json" >/dev/null \
          || warn "[ai-review] failed to send DingTalk notification"
      else
        warn "[ai-review] failed to build DingTalk notification payload"
      fi
    else
      warn "[ai-review] python is not available, skip DingTalk notification"
    fi
  fi

  if [ -n "${AI_REVIEW_EMAIL_TO:-}" ]; then
    if command -v python >/dev/null 2>&1; then
      export AI_REVIEW_SMTP_HOST
      export AI_REVIEW_SMTP_PORT
      export AI_REVIEW_SMTP_USERNAME
      export AI_REVIEW_SMTP_PASSWORD
      export AI_REVIEW_EMAIL_FROM
      export AI_REVIEW_EMAIL_TO
      export AI_REVIEW_SMTP_SSL
      export AI_REVIEW_SMTP_STARTTLS
      python - "$message_file" "$repo_root" <<'PY' || warn "[ai-review] failed to send email notification"
import html
import os
import pathlib
import smtplib
import sys
from email.message import EmailMessage

message_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])

host = os.environ.get("AI_REVIEW_SMTP_HOST")
port = int(os.environ.get("AI_REVIEW_SMTP_PORT", "587"))
username = os.environ.get("AI_REVIEW_SMTP_USERNAME")
password = os.environ.get("AI_REVIEW_SMTP_PASSWORD")
sender = os.environ.get("AI_REVIEW_EMAIL_FROM") or username
recipient = os.environ.get("AI_REVIEW_EMAIL_TO")
use_ssl = os.environ.get("AI_REVIEW_SMTP_SSL", "false").lower() == "true"
starttls = os.environ.get("AI_REVIEW_SMTP_STARTTLS", "true").lower() == "true"

if not host or not sender or not recipient:
    raise SystemExit("missing email config")

report_text = message_path.read_text(encoding="utf-8", errors="replace")
first_line = next((line.strip() for line in report_text.splitlines() if line.strip()), "")
status = "FAIL" if "FAIL" in first_line.upper() else "PASS"
status_color = "#dc2626" if status == "FAIL" else "#16a34a"
status_bg = "#fef2f2" if status == "FAIL" else "#f0fdf4"

def section_body(title):
    lines = report_text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == title:
            start = index + 1
            break
    if start is None:
        return "- 无"
    collected = []
    section_titles = {"阻断问题:", "非阻断建议:", "验证建议:"}
    for line in lines[start:]:
        if line.strip() in section_titles:
            break
        collected.append(line)
    text = "\n".join(collected).strip()
    return text or "- 无"

def render_section(title, body, color, background):
    escaped = html.escape(body)
    return f"""
    <section style="margin:16px 0;padding:14px 16px;border-left:4px solid {color};background:{background};border-radius:6px;">
      <h2 style="margin:0 0 10px;color:{color};font-size:16px;">{html.escape(title)}</h2>
      <pre style="margin:0;white-space:pre-wrap;font-family:Consolas,'Courier New',monospace;font-size:13px;line-height:1.6;color:#111827;">{escaped}</pre>
    </section>
    """

html_body = f"""<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,'Microsoft YaHei',sans-serif;color:#111827;">
    <main style="max-width:860px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:8px;padding:24px;">
      <h1 style="margin:0 0 12px;font-size:20px;">AI Commit Review - {html.escape(repo_root.name)}</h1>
      <div style="display:inline-block;margin:4px 0 18px;padding:6px 12px;border-radius:999px;background:{status_bg};color:{status_color};font-weight:700;">{status}</div>
      {render_section("阻断问题", section_body("阻断问题:"), "#dc2626", "#fef2f2")}
      {render_section("非阻断建议", section_body("非阻断建议:"), "#d97706", "#fffbeb")}
      {render_section("验证建议", section_body("验证建议:"), "#2563eb", "#eff6ff")}
      <p style="margin-top:20px;color:#6b7280;font-size:12px;">Plain text report is attached as the fallback body.</p>
    </main>
  </body>
</html>"""

msg = EmailMessage()
msg["Subject"] = f"AI Commit Review [{status}] - {repo_root.name}"
msg["From"] = sender
msg["To"] = recipient
msg.set_content(
    report_text,
    charset="utf-8",
    cte="base64",
)
msg.add_alternative(
    html_body,
    subtype="html",
    charset="utf-8",
    cte="base64",
)

if use_ssl:
    server = smtplib.SMTP_SSL(host, port, timeout=20)
else:
    server = smtplib.SMTP(host, port, timeout=20)
try:
    if starttls and not use_ssl:
        server.starttls()
    if username and password:
        server.login(username, password)
    server.send_message(msg)
finally:
    server.quit()
PY
    else
      warn "[ai-review] python is not available, skip email notification"
    fi
  fi
}

if [ "$AI_REVIEW_COMPILE" = "true" ]; then
  build_cmd="$(detect_build_command)"
  run_command "compile check" "$build_cmd"
fi

if [ "$AI_REVIEW_RUN_TESTS" = "true" ]; then
  test_cmd="$(detect_test_command)"
  run_command "tests" "$test_cmd"
fi

if [ -z "${AI_REVIEW_DIFF_FILE:-}" ]; then
  git diff --cached --binary --diff-filter=ACMRTUXB > "$diff_file"
fi
diff_bytes="$(wc -c < "$diff_file" | tr -d ' ')"

if [ "$diff_bytes" -eq 0 ]; then
  log "[ai-review] skipped: staged changes have no reviewable diff"
  exit 0
fi

if [ "$diff_bytes" -gt "$AI_REVIEW_MAX_DIFF_BYTES" ]; then
  warn "[ai-review] skipped AI call: staged diff is ${diff_bytes} bytes, limit is ${AI_REVIEW_MAX_DIFF_BYTES}."
  warn "[ai-review] raise AI_REVIEW_MAX_DIFF_BYTES or review smaller commits."
  exit 0
fi

if [ -z "${AI_REVIEW_API_KEY:-}" ]; then
  warn "[ai-review] AI_REVIEW_API_KEY is not set. Configure .ai-review.env or ~/.ai-review.env."
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ]; then
    exit 1
  fi
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  warn "[ai-review] curl is not available."
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ]; then
    exit 1
  fi
  exit 0
fi

if ! command -v python >/dev/null 2>&1; then
  warn "[ai-review] python is not available."
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ]; then
    exit 1
  fi
  exit 0
fi

python - "$diff_file" "$request_file" "$AI_REVIEW_MODEL" <<'PY'
import json
import pathlib
import sys

diff_path = pathlib.Path(sys.argv[1])
request_path = pathlib.Path(sys.argv[2])
model = sys.argv[3]
diff_text = diff_path.read_text(encoding="utf-8", errors="replace")

system_prompt = """你是一名资深代码审查工程师。只审查用户提供的 staged git diff，不要评论与本次 diff 无关的旧代码。

审查优先级从高到低：
1. 明显编译错误、语法错误、类型错误、缺失导入、错误方法签名。
2. 运行时异常风险，包括空指针、数组越界、非法状态、资源泄露。
3. 事务、数据一致性、幂等性、并发、异步、消息确认、重试等逻辑风险。
4. 安全问题，包括敏感信息泄露、注入、鉴权绕过、不安全反序列化。
5. API/数据库/配置/外部服务契约兼容性问题。
6. 可维护性、性能、可读性、边界校验等优化建议。

判定规则：
- 只有会导致编译失败、运行失败、数据错误、安全风险、接口契约破坏或明显业务逻辑错误的问题，才能放入“阻断问题”。
- 风格、命名、轻微重复、普通可读性建议只能放入“非阻断建议”。
- 不要为了凑数输出泛泛建议；没有问题就写“- 无”。
- 每条问题尽量包含文件/代码片段线索、风险说明和建议修复方向。
- 如果仅凭 diff 无法确定上下文，请明确说明“基于 diff 推断”，不要假装确定。

必须使用中文，并严格使用以下顶层格式，不要增加额外顶层标题：
结论: PASS 或 FAIL
阻断问题:
- ...
非阻断建议:
- ...
验证建议:
- ...
如果某一节没有内容，写“- 无”。
"""

user_prompt = f"""请 review 以下暂存区代码变更。

请判断是否存在明显编译错误、运行时异常、逻辑问题、数据一致性风险、安全风险和接口兼容性问题，并给出必要的优化建议。
请只基于 diff 输出，不要重复解释审查规则。

```diff
{diff_text}
```"""

payload = {
    "model": model,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
    ],
    "temperature": 0.1,
}

request_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
PY

chat_url="$(chat_completions_url)"
log "[ai-review] requesting AI review with model: $AI_REVIEW_MODEL"

http_code="000"
if curl -sS \
  --max-time "$AI_REVIEW_TIMEOUT_SECONDS" \
  -o "$response_file" \
  -w '%{http_code}' \
  -H "Authorization: Bearer $AI_REVIEW_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST "$chat_url" \
  --data-binary "@$request_file" > "$AI_REVIEW_REPORT_DIR/http_code"; then
  http_code="$(cat "$AI_REVIEW_REPORT_DIR/http_code")"
fi

if [ "$http_code" != "200" ]; then
  warn "[ai-review] AI request failed with HTTP $http_code. Response: $response_file"
  if [ -f "$response_file" ]; then
    cat "$response_file" >&2 || true
  fi
  {
    printf '%s\n' "AI Commit Review 调用失败"
    printf '%s\n' "仓库: $(basename "$repo_root")"
    printf '%s\n' "HTTP: $http_code"
    printf '%s\n' "响应文件: $response_file"
    if [ -f "$response_file" ]; then
      printf '%s\n' ""
      head -n "$AI_REVIEW_NOTIFY_PREVIEW_LINES" "$response_file" || true
    fi
  } > "$notification_file"
  send_notifications "error" "$notification_file"
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ] || [ "$AI_REVIEW_FAIL_ON_AI_ERROR" = "true" ]; then
    exit 1
  fi
  exit 0
fi

if ! python - "$response_file" "$report_file" <<'PY'
import json
import pathlib
import sys

response_path = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
raw_response = response_path.read_text(encoding="utf-8", errors="replace")
try:
    data = json.loads(raw_response)
except json.JSONDecodeError:
    sys.exit(2)

content = ""
try:
    content = data["choices"][0]["message"]["content"]
except (KeyError, IndexError, TypeError):
    content = json.dumps(data, ensure_ascii=False, indent=2)

report_path.write_text(content.strip() + "\n", encoding="utf-8")
print(content.strip())
PY
then
  warn "[ai-review] AI response is not valid OpenAI chat-completions JSON. Response: $response_file"
  if [ -f "$response_file" ]; then
    cat "$response_file" >&2 || true
  fi
  {
    printf '%s\n' "AI Commit Review 响应格式异常"
    printf '%s\n' "仓库: $(basename "$repo_root")"
    printf '%s\n' "响应文件: $response_file"
    if [ -f "$response_file" ]; then
      printf '%s\n' ""
      head -n "$AI_REVIEW_NOTIFY_PREVIEW_LINES" "$response_file" || true
    fi
  } > "$notification_file"
  send_notifications "error" "$notification_file"
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ] || [ "$AI_REVIEW_FAIL_ON_AI_ERROR" = "true" ]; then
    exit 1
  fi
  exit 0
fi

send_notifications "review" "$report_file"

if [ "$AI_REVIEW_FAIL_ON_FINDINGS" = "true" ] && grep -qi '^结论:[[:space:]]*FAIL' "$report_file"; then
  warn "[ai-review] AI review returned FAIL. Report: $report_file"
  exit 1
fi

log "[ai-review] report saved: $report_file"
