# Connect Codex to AUV / 在 AUV 中连接 Codex

## English

### Start here

1. Install the official Codex desktop app and sign in with your ChatGPT account.
2. Open AUV and allow its local Codex connection.
3. Choose **Scan for Agents**, select Codex, then **Refresh**.

You do not need to choose an executable or enter a developer command. AUV looks for Codex in system and user application folders and macOS-registered locations, then checks its app identity and developer signature.

### Already signed in, but no allowance appears?

Open the Codex entry's connection details and use the matching step below.

| What you see | What to do |
| --- | --- |
| Codex unavailable | Open the official Codex app once, then scan again. If needed, install or update it. |
| Sign-in required | Sign in with ChatGPT in Codex, then refresh AUV. An API-key-only login may not provide a plan allowance. |
| Update required | Update Codex, open it, then refresh AUV. |
| No response or connection failure | Confirm Codex opens normally. Refresh AUV once; if it still fails, keep the connection detail for a bug report. |
| Allowance appears, but token statistics do not | The account connection can still be valid. Token statistics are optional and depend on the Codex version. |

AUV 0.17.2 improves compatibility with Codex versions that omit optional connection metadata. Account availability still depends on your Codex version, sign-in and subscription.

AUV reads the allowance returned by Codex without starting an AI task. It does not count ChatGPT website messages or read conversations for this connection. Copying login files, granting Full Disk Access, or disabling system security is not part of normal setup.

### If you need help

[Open an issue](https://github.com/ShaoJHe-SilkRoad/UMA/issues) with your AUV version, macOS version, chip type, Codex version and the connection message. A screenshot is useful; hide account details. Never include passwords, API keys or login files.

For Claude, use its supported status-line or browser-companion connection; installing Claude alone may not provide exact account allowance. Local estimates stay labelled as estimates. Each provider has its own compatibility limits. See [Mac compatibility](MAC_COMPATIBILITY.md).

## 中文

### 首次连接

1. 安装官方 Codex 桌面应用，使用 ChatGPT 账户登录。
2. 打开 AUV，允许连接本机 Codex。
3. 点击**“扫描智能体”**，选择 Codex，再点击**“刷新”**。

无需选择可执行文件或输入开发命令。AUV 会查找系统应用目录、个人应用目录和 macOS 已登记的位置，并核验 Codex 的应用身份与开发者签名。

### 已经登录，仍然没有额度？

展开 Codex 条目的连接详情，按提示处理。

| 提示 | 处理方法 |
| --- | --- |
| Codex 不可用 | 先打开一次官方 Codex，再重新扫描；必要时安装或更新 Codex。 |
| 需要登录 | 在 Codex 中使用 ChatGPT 登录，再刷新 AUV。只用 API Key 登录可能没有套餐额度。 |
| 需要更新 | 更新并打开 Codex，再刷新 AUV。 |
| 没有响应或连接失败 | 确认 Codex 能正常打开，再刷新一次；仍失败时保留连接详情用于反馈。 |
| 有账户额度，没有 token 统计 | 账户连接仍可能正常。Token 统计是可选信息，取决于 Codex 版本。 |

AUV 0.17.2 改善了缺少可选连接信息时的兼容性。账户能否返回额度，仍取决于你的 Codex 版本、登录方式和订阅。

AUV 通过 Codex 返回的数据读取额度，不为此启动 AI 任务，也不统计 ChatGPT 网页消息或读取对话。正常设置无需复制登录文件、授予“完全磁盘访问权限”或关闭系统安全保护。

### 反馈问题

[提交问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)时，请附上 AUV 版本、macOS 版本、芯片类型、Codex 版本和连接提示。可以附截图，但请遮住账户信息，不要提供密码、API Key 或登录文件。

Claude 需使用支持的状态行或浏览器伴侣连接；仅安装 Claude 不保证能取得准确账户额度。本地估算会明确标注。各智能体的兼容性限制不同，详见 [Mac 兼容性](MAC_COMPATIBILITY.md#中文)。
