#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

python_cmd() {
  for cmd in python python3 "py -3"; do
    # Intentionally expand fixed candidates so "py -3" works as command + arg.
    if $cmd -c 'import sys, json, pathlib; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      printf '%s\n' "$cmd"
      return 0
    fi
  done
  printf '%s\n' ""
}

run_python() {
  cmd="$1"
  shift
  # Intentionally expand a trusted command selected by python_cmd so "py -3" works.
  PYTHONIOENCODING=utf-8 PYTHONUTF8=1 $cmd "$@"
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
: "${AI_REVIEW_CONTEXT_ENABLED:=true}"
: "${AI_REVIEW_CONTEXT_MAX_BYTES:=80000}"
: "${AI_REVIEW_CONTEXT_MAX_FILE_BYTES:=20000}"
: "${AI_REVIEW_TIMEOUT_SECONDS:=90}"
: "${AI_REVIEW_REPORT_DIR:=.git/ai-review}"
: "${AI_REVIEW_NOTIFY_ON:=always}"
: "${AI_REVIEW_NOTIFY_PREVIEW_LINES:=80}"
: "${AI_REVIEW_DESKTOP_NOTIFY_SECONDS:=8}"
: "${AI_REVIEW_DESKTOP_OPEN_MODE:=native}"
: "${AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT:=false}"
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
context_file="$AI_REVIEW_REPORT_DIR/context.txt"
request_file="$AI_REVIEW_REPORT_DIR/request.json"
response_file="$AI_REVIEW_REPORT_DIR/response.json"
notification_file="$AI_REVIEW_REPORT_DIR/notification.txt"

utf8_base64() {
  value="$1"
  py_cmd="$(python_cmd)"
  if [ -z "$py_cmd" ]; then
    printf '%s\n' ""
    return 0
  fi
  printf '%s' "$value" | PYTHONIOENCODING=utf-8 PYTHONUTF8=1 $py_cmd -c 'import base64, sys; print(base64.b64encode(sys.stdin.buffer.read()).decode("ascii"))'
}

chat_completions_url() {
  url="${AI_REVIEW_BASE_URL%/}"
  case "$url" in
    */chat/completions)
      printf '%s\n' "$url"
      ;;
    */v1 | */compatible-mode/v1 | */api/paas/v4 | */api/v3 | */v1beta/openai)
      printf '%s/chat/completions\n' "$url"
      ;;
    https://api.deepseek.com | https://api.moonshot.ai)
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

  if [ "${AI_REVIEW_DESKTOP_NOTIFY:-false}" = "true" ]; then
    py_cmd="$(python_cmd)"
    if [ -n "$py_cmd" ]; then
      summary="$(run_python "$py_cmd" - "$message_file" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
lines = [line.strip() for line in text.splitlines() if line.strip()]
title = lines[0] if lines else "AI Commit Review"
detail = ""
for line in lines[1:]:
    if line.startswith("- ") and "无" not in line:
        detail = line[2:]
        break
print((title + (" - " + detail if detail else ""))[:180])
PY
)"
    else
      summary="AI Commit Review finished"
    fi

    if command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"$(printf '%s' "$summary" | sed 's/"/\\"/g')\" with title \"AI Commit Review\"" >/dev/null 2>&1 \
        || warn "[ai-review] failed to send macOS desktop notification"
      if [ "${AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT:-false}" = "true" ]; then
        if [ -n "$py_cmd" ]; then
          run_python "$py_cmd" - "$message_file" "$status" <<'PY' | osascript >/dev/null 2>&1 \
            || warn "[ai-review] failed to show macOS review report"
import pathlib
import sys

message_path = pathlib.Path(sys.argv[1])
runtime_status = sys.argv[2].strip().upper()
text = message_path.read_text(encoding="utf-8", errors="replace").strip()
first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
if runtime_status == "ERROR":
    status = "ERROR"
elif "FAIL" in first_line.upper():
    status = "FAIL"
else:
    status = "PASS"

max_chars = 6000
if len(text) > max_chars:
    text = text[:max_chars] + "\n\n... 内容过长，完整报告请查看 .git/ai-review/last-review.md"

def esc(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")

print(f'display dialog "{esc(text or "无报告内容")}" with title "AI Commit Review [{status}]" buttons {{"OK"}} default button "OK"')
PY
        else
          warn "[ai-review] python is not available, skip macOS review report dialog"
        fi
      fi
    elif command -v powershell.exe >/dev/null 2>&1; then
      notify_script="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/show-windows-notification.ps1"
      notify_report_path="$report_file"
      case "$notify_report_path" in
        /* | [A-Za-z]:*)
          ;;
        *)
          notify_report_path="$repo_root/$notify_report_path"
          ;;
      esac
      notify_status="$(run_python "$py_cmd" - "$message_file" "$status" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
runtime_status = sys.argv[2].strip().upper()
first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
if runtime_status == "ERROR":
    print("ERROR")
elif "FAIL" in first_line.upper():
    print("FAIL")
else:
    print("PASS")
PY
)"
      if [ -f "$notify_script" ]; then
        notify_title_b64="$(utf8_base64 "AI Commit Review")"
        notify_message_b64="$(utf8_base64 "$summary")"
        notify_report_path_b64="$(utf8_base64 "$notify_report_path")"
        powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden \
          -File "$notify_script" \
          -TitleBase64 "$notify_title_b64" \
          -MessageBase64 "$notify_message_b64" \
          -Status "$notify_status" \
          -ReportPathBase64 "$notify_report_path_b64" \
          -OpenMode "$AI_REVIEW_DESKTOP_OPEN_MODE" \
          -Seconds "$AI_REVIEW_DESKTOP_NOTIFY_SECONDS" >/dev/null 2>&1 &
      else
        warn "[ai-review] Windows notification script not found: $notify_script"
      fi \
        || warn "[ai-review] failed to send Windows desktop notification"
    elif command -v notify-send >/dev/null 2>&1; then
      notify-send "AI Commit Review" "$summary" >/dev/null 2>&1 \
        || warn "[ai-review] failed to send Linux desktop notification"
    fi
  fi

  if [ -n "${AI_REVIEW_FEISHU_WEBHOOK:-}" ]; then
    py_cmd="$(python_cmd)"
    if [ -n "$py_cmd" ]; then
      if run_python "$py_cmd" - "$message_file" "$repo_root" "$AI_REVIEW_NOTIFY_PREVIEW_LINES" > "$AI_REVIEW_REPORT_DIR/feishu-payload.json" <<'PY'
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
first_line = next((line for line in text.splitlines() if line.strip()), "")
payload = {
    "msg_type": "interactive",
    "card": {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "AI Commit Review"},
            "template": "red" if "FAIL" in first_line.upper() else "green",
        },
        "elements": [
            {"tag": "div", "text": {"tag": "lark_md", "content": f"**仓库**: {repo_root.name}"}},
            {"tag": "hr"},
            {"tag": "div", "text": {"tag": "lark_md", "content": preview}},
        ],
    },
}
print(json.dumps(payload, ensure_ascii=False))
PY
      then
        curl -sS --max-time 15 \
          -H "Content-Type: application/json" \
          -X POST "$AI_REVIEW_FEISHU_WEBHOOK" \
          --data-binary "@$AI_REVIEW_REPORT_DIR/feishu-payload.json" >/dev/null \
          || warn "[ai-review] failed to send Feishu notification"
      else
        warn "[ai-review] failed to build Feishu notification payload"
      fi
    else
      warn "[ai-review] python is not available, skip Feishu notification"
    fi
  fi

  if [ -n "${AI_REVIEW_WECHAT_WEBHOOK:-}" ]; then
    py_cmd="$(python_cmd)"
    if [ -n "$py_cmd" ]; then
      if run_python "$py_cmd" - "$message_file" "$repo_root" "$AI_REVIEW_NOTIFY_PREVIEW_LINES" > "$AI_REVIEW_REPORT_DIR/wechat-payload.json" <<'PY'
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
    py_cmd="$(python_cmd)"
    if [ -n "$py_cmd" ]; then
      if run_python "$py_cmd" - "$message_file" "$repo_root" "$AI_REVIEW_NOTIFY_PREVIEW_LINES" > "$AI_REVIEW_REPORT_DIR/dingtalk-payload.json" <<'PY'
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
    py_cmd="$(python_cmd)"
    if [ -n "$py_cmd" ]; then
      export AI_REVIEW_SMTP_HOST
      export AI_REVIEW_SMTP_PORT
      export AI_REVIEW_SMTP_USERNAME
      export AI_REVIEW_SMTP_PASSWORD
      export AI_REVIEW_EMAIL_FROM
      export AI_REVIEW_EMAIL_TO
      export AI_REVIEW_SMTP_SSL
      export AI_REVIEW_SMTP_STARTTLS
      run_python "$py_cmd" - "$message_file" "$repo_root" <<'PY' || warn "[ai-review] failed to send email notification"
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

PY_CMD="$(python_cmd)"
if [ -z "$PY_CMD" ]; then
  warn "[ai-review] python/python3 is not available."
  if [ "$AI_REVIEW_REQUIRE_API" = "true" ]; then
    exit 1
  fi
  exit 0
fi

if [ "$AI_REVIEW_CONTEXT_ENABLED" = "true" ]; then
  run_python "$PY_CMD" - "$diff_file" "$context_file" "$repo_root" "$AI_REVIEW_CONTEXT_MAX_BYTES" "$AI_REVIEW_CONTEXT_MAX_FILE_BYTES" <<'PY'
import pathlib
import re
import subprocess
import sys

diff_path = pathlib.Path(sys.argv[1])
context_path = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3]).resolve()
max_bytes = int(sys.argv[4])
max_file_bytes = int(sys.argv[5])

diff_text = diff_path.read_text(encoding="utf-8", errors="replace")

def norm_path(value):
    value = value.strip().replace("\\", "/")
    if value.startswith("a/") or value.startswith("b/"):
        value = value[2:]
    if not value or value == "/dev/null":
        return ""
    parts = []
    for part in value.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            return ""
        parts.append(part)
    return "/".join(parts)

changed = []
for line in diff_text.splitlines():
    if line.startswith("+++ "):
        path = norm_path(line[4:].split("\t", 1)[0])
        if path:
            changed.append(path)
    elif line.startswith("--- "):
        path = norm_path(line[4:].split("\t", 1)[0])
        if path:
            changed.append(path)

def add_unique(target, path):
    path = norm_path(path)
    if path and path not in target:
        target.append(path)

files = []
for path in changed:
    add_unique(files, path)

for root_file in ("AGENTS.md", "README.md", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "package.json"):
    if (repo_root / root_file).is_file():
        add_unique(files, root_file)

changed_set = list(files)
for path in changed_set:
    p = repo_root / path
    parent = p.parent
    stem = p.stem
    suffix = p.suffix.lower()
    if not p.exists():
        continue
    if suffix == ".java":
        for candidate in (
            f"{stem}Mapper.xml",
            f"{stem}Dao.xml",
            f"{stem}Repository.xml",
            f"{stem}Service.java",
            f"{stem}ServiceImpl.java",
            f"I{stem}Service.java",
            f"{stem}Mapper.java",
            f"{stem}Dao.java",
            f"{stem}Repository.java",
            f"{stem}DTO.java",
            f"{stem}Dto.java",
            f"{stem}VO.java",
            f"{stem}Vo.java",
        ):
            for base in (parent, repo_root / "src/main/resources/mapper"):
                candidate_path = base / candidate
                if candidate_path.is_file():
                    add_unique(files, str(candidate_path.relative_to(repo_root)).replace("\\", "/"))
        for neighbor in sorted(parent.glob("*.java"))[:20]:
            add_unique(files, str(neighbor.relative_to(repo_root)).replace("\\", "/"))
    elif suffix == ".xml" and "mapper" in path.lower():
        for java_file in repo_root.glob(f"src/main/java/**/*{stem}.java"):
            add_unique(files, str(java_file.relative_to(repo_root)).replace("\\", "/"))

for match in re.finditer(r"^\s*import\s+([a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)+);", diff_text, re.M):
    imported = match.group(1)
    if imported.startswith(("java.", "javax.", "jakarta.", "org.springframework.", "lombok.")):
        continue
    relative = pathlib.Path("src/main/java") / pathlib.Path(*imported.split(".")).with_suffix(".java")
    if (repo_root / relative).is_file():
        add_unique(files, str(relative).replace("\\", "/"))

skip_parts = {
    ".git", ".idea", ".vscode", "target", "build", "dist", "node_modules",
    ".gradle", ".mvn", "out", "coverage", ".git-ai-review-hook"
}
skip_suffixes = {
    ".class", ".jar", ".war", ".zip", ".gz", ".7z", ".rar", ".png", ".jpg", ".jpeg",
    ".gif", ".webp", ".ico", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".mp3", ".mp4", ".wav", ".avi", ".mov", ".exe", ".dll", ".so", ".dylib"
}
secret_patterns = re.compile(r"(^|/)(\.env|.*secret.*|.*password.*|.*credential.*|.*token.*|.*private.*|id_rsa|id_dsa)(\.|$|/)", re.I)

def is_safe_text_file(path):
    if any(part in skip_parts for part in pathlib.PurePosixPath(path).parts):
        return False
    if secret_patterns.search(path):
        return False
    full = (repo_root / path).resolve()
    try:
        full.relative_to(repo_root)
    except ValueError:
        return False
    if not full.is_file():
        return False
    if full.suffix.lower() in skip_suffixes:
        return False
    try:
        sample = full.read_bytes()[:4096]
    except OSError:
        return False
    return b"\x00" not in sample

sections = []
used = 0
included = []
for path in files:
    if not is_safe_text_file(path):
        continue
    full = repo_root / path
    try:
        raw = full.read_bytes()
    except OSError:
        continue
    truncated = len(raw) > max_file_bytes
    raw = raw[:max_file_bytes]
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", errors="replace")
    body = f"\n--- FILE: {path} ---\n{text}"
    if truncated:
        body += "\n... 文件内容已按 AI_REVIEW_CONTEXT_MAX_FILE_BYTES 截断\n"
    body_bytes = len(body.encode("utf-8", errors="replace"))
    if used + body_bytes > max_bytes:
        break
    sections.append(body)
    included.append(path)
    used += body_bytes

if sections:
    header = [
        "项目上下文（仅用于理解本次 staged diff 的影响范围，不要审查无关旧代码）",
        f"包含文件数: {len(included)}",
        f"上下文字节数: {used}/{max_bytes}",
        "",
    ]
    context_path.write_text("\n".join(header) + "\n".join(sections).strip() + "\n", encoding="utf-8")
else:
    context_path.write_text("项目上下文: 未收集到可用上下文。\n", encoding="utf-8")
PY
else
  printf '%s\n' "项目上下文: 已禁用 AI_REVIEW_CONTEXT_ENABLED=false。" > "$context_file"
fi

run_python "$PY_CMD" - "$diff_file" "$context_file" "$request_file" "$AI_REVIEW_MODEL" <<'PY'
import json
import pathlib
import sys

diff_path = pathlib.Path(sys.argv[1])
context_path = pathlib.Path(sys.argv[2])
request_path = pathlib.Path(sys.argv[3])
model = sys.argv[4]
diff_text = diff_path.read_text(encoding="utf-8", errors="replace")
context_text = context_path.read_text(encoding="utf-8", errors="replace")

system_prompt = """你是一名资深代码审查工程师。只审查用户提供的 staged git diff。项目上下文只用于理解本次 diff 的影响范围，不要评论与本次 diff 无关的旧代码。

审查优先级从高到低：
1. 明显编译错误、语法错误、类型错误、缺失导入、错误方法签名。
2. 运行时异常风险，包括空指针、数组越界、非法状态、资源泄露。
3. 事务、数据一致性、幂等性、并发、异步、消息确认、重试等逻辑风险。
4. 安全问题，包括敏感信息泄露、注入、鉴权绕过、不安全反序列化。
5. API/数据库/配置/外部服务契约兼容性问题。
6. 可维护性、性能、可读性、边界校验、可重构性等优化建议。

判定规则：
- 只有会导致编译失败、运行失败、数据错误、安全风险、接口契约破坏或明显业务逻辑错误的问题，才能放入“阻断问题”。
- 风格、命名、轻微重复、普通可读性、代码简化、抽离公共方法、减少重复逻辑等建议只能放入“非阻断建议”。
- 可以判断当前写法是否过于啰嗦；在不改变业务逻辑的前提下，如果能更简洁、更清晰或更容易维护，请在“非阻断建议”中说明可重构方向。
- 可以判断是否有适合参考设计模式的场景，例如策略模式、模板方法、工厂模式、责任链、适配器、观察者等；设计模式只作为参考建议，必须放入“非阻断建议”，不要因为未使用设计模式而判定失败。
- 不要为了使用设计模式而建议过度设计；只有当 diff 中确实出现明显条件分支膨胀、重复流程、对象创建分散、扩展点不清晰或职责混杂时才提出。
- 不要为了凑数输出泛泛建议；没有问题就写“- 无”。
- 每条问题尽量包含文件/代码片段线索、风险说明和建议修复方向。
- 如果仅凭 diff 无法确定上下文，请明确说明“基于 diff 推断”，不要假装确定。
- 如果项目上下文显示本次 diff 会影响调用方、接口实现、Mapper/XML、配置、DTO 或依赖契约，请结合上下文指出风险。
- 不要因为上下文中的历史代码风格、旧问题或未修改代码本身判定 FAIL；只有它直接影响本次 diff 时才可以提及。

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
优化建议中请额外关注：代码是否可以在不改变业务逻辑的前提下重构得更简洁，是否存在可抽离的公共方法、重复流程、过长方法、职责混杂，以及是否有适合参考设计模式改善扩展性的场景。
这些重构和设计模式建议都属于非阻断建议，不应影响 PASS/FAIL 结论。
请以 staged diff 为主，结合项目上下文判断影响范围，不要重复解释审查规则。

<project_context>
{context_text}
</project_context>

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

if ! run_python "$PY_CMD" - "$response_file" "$report_file" <<'PY'
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
