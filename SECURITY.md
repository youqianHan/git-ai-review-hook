# Security

This tool sends staged git diffs to the configured OpenAI-compatible API endpoint.

Before enabling it, confirm that your organization permits source code review through the selected AI provider.

## Secrets

Do not commit:

- `.ai-review.env`
- API keys
- SMTP authorization codes
- WeCom or DingTalk webhook URLs

The installer adds `.ai-review.env` and `/githooks/` to the target repository `.gitignore` by default.

## Data Sent To AI

The hook sends only `git diff --cached` content. It does not send the full repository unless the staged diff contains it.

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
```
