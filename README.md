# AI Review Git Hook

AI Review Git Hook reviews staged code changes during `git commit` and sends the result by email, WeCom, or DingTalk.

It is asynchronous by default: commit returns quickly, while AI review and notifications continue in the background.

## Features

- Reviews only `git diff --cached`.
- Uses an OpenAI-compatible `/v1/chat/completions` endpoint.
- Does not run Maven, Gradle, npm, or other local build commands by default.
- Sends optional notifications through email, WeCom, or DingTalk.
- Writes logs and reports under `.git/ai-review/`.
- Includes diagnostics for Python, Git Bash, API connectivity, and SMTP.

## Quick Start

One-line install from GitHub release:

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/<owner>/git-ai-review-hook/main/bootstrap.ps1 | iex
```

macOS/Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/git-ai-review-hook/main/bootstrap.sh | sh
```

Install a fixed version:

```bash
AI_REVIEW_HOOK_VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/<owner>/git-ai-review-hook/main/bootstrap.sh | sh
```

For local testing with a zip file:

```bash
AI_REVIEW_HOOK_ZIP=/path/to/git-ai-review-hook.zip sh bootstrap.sh
```

Copy `githooks/` into a target repository, then run:

```powershell
.\githooks\install.ps1
```

Or on Git Bash/Linux/macOS:

```bash
sh githooks/install.sh
```

The installer:

- Checks Git, Git Bash, Python, and curl.
- Sets `git config core.hooksPath githooks`.
- Adds `.ai-review.env` and `/githooks/` to `.gitignore`.
- Creates or updates `.ai-review.env`.

## Configuration

`.ai-review.env` is local and must not be committed.

Minimum:

```bash
AI_REVIEW_ENABLED=true
AI_REVIEW_API_KEY=replace_with_your_api_key
AI_REVIEW_MODEL=gpt-5.5
AI_REVIEW_BASE_URL=https://example.com/v1
AI_REVIEW_ASYNC=true
```

Email example:

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_EMAIL_TO=dev@example.com
AI_REVIEW_EMAIL_FROM=dev@example.com
AI_REVIEW_SMTP_HOST=smtp.qq.com
AI_REVIEW_SMTP_PORT=465
AI_REVIEW_SMTP_USERNAME=dev@example.com
AI_REVIEW_SMTP_PASSWORD=replace_with_smtp_auth_code
AI_REVIEW_SMTP_STARTTLS=false
AI_REVIEW_SMTP_SSL=true
```

WeCom:

```bash
AI_REVIEW_WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx
```

DingTalk:

```bash
AI_REVIEW_DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx
```

Notification modes:

```bash
AI_REVIEW_NOTIFY_ON=always  # every review or error
AI_REVIEW_NOTIFY_ON=fail    # only when AI returns FAIL
AI_REVIEW_NOTIFY_ON=error   # only API/response errors
AI_REVIEW_NOTIFY_ON=never   # disable notifications
```

## Output

```text
.git/ai-review/last-review.md
.git/ai-review/request.json
.git/ai-review/response.json
.git/ai-review/jobs/<job-id>/background.log
```

## Diagnostics

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\scripts\test-ai-review-env.ps1
```

Without sending mail:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\scripts\test-ai-review-env.ps1 -SendMail false
```

## Uninstall

Windows:

```powershell
.\githooks\uninstall.ps1
```

POSIX shell:

```bash
sh githooks/uninstall.sh
```

This removes `core.hooksPath=githooks` and keeps local files for manual cleanup.

## Development

Run local checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-install.ps1
```

Build a release zip:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-release.ps1
```

```bash
sh -n githooks/install.sh
sh -n githooks/pre-commit
sh -n githooks/scripts/ai-review.sh
```
