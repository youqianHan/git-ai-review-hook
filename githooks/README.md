# AI Review Git Hook 使用文档

这套 Git Hook 用于在 `git commit` 时把暂存区代码变更发送给 AI 做 review，检查明显编译错误、运行时风险、逻辑问题，并给出优化建议。

默认行为：

- 只 review `git diff --cached`，也就是本次 commit 暂存区内容。
- 不执行 `mvn`、`gradle`、`npm` 等本地构建命令。
- 默认后台异步执行 AI review，commit 不等待网络请求。
- AI 接口失败时只提示，不阻止 commit。
- AI review 结果会保存到 `.git/ai-review/last-review.md`。
- 可选发送桌面通知、飞书、企业微信、钉钉或邮件通知。

## 文件说明

```text
githooks/
  pre-commit                  # Git hook 入口
  scripts/ai-review.sh         # AI review 主逻辑
  install.ps1                  # Windows PowerShell 交互安装脚本
  install.sh                   # Git Bash/Linux/macOS 交互安装脚本
  ai-review.env.example        # 配置样例
  README.md                    # 使用文档
```

本项目已配置 `.gitignore`：

```gitignore
.ai-review.env
/githooks/
```

所以 `githooks/` 和 `.ai-review.env` 都只保留在本地，不会提交到远端。

## 安装

Windows PowerShell：

```powershell
.\githooks\install.ps1
```

Git Bash/Linux/macOS：

```bash
sh githooks/install.sh
```

安装脚本会执行：

```bash
git config core.hooksPath githooks
```

并交互生成本地配置文件：

```text
.ai-review.env
```

## 交互配置项

安装时会询问：

```text
AI base URL
AI model
AI API key
Notify when
Notification channel
```

推荐配置示例：

```bash
AI_REVIEW_BASE_URL=https://win.gxapi.site/v1
AI_REVIEW_MODEL=gpt-5.5
AI_REVIEW_API_KEY=你的API_KEY
AI_REVIEW_NOTIFY_ON=always
```

`AI_REVIEW_BASE_URL` 支持两种写法：

```bash
AI_REVIEW_BASE_URL=https://win.gxapi.site/v1
AI_REVIEW_BASE_URL=https://win.gxapi.site/v1/chat/completions
```

Hook 会自动把 `/v1` 转成 `/v1/chat/completions`。

## 通知配置

`AI_REVIEW_NOTIFY_ON` 控制什么时候通知：

```bash
always  # 每次 review 成功或异常都通知
fail    # 只有 AI 返回 结论: FAIL 时通知
error   # 只有 AI 接口异常或响应格式异常时通知
never   # 不发送通知
```

### 桌面通知

```bash
AI_REVIEW_DESKTOP_NOTIFY=true
```

支持 macOS `osascript`、Windows PowerShell 和 Linux `notify-send`。

### 飞书

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_FEISHU_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

### 企业微信

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx
```

### 钉钉

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx
```

### 邮件

163 邮箱示例：

```bash
AI_REVIEW_NOTIFY_ON=always
AI_REVIEW_EMAIL_TO=你的邮箱@163.com
AI_REVIEW_EMAIL_FROM=你的邮箱@163.com
AI_REVIEW_SMTP_HOST=smtp.163.com
AI_REVIEW_SMTP_PORT=465
AI_REVIEW_SMTP_USERNAME=你的邮箱@163.com
AI_REVIEW_SMTP_PASSWORD=SMTP授权码
AI_REVIEW_SMTP_STARTTLS=false
AI_REVIEW_SMTP_SSL=true
```

说明：

- `AI_REVIEW_SMTP_USERNAME` 通常就是完整邮箱地址。
- `AI_REVIEW_SMTP_PASSWORD` 通常不是邮箱登录密码，而是邮箱后台生成的 SMTP 授权码。
- 163 邮箱使用 `465` 端口时应配置 `SMTP_SSL=true`、`SMTP_STARTTLS=false`。
- 发送方和接收方可以是同一个邮箱。
- 邮件会同时发送纯文本和 HTML 两种格式；HTML 中 `FAIL`、阻断问题、非阻断建议、验证建议会使用不同颜色展示。

## IDEA 中看不到提示怎么办

IDEA 提交成功时，Git hook 的 stdout/stderr 不一定明显展示。通常可以在这些地方找：

- Commit 工具窗口底部输出区域
- Version Control / Git 控制台
- `.git/ai-review/last-review.md`

如果配置了桌面通知、飞书、邮件、企业微信或钉钉，建议以通知为准。

## 输出文件

每次运行会写入：

```text
.git/ai-review/staged.diff       # 本次暂存区 diff
.git/ai-review/request.json      # 发给 AI 的请求
.git/ai-review/response.json     # AI 原始响应
.git/ai-review/last-review.md    # AI review 文本结果
.git/ai-review/notification.txt  # 异常通知内容
```

## 手动测试 AI 配置

可以用一次临时 commit 测试，也可以直接检查接口。

PowerShell 中测试 `/models`：

```powershell
$headers = @{
  Authorization = "Bearer 你的API_KEY"
  "Content-Type" = "application/json"
}
Invoke-WebRequest `
  -Uri "https://win.gxapi.site/v1/models" `
  -Headers $headers `
  -Method Get
```

测试 chat completions：

```powershell
$headers = @{
  Authorization = "Bearer 你的API_KEY"
  "Content-Type" = "application/json"
}
$body = @{
  model = "gpt-5.5"
  messages = @(@{ role = "user"; content = "只回复 OK" })
  temperature = 0
} | ConvertTo-Json -Depth 5

Invoke-WebRequest `
  -Uri "https://win.gxapi.site/v1/chat/completions" `
  -Headers $headers `
  -Method Post `
  -Body $body
```

## 常用开关

```bash
AI_REVIEW_ENABLED=true
AI_REVIEW_COMPILE=false
AI_REVIEW_RUN_TESTS=false
AI_REVIEW_REQUIRE_API=false
AI_REVIEW_FAIL_ON_AI_ERROR=false
AI_REVIEW_FAIL_ON_FINDINGS=false
AI_REVIEW_MAX_DIFF_BYTES=120000
AI_REVIEW_TIMEOUT_SECONDS=90
AI_REVIEW_ASYNC=true
```

如果需要恢复同步执行：

```bash
AI_REVIEW_ASYNC=false
```

如果希望 AI 返回 `结论: FAIL` 时阻止 commit：

```bash
AI_REVIEW_FAIL_ON_FINDINGS=true
```

如果希望 AI 接口异常时阻止 commit：

```bash
AI_REVIEW_REQUIRE_API=true
AI_REVIEW_FAIL_ON_AI_ERROR=true
```

如果临时跳过 hook：

```bash
git commit --no-verify
```

或者：

```bash
AI_REVIEW_ENABLED=false git commit -m "message"
```

## 多项目复用

复制整个 `githooks/` 目录到另一个项目，然后执行：

```powershell
.\githooks\install.ps1
```

或：

```bash
sh githooks/install.sh
```

每个项目会生成自己的 `.ai-review.env`。如果多个项目共用同一套配置，也可以把配置放到用户目录：

```text
~/.ai-review.env
```

仓库根目录的 `.ai-review.env` 会覆盖用户目录配置。

## 排障

### commit 时没有触发 hook

检查：

```bash
git config core.hooksPath
```

应该输出：

```text
githooks
```

如果没有，重新安装：

```powershell
.\githooks\install.ps1
```

### AI 返回 HTML，不是 JSON

通常是 `AI_REVIEW_BASE_URL` 配错了。应配置为：

```bash
AI_REVIEW_BASE_URL=https://win.gxapi.site/v1
```

或：

```bash
AI_REVIEW_BASE_URL=https://win.gxapi.site/v1/chat/completions
```

### 邮件中文乱码

当前 hook 已使用 UTF-8 + base64 发送邮件正文。若仍乱码，优先检查邮件客户端显示编码，或确认不是测试脚本在发送前已把中文变成了 `?`。

### 邮件发送失败

163 邮箱重点检查：

```bash
AI_REVIEW_SMTP_PORT=465
AI_REVIEW_SMTP_SSL=true
AI_REVIEW_SMTP_STARTTLS=false
AI_REVIEW_SMTP_PASSWORD=SMTP授权码
```

不要使用网页登录密码。

### 不想提交 githooks 到远端

确认：

```bash
git check-ignore -v githooks/pre-commit .ai-review.env
git ls-files githooks
```

`git ls-files githooks` 没有输出，说明不会被提交。
