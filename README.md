# AI Review Git Hook

一个可复用的 AI 代码审查 Git Hook。它会在 `git commit` 时读取本次暂存区 diff，异步调用 OpenAI 兼容接口做代码 review，并把结果写入本地日志，也可以通过邮件、企业微信或钉钉通知。

默认是异步执行：commit 会很快完成，AI review 和通知在后台继续运行。

## 功能特性

- 只审查 `git diff --cached`，也就是本次提交的暂存区代码。
- 支持 OpenAI-compatible `/v1/chat/completions` 接口。
- 默认不执行 Maven、Gradle、npm 等本地构建命令。
- 支持桌面通知、飞书、邮件、企业微信、钉钉通知。
- 邮件支持纯文本 + HTML 彩色格式。
- 默认不阻塞 commit；如果需要，也可以配置 AI 返回 `FAIL` 时阻止提交。
- 日志和报告写入 `.git/ai-review/`。
- 提供诊断脚本，检查 Git Bash、Python、AI API、SMTP 等环境。

## 一键安装

在目标项目根目录执行。

Windows PowerShell：

```powershell
irm https://raw.githubusercontent.com/youqianHan/git-ai-review-hook/main/bootstrap.ps1 | iex
```

macOS / Linux：

```bash
curl -fsSL https://raw.githubusercontent.com/youqianHan/git-ai-review-hook/main/bootstrap.sh | sh
```

安装指定版本：

```bash
AI_REVIEW_HOOK_VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/youqianHan/git-ai-review-hook/main/bootstrap.sh | sh
```

本地 zip 测试：

```bash
AI_REVIEW_HOOK_ZIP=/path/to/git-ai-review-hook.zip sh bootstrap.sh
```

安装脚本会：

- 检查 Git、Git Bash、Python、curl。
- 设置 `git config core.hooksPath githooks`。
- 自动把 `.ai-review.env` 和 `/githooks/` 加入 `.gitignore`。
- 交互式生成或更新 `.ai-review.env`。

## 手动安装

也可以手动复制 `githooks/` 到目标项目根目录，然后执行：

```powershell
.\githooks\install.ps1
```

或：

```bash
sh githooks/install.sh
```

## 配置

`.ai-review.env` 是本地配置文件，不要提交到仓库。

最小配置：

```bash
AI_REVIEW_ENABLED=true
AI_REVIEW_API_KEY=replace_with_your_api_key
AI_REVIEW_MODEL=gpt-5.5
AI_REVIEW_BASE_URL=https://example.com/v1
AI_REVIEW_ASYNC=true
```

`AI_REVIEW_BASE_URL` 支持两种格式：

```bash
AI_REVIEW_BASE_URL=https://example.com/v1
AI_REVIEW_BASE_URL=https://example.com/v1/chat/completions
```

## 推荐通知方式

最简单的是桌面通知，不需要邮箱授权码或 webhook：

```bash
AI_REVIEW_DESKTOP_NOTIFY=true
AI_REVIEW_DESKTOP_NOTIFY_SECONDS=8
```

支持：

- macOS：`osascript` 系统通知
- Windows：PowerShell 自定义右下角通知，支持自动关闭，鼠标悬停暂停关闭，点击打开 review 报告
- Linux：`notify-send`

团队通知推荐飞书、企业微信或钉钉机器人，配置一个 webhook 即可。

## 飞书通知

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_FEISHU_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

## 邮件通知示例

QQ 邮箱：

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_EMAIL_TO=dev@qq.com
AI_REVIEW_EMAIL_FROM=dev@qq.com
AI_REVIEW_SMTP_HOST=smtp.qq.com
AI_REVIEW_SMTP_PORT=465
AI_REVIEW_SMTP_USERNAME=dev@qq.com
AI_REVIEW_SMTP_PASSWORD=replace_with_smtp_auth_code
AI_REVIEW_SMTP_STARTTLS=false
AI_REVIEW_SMTP_SSL=true
```

163 邮箱：

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_EMAIL_TO=dev@163.com
AI_REVIEW_EMAIL_FROM=dev@163.com
AI_REVIEW_SMTP_HOST=smtp.163.com
AI_REVIEW_SMTP_PORT=465
AI_REVIEW_SMTP_USERNAME=dev@163.com
AI_REVIEW_SMTP_PASSWORD=replace_with_smtp_auth_code
AI_REVIEW_SMTP_STARTTLS=false
AI_REVIEW_SMTP_SSL=true
```

说明：

- `AI_REVIEW_SMTP_PASSWORD` 通常是邮箱 SMTP 授权码，不是网页登录密码。
- 465 端口通常使用 `AI_REVIEW_SMTP_SSL=true` 和 `AI_REVIEW_SMTP_STARTTLS=false`。

## 企业微信 / 钉钉

企业微信机器人：

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx
```

钉钉机器人：

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx
```

通知触发模式：

```bash
AI_REVIEW_NOTIFY_ON=always  # 每次 review 成功或异常都通知
AI_REVIEW_NOTIFY_ON=fail    # 只有 AI 返回 FAIL 时通知
AI_REVIEW_NOTIFY_ON=error   # 只有 API 或响应异常时通知
AI_REVIEW_NOTIFY_ON=never   # 不通知
```

## 输出文件

```text
.git/ai-review/last-review.md
.git/ai-review/request.json
.git/ai-review/response.json
.git/ai-review/jobs/<job-id>/background.log
```

如果没收到通知，优先看最新 job 的 `background.log`。

## 诊断

运行完整诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\scripts\test-ai-review-env.ps1
```

不发送测试邮件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\scripts\test-ai-review-env.ps1 -SendMail false
```

只排查 Git Bash / Python / Hook 路径：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\scripts\test-ai-review-env.ps1 -SendMail false -TestAi false
```

## 卸载

Windows：

```powershell
.\githooks\uninstall.ps1
```

macOS / Linux：

```bash
sh githooks/uninstall.sh
```

卸载脚本会移除：

```bash
git config core.hooksPath
```

但会保留本地 `githooks/` 和 `.ai-review.env`，如不再需要可手动删除。

## 安全说明

该工具会把本次暂存区 diff 发送给你配置的 AI 服务。使用前请确认你的团队允许把代码变更发送到该服务。

不要提交：

- `.ai-review.env`
- API Key
- SMTP 授权码
- 企业微信或钉钉 webhook

## English Summary

AI Review Git Hook reviews staged code changes during `git commit` and sends results through desktop notification, Feishu, email, WeCom, or DingTalk. It runs asynchronously by default, so commits return quickly while review and notifications continue in the background.

One-line install:

```powershell
irm https://raw.githubusercontent.com/youqianHan/git-ai-review-hook/main/bootstrap.ps1 | iex
```

```bash
curl -fsSL https://raw.githubusercontent.com/youqianHan/git-ai-review-hook/main/bootstrap.sh | sh
```

## Development

Run local checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-install.ps1
```

Build a release zip:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-release.ps1
```

Shell syntax:

```bash
sh -n bootstrap.sh
sh -n githooks/install.sh
sh -n githooks/pre-commit
sh -n githooks/scripts/ai-review.sh
```
