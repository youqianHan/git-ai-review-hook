# Security

This tool sends staged git diffs, and optionally related project context, to the configured OpenAI-compatible API endpoint.

Before enabling it, confirm that your organization permits source code review through the selected AI provider.

## Secrets

Do not commit:

- `.ai-review.env`
- API keys
- SMTP authorization codes
- WeCom or DingTalk webhook URLs

The installer adds `.ai-review.env` and `/githooks/` to the target repository `.gitignore` by default.

## Data Sent To AI

The hook always sends `git diff --cached` content.

By default, `AI_REVIEW_CONTEXT_ENABLED=true` also sends a limited set of related project files to help the model understand the changed code. This may include files such as `AGENTS.md`, `README.md`, `pom.xml`, changed source files, nearby Java classes, Mapper XML files, DTO/DAO/Service classes, and imported project classes.

Context collection is bounded by:

```bash
AI_REVIEW_CONTEXT_MAX_BYTES=80000
AI_REVIEW_CONTEXT_MAX_FILE_BYTES=20000
```

The hook skips obvious secret files, `.env` files, build outputs, dependency directories, binary files, and common private-key/token filenames. This is a best-effort filter, not a security boundary.

To disable project context and send only the staged diff:

```bash
AI_REVIEW_CONTEXT_ENABLED=false
```

Avoid staging secrets. Consider running a secret scanner before commit in high-sensitivity repositories.

## Network

AI requests use `curl` and respect standard environment proxy variables such as:

```bash
HTTP_PROXY=http://proxy.example.com:8080
HTTPS_PROXY=http://proxy.example.com:8080
NO_PROXY=localhost,127.0.0.1
```

SMTP notifications use Python `smtplib`.

## Reporting Issues

When reporting bugs, remove secrets from logs before sharing:

```text
.git/ai-review/jobs/<job-id>/background.log
.git/ai-review/response.json
.git/ai-review/request.json
.git/ai-review/context.txt
```
