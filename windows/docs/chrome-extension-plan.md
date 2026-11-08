# AUV Windows：Claude 浏览器伴侣（Chrome / Edge 扩展）开发计划

状态：**计划稿，待用户批准**。本文件只是计划，没有写任何实现代码。
日期：2026-11-08 · 基线：`origin/main` `c594df0`（AUV Windows 0.18.4，tag `v0.18.4-win`）
范围：给 AUV Windows 版做一个 Chrome 扩展（Edge 顺带支持），实现 Mac 上 Safari 伴侣的功能：从用户自己已登录的 claude.ai 用量页读取 Claude 的精确额度百分比和重置时间，交给 AUV 显示。

> 本计划以用户这次的明确要求为准，替代 0.18.4 中“Windows 不模仿 Safari 读取”的规则（只对这项工作生效）。决定 C0（Claude 在 Windows 上显示“不可用”）会在本功能启用并连接成功后解除，未启用时保持不变。

---

## 1. Mac Safari 伴侣现状（只读调研结论）

### 1.1 组成

| 组件 | 位置 | 作用 |
|---|---|---|
| Safari Web 扩展（MV2，常驻后台页） | `BrowserExtension/Safari/manifest.json`、`BrowserExtension/Shared/*.js` | 开一个“自有”标签页打开用量页，读 DOM，把规范化结果交给原生端 |
| 扩展原生处理器（appex，沙盒） | `BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift` | 校验每条消息（逐层精确键名白名单），写入 App Group 收件箱；保存自有标签页回执 |
| UMA Safari Bridge Host（独立签名 App，无窗口） | `Sources/UMASafariBridgeHost/`、`Sources/ClaudeSafariHostIPC/` | 通过 `SFSafariApplication.dispatchMessage` 向扩展发命令；与 AUV 用 JSON 信箱文件通信 |
| AUV 主程序 | `Sources/CodexUsageUI/Connectors/Claude*.swift`、`Stores/ClaudeBrowserSettingsModel.swift`、`Services/ClaudeSmartUsageEngine.swift` | 调度精确同步、接收读数、新鲜度、提示框、界面 |

进程之间没有 XPC，也没有 socket，全部通过 App Group 目录里的文件交接（0700 目录、0600 文件、禁止符号链接、`flock` 监听锁、`RENAME_EXCL` 发布）。

### 1.2 读取的数据与来源

- **只读一个页面**：`https://claude.ai/new#settings/usage`（Claude 官方的个人用量页）。扩展声明的主机权限只有 `https://claude.ai/new*`，内容脚本只在顶层框架运行。
- 提取器 `claude-usage-extractor.js` 只认精确路由（协议、源、路径、无 query、hash 完全一致），页面上有登录表单时直接判为“需要登录”。
- 读取字段：
  - `fiveHour`：已用百分比（0–100）和重置时间；
  - `weeklyAllModels`：已用百分比和重置时间；
  - `modelSpecificWeekly`：Sonnet、Opus 或 Haiku 中唯一的一项（会做校验，但 AUV 不使用）。
- 重置时间：优先读 `time[datetime]` 或 `data-reset-at`；没有时只认几种固定写法（“Resets at 6:40 PM”“Resets Saturday 9:00 AM”“Resets tomorrow at …”“Resets Nov 2, 9:00 AM”），按浏览器所在时区换算。倒计时写法不读；超出窗口长度的时间丢弃。
- **无法唯一确定时宁可不报**：同一行出现两个百分比、两个不同的重置时间或第二个额度标签，都不报。
- 内容脚本要求连续两次读到相同结果才算稳定，期限 20 秒。
- **永远不出页面的内容**：页面源码、整页文本、URL 参数、套餐名、账户身份、消费数据。协议里根本没有这些字段。
- AUV 最终保留：两个窗口的已用百分比（换算为剩余 = 100 − 已用）、重置时间和 `observedAt`。

### 1.3 扩展与 App 的通信（Mac）

1. AUV → Host（信箱文件）：`verifyCompanion`、`accuracySync`、`automaticRefresh` 或 `closeOwnedTab`。
2. Host → 扩展（`dispatchMessage`）：
   - `umaClaudeWakeBridge`：唤醒；
   - `umaClaudeRuntimeQualification`：资格校验；
   - `umaClaudeAutomaticRefresh`：读取，带 `placement` = `existingWindow` 或 `temporaryWindow`；
   - `umaClaudeCloseOwnedUsageTab`：关闭自有标签页。
3. 扩展 → 原生处理器（`sendNativeMessage`）：
   - 自动化事件 `claudeBrowserAutomationEvent`：`extensionBackgroundReady`、`refreshStarted` 等；
   - 观测信封 `claudeUsageObservation`；
   - 终止包 `claudeBrowserTerminalPacket`；
   - 自有标签页回执命令 `claudeOwnedProviderTabV2ReceiptCommand`。
4. 所有消息 ≤ 4096 字节，`schemaVersion = 2`，每一层都精确匹配键名，ID 必须是 UUID。
5. 打包时生成的 `runtimeGenerationID` 写入扩展、Host 和 AUV 三方，三方一致才算“同一套安装”，否则报版本不匹配。
6. **自有标签页**：每次读取生成 43 字符的一次性 nonce，打开 `…#settings/usage?uma_ot=<nonce>`。内容脚本在 `document_start` 就用 `history.replaceState` 去掉 nonce，再通过 Port 出示 nonce 证明“这是 AUV 开的标签页”。
   - 回执只保存 nonce 的 SHA-256；
   - 状态机共 13 个状态，每一步都是比较并交换；
   - 只有证明属于 AUV 的标签页才会被关闭。用户自己打开的 claude.ai 标签页永远不读、不关。

### 1.4 刷新、重试与恢复（Mac 0.18.2–0.18.4）

| 行为 | 数值 |
|---|---|
| 触发 | “全部刷新”与自动刷新（全局间隔 5/10/15/30/60 分钟）；启动后 15 秒首次同步 |
| 单次读取总期限 | 扩展端 30 秒；页面就绪 20 秒；AUV 端 45 秒后发关闭标签页命令 |
| 页面沉默 | 6 秒无回应判为被挂起（约 11 秒发现），同步开始 20 秒后若没有新读数则重试一次 |
| 原生消息无回复 | 8 秒放弃，不阻塞后续消息 |
| 连接断开重连 | 0 / 1 / 5 / 15 / 60 秒，持续重连不放弃 |
| 存活检查 | 每 60 秒一次；闲置 5 分钟的连接更换；连续 2 次不通就自我重载（两次重载至少间隔 30 分钟） |
| 重复命令 | 按命令名加 requestID 去重（记住最近 64 条） |
| Safari 不在当前桌面 | 改用一个 480×640 的临时窗口，读完关闭 |
| Safari 未运行 | 询问是否在后台打开（自动刷新一轮只问一次，可勾选“自动刷新时不再询问”） |
| 伴侣持续沉默 | ≥2 次沉默且 ≥180 秒后询问是否重启 Safari。按钮前 4 秒不可点，回车等于“暂不”；会提示可能丢失标签页 |
| 新鲜度 | 精确读数在 max(5 分钟, 间隔 + 2 分钟) 内算当前；0.18.4 说明称之后最多再显示 2 小时并标记过期 |

### 1.5 隐私保证

- 每层精确键名白名单；百分比必须有限且在 0–100；时间戳 ≤ 64 字节；只接受 UUID；有大小上限。
- 协议中没有 URL、页面文本、Cookie、令牌、凭据字段。日志只记固定错误码，页面追踪只允许受限字符集。
- AUV 只接受自己发起、requestID 匹配、`observationID` 没见过的观测，主动推送的一律拒绝。
- 登录状态始终留在浏览器自己的会话里，AUV 不接触。

### 1.6 用户看到的内容

- Claude 设置卡有三行状态：本地智能、浏览器伴侣、浏览器精确同步。按钮包括“请求 Safari 网站访问权限”“检查浏览器伴侣”“修复伴侣”“重新检查”“断开 Claude”。
- 智能体页面提示：“正在同步精确读数…”“浏览器伴侣正在启动…”“浏览器伴侣需要更新…”“在线验证不可用”。
- 两个询问框：“打开 Safari 以更新 Claude 用量？”和“重启 Safari 以恢复 Claude 同步？”。
- 失败原因文案：需要网站权限、需要登录、Safari 不可用、页面结构不支持、版本不匹配等，中英双语，见 `AppLanguage+Claude.swift`。
- 默认关闭，需要用户同意（`ClaudeLocalSmartModeConsent.v1` 默认 false）。

### 1.7 仓库里已有的 Chromium 变体（`BrowserExtension/Chromium/`）

这是一个 MV3 的“点工具栏读一次”原型：固定 `key`，扩展 ID 为 `jgoknghcplngcnldmfenkghcbommaalj`，原生主机名 `com.silkrd.uma.claude_browser`。它**已经没有在用**：

- 当前 Mac 打包不含它，也没有代码注册它；
- 它的读数不会被 AUV 接受；
- 观测、事件、终止包的解码器都写死了 `browserFamily == "safari"`。

结论：可以参考，不能直接复用。共享的提取器、内容脚本、所有权模块和状态机（`BrowserExtension/Shared/`）可以原样复用；后台逻辑 `background-core.js` 与 Safari 绑定太深，需要为 Chromium 另写。

---

## 2. Windows 现状与接入点

- `ProviderController`（`windows/src/AUV.Windows.App/ProviderController.cs`）是所有智能体的唯一接入点：
  - `Admit(id, build)` 负责上屏；
  - `RunAll` 是“全部刷新”和定时刷新的入口；
  - `EnforceFreshness` 每 30 秒撤下过期读数；
  - Claude 目前由 `PreparedConnections.Plans` 里的 `PreparedUsageConnector` 返回“Windows 上暂不可用”。
- 接入方式：
  1. 新增 `ClaudeBrowserConnector`（实现 `IReadOnlyUsageConnector`，`Stage = Live`）；
  2. 从 `PreparedConnections.Plans` 中移除 claude；
  3. 在 `RunAll` 里加入 `RefreshClaudeAsync()`（仅在用户启用且伴侣已连接时）；
  4. 解码结果仿照 `CodexUsageDecoder` 生成 `AgentPresentation`，含 `QuotaWindow("claude.fiveHour", 300, …)` 和 `QuotaWindow("claude.weekly", 10080, …)`，复用 `QuotaWindowPolicy.Select` 和 `ResetText.Format`，与 Codex 显示规则一致。
- `PreparedClaudePacketDecoder` 是给“状态行数据包”准备的另一种格式（schema 1），与浏览器伴侣无关，保留不动。
- `ReadingFreshness`：当前为“间隔 + 2 分钟”（关闭自动刷新时为 15 + 2 分钟），过期即隐藏；WorkBuddy 单独用 10 分钟。
- `SettingsStore`：`settings.v1.json`，`Version = 1`；新增字段靠初始化器提供默认值，System.Text.Json 会忽略未知字段，所以 0.18.4 也能读新文件。
- **先例**：`WorkBuddyConnectionWindow` 用 WebView2 加 AUV 自有浏览器配置（`workbuddy-web-<hash>`）读官方页面：
  - 注入嵌入资源脚本，拿到严格 JSON 后用 C# 解码器校验；
  - “断开连接”只清除自有配置。
  - 其中“严格解码、只上屏允许范围内的字段、失败就隐藏”的模式直接沿用。
- 单实例：`PreviewInstance` 用设置路径的 SHA-256 前 24 位作为 `Local\AUV.Windows.Preview.<key>` 互斥体名。命名管道可以用同一个 key。
- 打包：`build.ps1 -Publish` 以 win-x64 自包含方式发布，`package-product-preview.ps1` 生成 ZIP、SOURCE-MANIFEST、BUILD-INFO 和 HASHES。

---

## 3. 本机环境（2026-11-08 实测）

| 项 | 结果 |
|---|---|
| Google Chrome | 157.0.8103.38（`C:\Program Files\Google\Chrome\Application`），正在运行 |
| Microsoft Edge | 157.0.4341.42，正在运行 |
| WebView2 Runtime | 157.0.4341.42 |
| `HKCU\Software\Google\Chrome\NativeMessagingHosts` | 已有 5 个其他软件的项（不会碰它们） |
| `HKCU\Software\Microsoft\Edge\NativeMessagingHosts` | 存在，为空 |
| Chrome 企业策略 | 无（`HKLM/HKCU\SOFTWARE\Policies\Google\Chrome` 都不存在），即非受管设备 |
| Edge 策略键 | `HKLM\SOFTWARE\Policies\Microsoft\Edge` 存在，未见具体值 |

---

## 4. Chrome MV3 与本地程序通信：调研结论

### 4.1 通道对比

| 方案 | 结论 | 理由 |
|---|---|---|
| **A. 原生消息（Native Messaging）+ 本地主机程序** | **推荐** | Chrome 和 Edge 官方支持。主机清单通过 **HKCU** 注册表注册，不需要管理员。浏览器按 `allowed_origins` 只让指定扩展 ID 启动主机；主机第一个参数是调用方 origin，可以二次校验。`connectNative` 打开的 Port 从 Chrome 105 起能让 MV3 Service Worker 保持存活，等价于 Safari 的常驻后台页。 |
| B. localhost HTTP/WebSocket | 不推荐 | 任何网页和本机进程都能访问 localhost，需要共享密钥，密钥就得落盘（违反“不写凭据”）；还要处理 Chrome 对私有网络访问的限制、端口冲突和防火墙。 |
| C. 在 AUV 内用 WebView2 打开 claude.ai（同 WorkBuddy） | 作为备选，不作为本项 | 不是 Chrome 扩展，与用户要求不符；用户要在 AUV 的嵌入浏览器里重新登录 Claude（凭据留在 AUV 的配置目录，虽然 AUV 不读取）；Google 登录通常拒绝嵌入式浏览器。 |
| D. 扩展直接调 claude.ai 内部 JSON 接口 | 不推荐 | 不是公开接口，会带上组织 ID 等账户标识，随时可能变。Mac 刻意只读官方页面 DOM，这里保持一致。 |

### 4.2 原生消息要点（Chrome 与 Edge 官方文档）

- 主机清单字段：`name`（小写字母、数字、下划线、点）、`description`、`path`（Windows 可以写相对于清单文件的路径）、`type: "stdio"`、`allowed_origins`（必须是完整的 `chrome-extension://<id>/`，**不允许通配符**）。
- 注册：`HKCU\Software\Google\Chrome\NativeMessagingHosts\<name>`，默认值为清单的完整路径。Edge 用 `HKCU\Software\Microsoft\Edge\NativeMessagingHosts\<name>`。
- **Edge 的差异**：查找顺序是 Edge 键 → Chromium 键 → Chrome 键（先 HKCU 后 HKLM），**只读找到的第一个清单**。只注册 Chrome 键时 Edge 也能找到；如果分别从 Chrome Web Store 和 Edge Add-ons 安装，两个商店的扩展 ID 不同，`allowed_origins` 要把两个都列上。解压加载（unpacked）时，只要 manifest 里有同一个 `key`，两个浏览器算出的扩展 ID 相同。
- 帧格式：4 字节本机字节序长度加 UTF-8 JSON。主机发给浏览器单条 ≤ 1 MB；浏览器发给主机，Chrome 文档写 64 MiB，Edge 文档写 4 GB。我们自己再限制为 ≤ 4096 字节，与 Mac 一致。
- 标准输入输出必须用二进制模式（.NET 直接读写 `Console.OpenStandardInput/Output` 的 Stream 即可，不经过 TextReader）；调试输出写 stderr。
- `connectNative`：一个 Port 对应一个主机进程，Port 关闭主机就退出。`sendNativeMessage` 每条消息启动一个新进程，不适合我们。
- 从 Service Worker 启动时，Windows 上会传 `--parent-window=0`。
- MV3 生命周期：闲置 30 秒终止，单个事件最长 5 分钟；`connectNative` Port 能保持 SW 存活，主机退出后要在 `onDisconnect` 里重连；`chrome.alarms` 最小周期 30 秒（Chrome 120 起）。

### 4.3 分发方式（Windows 包未签名）

| 方式 | 可行性 | 说明 |
|---|---|---|
| **开发者模式“加载已解压的扩展程序”** | **可行，首发推荐** | 用户在 `chrome://extensions` 打开开发者模式，选择 AUV 提供的文件夹。Chrome 137 起品牌版已移除 `--load-extension` 命令行参数，所以 AUV 不能替用户装，只能引导。文件夹必须一直保留在原位置。Chrome 可能显示开发者模式扩展提示。 |
| Chrome Web Store / Edge Add-ons | 可行，后续 | 需要用户自己的开发者账号（Chrome 一次性注册费）、隐私政策页、商店审核。商店扩展 ID 由商店分配，主机清单要列出。上架后自动更新，没有开发者模式提示。 |
| 注册表外部安装（`…\Chrome\Extensions\<id>` + `update_url`） | 只在上架后可行 | Windows 上 `update_url` 必须指向 Chrome Web Store；本地 CRX 自 Chrome 33 起在 Windows 上不允许外部安装。 |
| 企业策略 `ExtensionInstallForcelist` 自托管 | 不适用 | Windows 上商店外的扩展只能在加入域、Entra ID 或云管理的设备上强制安装（Edge 文档写明，Chrome 规则相同）；本机是非受管设备。 |

另外，**原生主机 exe 不需要签名**，浏览器只按注册表和清单启动它。但未签名的 exe 可能被 Defender 或 SmartScreen 拦截，属于风险项（见 §12）。

### 4.4 扩展能从 claude.ai 读什么

- 在用户已登录的 Chrome 中，内容脚本与页面同源，能读到页面 DOM，因此读取方式与 Mac 完全一致，只读用量页 DOM。
- 扩展不调用 `chrome.cookies`，不申请 `cookies`、`webRequest`、`tabs`（读 URL）、`history` 等权限。
- AUV 和主机程序都拿不到 Cookie 或令牌，协议里也没有这些字段。
- 用户自己打开的 claude.ai 标签页，没有 AUV 的 nonce 就不会被读取（共享内容脚本的既有行为）。

---

## 5. Mac → Windows 功能对照表

| # | Mac Safari 功能 | Windows Chrome/Edge 对应 | 备注 |
|---|---|---|---|
| 1 | Safari Web 扩展（MV2，常驻后台页） | Chrome MV3 扩展，`connectNative` Port 让 SW 常驻 | 新写 `background-chromium.js` |
| 2 | 提取器 `claude-usage-extractor.js` | **原样复用**（固定副本 + 哈希比对测试） | 读取规则、字段、失败即不报都一样 |
| 3 | 内容脚本、nonce 自有标签页、`provider-ownership-v2.js`、状态机 reducer | **原样复用** | 内容脚本里 MV2 才有的“恢复候选”路径在 MV3 下不触发，nonce 路径照常工作 |
| 4 | 原生处理器 appex（沙盒、App Group 文件） | `AUV.BrowserHost.exe`（原生消息主机，只做校验和转发）+ 命名管道连到 AUV | 不落盘 |
| 5 | UMA Safari Bridge Host（独立签名 App） | 合并进 AUV 本体的管道服务端，加上主机程序 | Windows 不需要一个永远不替换的 Host |
| 6 | 信箱文件 IPC（0700/0600、flock） | 命名管道，`PipeOptions.CurrentUserOnly`，长度前缀 JSON，≤ 8 KB | 同用户之外的进程连不上 |
| 7 | 运行时资格校验（Bundle ID、Team ID、签名 plist 中的 generation） | 扩展 origin（argv[1]）+ 打包时写入的 `runtimeGenerationID` + 伴侣版本/协议版本握手 | 没有代码签名，Team ID 不适用 |
| 8 | 唤醒、资格、读取、关闭四种命令 | 同名命令，经管道 → 主机 → Port 下发 | `browserFamily = "chromium"` |
| 9 | 位置 `existingWindow` / `temporaryWindow` | `backgroundTab`（已有普通窗口时开后台标签）/ `minimizedWindow`（没有窗口时开最小化的小窗口） | 用 `chrome.windows.getAll` 判断，不需要“当前桌面”检测 |
| 10 | 回执保存在原生端（plist） | 保存在 `chrome.storage.session`（只存 requestID、tabId、nonce 摘要、时间、状态、revision） | 不含任何内容数据，浏览器重启即清空 |
| 11 | 页面沉默 6 秒、20 秒重试、30/45 秒期限 | 同样的数值，先照搬，实测后再调 | Chrome 不会像 Safari 那样挂起后台标签，但会节流计时器、“节省内存”会丢弃标签页 |
| 12 | 原生无回复 8 秒放弃、0/1/5/15/60 秒重连、60 秒存活检查、5 分钟闲置更换、自我重载间隔 30 分钟 | 同样实现；重载用 `chrome.runtime.reload()`，时间戳存 `chrome.storage.local` | |
| 13 | 重复命令丢弃 | 同样实现 | |
| 14 | “全部刷新”和自动刷新时同步 | 加入 `ProviderController.RunAll`，共用 Windows 的刷新间隔 | |
| 15 | Safari 未运行时询问是否在后台打开 | “Chrome 未运行，是否打开以更新 Claude 用量？” | 打开方式待实测（见 D9）；按钮 1 秒后可点，可勾选“自动刷新时不再询问” |
| 16 | 沉默时询问重启 Safari（4 秒保护） | 首发建议**不替用户重启 Chrome**，只提示“在扩展页重新加载伴侣或重启浏览器” | 见 D10 |
| 17 | Bridge 版本不匹配提示 | 伴侣版本或 generation 不匹配：“浏览器伴侣需要更新” | |
| 18 | 站点权限（`permissions.contains`） | 同样检查；用户把站点访问改成“点击时”就报“需要网站访问权限” | |
| 19 | 新鲜度：max(5 分钟, 间隔 + 2 分钟)，之后标记过期继续显示 | 见 D8：建议沿用 Windows “过期即隐藏” | |
| 20 | Developer ID 签名、公证 | 不适用 | Windows 包未签名 |
| 21 | Claude Code 本地记录估算（`ClaudeCodeUsageConnector` 的本地部分） | **不在本项** | 与 Safari 伴侣无关，Windows 上尚未验证 |
| 22 | Chromium 工具栏“读一次” | 可选：点工具栏图标让 AUV 立即同步一次（结果仍走正式请求流程） | 见 D13 |
| 23 | 已停用的“净化缓存”文件 | 不做，读数只在内存中，与 Windows 0.18.4 一致 | |

---

## 6. 推荐架构

```
┌──────────── Chrome / Edge（用户已登录 claude.ai）────────────┐
│  MV3 扩展 “AUV Browser Companion for Claude”                  │
│   ├ service worker: background-chromium.js（新写）            │
│   │   connectNative("com.silkrd.auv.claude_browser") 常驻     │
│   └ content script（复用 Mac Shared）: 仅 https://claude.ai/new*│
│       nonce 自有标签页 → 提取器 → 规范化结果                  │
└───────────────│ stdio（4 字节长度 + JSON，≤4 KB）──────────────┘
                ▼
   AUV.BrowserHost.exe（浏览器按 HKCU 注册表启动；校验 origin、逐条校验后转发）
                │ 命名管道 \\.\pipe\AUV.Windows.Preview.<key>.ClaudeBrowser
                │（CurrentUserOnly，≤8 KB，长度前缀 JSON）
                ▼
   AUV.exe：ClaudeBrowserBridgeServer → ClaudeBrowserConnector
            → 严格解码（C# 移植 Mac 解码规则）→ ProviderController.Admit("claude")
```

要点：

1. **启动方向**：浏览器只能由扩展主动连接主机，所以扩展在 `onStartup`、`onInstalled` 和 SW 启动时调用 `connectNative`。主机启动后连 AUV 的管道；AUV 没运行时，主机每 5 秒重试，同时告诉扩展“AUV 未运行”。这样扩展常驻，浏览器开着就随时可读。
2. **主机是哑转发**：
   - 不保存任何东西；
   - 每条消息按白名单和大小上限校验后才转发；
   - argv[1] 必须等于配置的扩展 origin，否则立即退出；
   - 只接受我们定义的消息类型。
3. **AUV 才是协调者**（相当于 Mac 的 Host）：
   - 同一时间只处理一个请求；
   - 按“唤醒 → 资格 → 读取 → 关闭”下发；
   - 只接受自己发起、requestID 匹配、`observationID` 没见过的观测；
   - 超时后发关闭标签页命令。
4. **多个浏览器或配置**：Chrome 和 Edge 同时装了扩展，或多个 Chrome 配置各装一份时，每个都会启动一个主机。AUV 只用一个：用户在设置中选的浏览器，默认“第一个就绪的”。其余连接显示为“已连接（备用）”，不发读取命令。
5. **主机程序形式**：独立的小控制台程序（.NET 10，win-x64），见 D2。

### 6.1 备选与取舍

| 备选 | 优点 | 缺点 |
|---|---|---|
| AUV.exe 加 `--native-host` 模式充当主机（不另做 exe） | 少一个程序，包更小 | 每次被浏览器拉起都要加载完整的 WPF 自包含程序，启动慢、内存大；还要绕开单实例互斥逻辑；GUI 子系统程序做 stdio 不直观 |
| 主机直接读写 AUV 设置目录里的文件（仿 Mac 信箱） | 与 Mac 结构相同 | Windows 上命名管道更简单，也更容易限定当前用户；文件方案需要自己做锁和清理 |
| 回执交给 AUV 保存（仿 Mac 原生回执） | 浏览器重启后也能追查残留标签页 | AUV 重启会丢失回执；`chrome.storage.session` 是 MV3 自带的，能扛住 SW 重启，更贴合 |
| WebView2 方案（§4.1 C） | 不需要扩展和开发者模式 | 不是用户要的 Chrome 伴侣；要在 AUV 中重新登录；Google 登录可能被拒 |

---

## 7. 数据流与消息协议

### 7.1 一次读取（时序）

1. 定时器或“全部刷新”触发 `ClaudeBrowserConnector.RefreshAsync()`，新建一个 requestID（UUID）。
2. AUV 通过管道 → 主机 → Port 发 `umaClaudeWakeBridge`，扩展回 `extensionBackgroundReady`（带伴侣版本、构建、协议版本、扩展 ID、generation）。
3. AUV 发 `umaClaudeRuntimeQualification`，扩展回资格请求，主机按自身配置生成资格答复，扩展回确认，最后 AUV 记为 `bridgeReady`。等价于 Mac 的 12 步阶段，Windows 合并为 4 步：已唤醒 → 资格已答复 → 资格已确认 → 就绪。
4. AUV 发 `umaClaudeAutomaticRefresh{placement}`：
   1. 扩展检查站点权限，写回执，创建标签页或最小化窗口（`active:false`）；
   2. 内容脚本出示 nonce，所有权得到证明后开始提取；
   3. 拿到稳定结果后经 Port 交给 SW，SW 发观测信封和终止包；
   4. SW 关闭自有标签页。
5. AUV 校验通过后上屏 Claude 卡片。失败时卡片显示对应原因，不显示数字。
6. 同步开始 20 秒后如果还没有被接受的观测，再试一次；45 秒期限到达时发 `umaClaudeCloseOwnedUsageTab`。

### 7.2 消息定义

**沿用 Mac schema v2**：观测信封、自动化事件、终止包的键名和取值规则不变，只把 `browserFamily` 换成 `"chromium"`。

- Mac 的身份字段在 Windows 上的含义：`containingApplicationIdentifier = "com.silkrd.auv.windows"`，`extensionIdentifier = <扩展 ID>`，`teamIdentifier = ""`（Windows 无签名，空串经过白名单校验）。
- 新增的 Windows 专用信封都带 `kind` 和 `schemaVersion`，同样精确匹配键名：

| 方向 | kind | 字段 |
|---|---|---|
| 主机 → AUV | `auvBrowserHostHello` (v1) | `hostVersion`、`hostBuild`、`extensionOrigin`、`browserProduct`（`chrome` 或 `edge`，由父进程映像名判断，判断不了就是 `unknown`）、`runtimeGenerationID` |
| AUV → 主机 | `auvBrowserHostWelcome` (v1) | `accepted`、`reason`（`accepted`、`generationMismatch`、`browserNotSelected`、`busy`） |
| 主机 ↔ 扩展 | `auvCompanionCommand` (v1) | `command`（四个 `umaClaude*` 之一）、`requestID`、`targetRequestID?`、`placement?`（`backgroundTab` 或 `minimizedWindow`） |
| 扩展 → 主机 | 原样的 Mac v2 事件、观测、终止包 | 主机逐条校验后转发 |
| 双向 | `auvCompanionPing` / `auvCompanionPong` (v1) | `pingID`；60 秒一次，连续 2 次无回应视为沉默 |
| 扩展 → 主机 | `umaCompanionPageTraceV1` | 只进 AUV 诊断日志，内容为受限字符集的固定步骤名 |

- 大小上限：扩展 ↔ 主机每条 ≤ 4096 字节，管道每帧 ≤ 8192 字节，超过就断开连接。
- `runtimeGenerationID`：打包时生成，写进扩展的 `background-loader.js` 配置、主机配置和 AUV 的 BUILD-INFO。三方不一致时状态为“浏览器伴侣需要更新”，不读取。

---

## 8. 安全与隐私

1. **只读一个页面，只取几个数字**：路由、白名单和失败即不报的规则与 Mac 相同。不读套餐名、邮箱、组织 ID、对话或页面文本。
2. **AUV 不接触凭据**：登录状态只在 Chrome 自己的配置里；扩展不申请 `cookies` 权限；协议里没有凭据字段；AUV、主机、日志、测试数据和提交都不包含凭据或账户数据。
3. **扩展权限最小化**：
   - 只申请 `nativeMessaging`、`storage`，主机权限只有 `https://claude.ai/new*`；
   - 安装时浏览器会提示“读取和更改 claude.ai 上的数据”和“与协作的本机应用通信”。
4. **主机校验**：
   - argv[1] 必须是配置的扩展 origin；
   - 每条消息校验键名、大小和类型；
   - 主机不写任何文件，只往 stderr 写固定错误码，浏览器开启 `--enable-logging` 时才看得到。
5. **管道**：
   - 用 `PipeOptions.CurrentUserOnly`，只有当前用户的进程能连；
   - AUV 用 `GetNamedPipeClientProcessId` 取得对端进程路径，必须是已登记的主机程序；
   - 帧大小有上限，超时就断开。
6. **信任边界**：同一 Windows 用户下运行的恶意程序可以改 HKCU 注册表或伪造读数。这与 Mac App Group 的边界相当，在文档中如实写明。最坏情况是 Claude 显示错误的百分比，不会泄露凭据。
7. **读数只在内存**：与 Windows 0.18.4 一致，不新增磁盘缓存。设置文件里只多几项开关。
8. **隐私页文案更新**：说明 Claude 精确同步读什么、不读什么、登录状态在哪里、如何移除。

---

## 9. 在 Windows 上安装、注册与卸载

### 9.1 包内新增

```
AUV_Win_<ver>\
  AUV.exe …（不变）
  BrowserCompanion\
    extension\   manifest.json, background-loader.js, background-chromium.js,
                 Shared\claude-usage-extractor.js, provider-ownership-v2.js,
                 owned-provider-tab-v2-reducer.js, content-script.js, icons\
    host\        AUV.BrowserHost.exe（自包含单文件）, host-manifest.template.json
```

### 9.2 设置流程（用户在“Claude 设置 → 浏览器伴侣 → 设置”中操作）

1. **说明并征得同意**：列出将要写入的文件夹和注册表项。
2. **复制文件**：复制到稳定位置 `%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\`（见 D6）：
   - `host\<build>\`：每个构建一个新目录，不覆盖旧目录；
   - `extension\`：固定路径，开发者模式加载的扩展指向它，升级时先把旧内容备份为 `extension.backup-<build>\` 再替换；
   - 生成 `host\<build>\com.silkrd.auv.claude_browser.json`（`path` 写相对路径，`allowed_origins` 写扩展 ID）和 `host-config.json`（管道名、generation、允许的 origin，不含任何秘密）。
3. **写注册表**（只写 HKCU，不需要管理员）：
   - `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.silkrd.auv.claude_browser`；
   - `HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.silkrd.auv.claude_browser`；
   - 默认值都是清单完整路径。如果键已存在且指向别处，先记录原值，再询问用户，不直接覆盖。
4. **引导用户在浏览器中加载扩展**：
   - AUV 打开扩展文件夹并把路径复制到剪贴板，同时尝试打开 `chrome://extensions`（能否从命令行打开需实测，不行就显示步骤图文）；
   - 用户自己打开“开发者模式”，点“加载已解压的扩展程序”，选择该文件夹；
   - AUV 不替用户安装。
5. **用户确认 claude.ai 已登录**：AUV 只提示“请在 Chrome 中登录 claude.ai”，不打开登录页，也不经手任何凭据。
6. **验证**：扩展连上后 AUV 显示“浏览器伴侣已连接 · Chrome 157 · 伴侣 1.0.0”，再执行一次同步。

### 9.3 升级

新版 AUV 检测到 `browser-companion` 里的构建较旧，或 generation 不同时，显示“浏览器伴侣需要更新”，用户点“更新”：

1. 新建 `host\<newbuild>\`，旧目录保留；
2. 备份并替换 `extension\`；
3. 更新注册表值；
4. 提示用户在 `chrome://extensions` 点“重新加载”，或重启浏览器。

### 9.4 移除（卸载）

“Claude 设置 → 浏览器伴侣 → 移除”：

1. 删除上述两个 HKCU 键，只删值指向本目录的键；
2. 询问后删除 `browser-companion\`（这个目录是 AUV 自己创建的；删除前列出内容，用户同意才删）；
3. 提示用户到 `chrome://extensions` 移除扩展，AUV 无法替用户移除。

手动移除的命令写进文档：

```bat
reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
```

便携 ZIP 没有卸载程序。用户如果直接删掉 AUV 文件夹，主机程序仍在 `%LOCALAPPDATA%`，会照常启动但连不上 AUV，没有害处。文档中写明清理方法。

---

## 10. 界面改动（中英双语，产品名一律为 AUV）

1. **Claude 设置**（目前只有一段“暂不可用”说明，在 `SettingsWindow.xaml` 中新增 `ClaudePanel`）：
   - 开关：“通过浏览器同步 Claude 精确读数”（默认关）；
   - 浏览器：自动（第一个就绪的）/ Chrome / Edge；
   - 状态行：未设置、等待浏览器、已连接、需要更新、需要网站访问权限、请在浏览器中登录 claude.ai、正在同步、上次读取失败（原因）；
   - 按钮：设置 / 更新、打开扩展文件夹、立即同步、移除；
   - 说明：读什么、不读什么、读取时会短暂打开一个后台标签页或最小化窗口。
2. **Claude 智能体页**：与 Codex 相同的用量卡（5 小时和 7 天两个窗口，各带重置时间），来源写“Chrome 伴侣 · claude.ai 官方用量页”。没有读数时显示原因，例如“浏览器伴侣正在启动…”。
3. **“刷新”设置页说明**：改为“Codex；Claude（浏览器伴侣已连接时）；WorkBuddy（连接窗口打开时）”。
4. **隐私与数据页**：新增一段 Claude 说明。
5. **询问框**：“打开 Chrome 以更新 Claude 用量？”，含“自动刷新时不再询问”复选框；按钮 1 秒后才能点。
6. **托盘、托盘面板、托盘提示**：沿用现有规则；Claude 有当前读数时出现，`TrayAgentPolicy` 不改。
7. **桌面浮窗（Desktop Wizard）外观不变**：不改布局和样式，Claude 只是像其他智能体一样在有读数时出现在列表里（见 D12）。

---

## 11. 设置迁移与默认值

在 `PreviewSettings` 新增一个对象（`Version` 仍为 1）：

```json
"ClaudeBrowser": {
  "Enabled": false,
  "Browser": "auto",
  "Placement": "auto",
  "AskToOpenBrowser": true,
  "InstalledBuild": null
}
```

- 0.18.4 的 `settings.v1.json` 里没有这一项，读取时取上面的默认值：不启用，Claude 照旧显示不可用，直到用户主动开启。
- `Normalize()`：
  - `Browser` 不在 `auto|chrome|edge` 内时改为 `auto`；
  - `Placement` 不在 `auto|backgroundTab|minimizedWindow` 内时改为 `auto`；
  - `InstalledBuild` 只接受数字构建号，否则改为 null。
- 0.18.4 读到新文件时会忽略未知字段，双向兼容。测试会用 0.16.3 和 0.18.4 的真实格式样例（无账户数据）验证。
- 偏好目录仍为 `%LOCALAPPDATA%\AUV.Windows.UI.Preview`，新增子目录 `browser-companion\`，与现有的 `workbuddy-web-*` 并列。

---

## 12. 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| claude.ai 改版 | 读不到 → 显示原因，不显示错误数字 | 与 Mac 共用提取器，同步修复；哈希比对测试保证两边一致 |
| claude.ai 界面不是英文 | 提取器只认英文标签，会读取失败 | 文档写明需要英文界面；以后可与 Mac 一起扩展 |
| 开发者模式扩展会有提示，Chrome 将来可能进一步限制 | 用户体验差，可能失效 | 后续上架 Chrome Web Store / Edge Add-ons（D4） |
| 扩展文件夹被移动或删除 | 扩展失效 | 放在 `%LOCALAPPDATA%` 的稳定位置，不放在 ZIP 解压目录 |
| 未签名的主机 exe 被 Defender 或 SmartScreen 拦截 | 连不上 | 实测并在文档中如实写出；不绕过安全控制 |
| 每次同步都要开标签页或窗口，标签栏或任务栏会短暂出现 | 打扰用户 | 默认没有窗口时用最小化小窗口；间隔可调；实测后决定默认位置（D7） |
| “节省内存”、Edge 睡眠标签页、后台计时器节流 | 读取变慢或失败 | 20 秒重试；页面沉默检测；必要时把自有标签页设为 `autoDiscardable:false` |
| Chrome 关闭了所有窗口 | 不能读 | 询问是否打开；不申请 `background` 权限（D11） |
| 多个浏览器或配置同时连接 | 重复读取 | AUV 只用一个（§6 第 4 点） |
| Cloudflare 校验或需要重新登录 | 读不到 | 报“请在浏览器中登录 claude.ai”，不尝试自动处理 |
| 同用户恶意程序伪造读数 | 显示错误数字 | 如实写明信任边界；只要求 CurrentUserOnly 加对端路径校验 |
| 上架商店需要用户的开发者账号和隐私政策 | 进度依赖用户 | 首发用开发者模式，不受影响 |

---

## 13. 自动化测试与实机验证

### 13.1 自动化测试（xUnit，`windows/tests`）

- **解码器**（C# 移植 Mac 规则）：正例和每一类反例都要覆盖：
  - 多余键、缺键；
  - 百分比越界或是 NaN；
  - 时间戳超长；
  - ID 不是 UUID；
  - `browserFamily` 不对；
  - 两个窗口都缺；
  - 超过 4096 字节。
- **协调器**：只接受自己发起的观测；requestID 不匹配或 `observationID` 重复都拒绝；20 秒重试；45 秒后发关闭命令；同时只处理一个请求；generation 不匹配时不读取。
- **主机程序**：
  - 帧编解码（4 字节长度、二进制、上限、半帧）；
  - origin 不对时退出；
  - 每类消息的白名单；
  - AUV 未运行时重试，管道断开时恢复。
- **管道**：只有当前用户能连；对端路径校验；8 KB 上限。
- **注册与移除**：在测试专用的注册表根（`HKCU\Software\AUV-Test-<guid>`）和临时目录里做，验证：
  - 不覆盖他人的键；
  - 只删指向自己目录的键；
  - 升级不覆盖旧构建目录，且会先备份 `extension\`。
- **设置**：0.16.3 / 0.18.4 格式迁移，默认值，`Normalize` 边界。
- **共享 JS 一致性**：Windows 包里 4 个共享 JS 文件的 SHA-256 必须等于 `BrowserExtension/Shared/` 中对应文件（只读比对）。
- **界面文案**：中英都有，产品名为 AUV。

### 13.2 JS 测试（不新增 Node 依赖）

- 仿照现有的 opt-in 原生检查（`FeatureVerification` 等），在 WebView2 中加载 Mac 的用量页 HTML 样例（`Tests/Fixtures/ClaudeUsage/*.html`，只读引用或复制到 Windows fixtures），运行同一个提取器，结果必须与 Mac 测试一致。
- 新写 `chrome-harness.js`，仿 Mac 的 `background-harness.js`：用假的 `chrome.runtime/tabs/windows/storage` 和虚拟时钟驱动 `background-chromium.js`。覆盖：
  - 冷启动、Port 断开重连、无回复 8 秒放弃；
  - 重复命令、沉默页面、标签页被用户关闭；
  - SW 重启后凭回执清理、自我重载间隔。

### 13.3 实机验证（本机 Chrome 157 和 Edge 157）

需要用户自己在浏览器中登录 claude.ai，我不经手账号。

1. 全新设置：开发者模式加载 → 连接 → 读到 5 小时和 7 天两个窗口及重置时间，与网页显示一致。
2. 按 5 分钟间隔连续运行 1 小时，统计成功、重试和失败次数（与 Mac 0.18.4 的 13/13 对照，如实记录）。
3. 场景：
   - Chrome 最小化；Chrome 没有窗口；Chrome 未运行（询问框）；
   - 用户手动关闭自有标签页；
   - 用结束进程杀掉主机程序；在扩展页重新加载扩展；AUV 重启；
   - 睡眠唤醒；
   - “节省内存”开启；
   - 站点访问改为“点击时”；
   - claude.ai 退出登录。
4. Edge 重复关键场景；Chrome 和 Edge 同时连接时只读一个。
5. 升级：用 0.18.4 的偏好文件启动（先备份），设置保留，新项为默认值。
6. 移除：注册表键和文件按说明清掉，浏览器提示找不到主机。
7. 安装包：解压到新文件夹，二进制与受测版本一致。
8. 隐私核对：检查日志、设置文件和管道抓包内容，只出现白名单字段。

每一项都会如实报告结果：未测、失败或被平台拒绝的情况照写，不做规避。

---

## 14. 打包、发布与文档影响

- **ZIP**：
  - 新增 `BrowserCompanion\`（扩展约几十 KB；主机为自包含单文件，预计 15–30 MB，裁剪后实测）；
  - SOURCE-MANIFEST、BUILD-INFO、HASHES 中加入扩展文件、主机程序和 `runtimeGenerationID`。
- **构建**：
  - `build.ps1` 新增 `AUV.Windows.BrowserHost` 项目的发布；
  - `package-product-preview.ps1` 复制扩展，并生成带 generation 的 `background-loader.js`。
- **文档**（中英双语）：
  - `windows/README.md`、`docs/INSTALLATION.md`（Windows 节）新增“Claude 浏览器伴侣”安装、更新、移除步骤；
  - `docs/FIRST_INSTALL_TROUBLESHOOTING.md` 新增 Windows 排错（找不到主机、版本不匹配、需要网站权限等）；
  - 新的发布说明，删去“Claude 在 Windows 上没有读数”的表述，写明验证范围和限制。
- **版本号**：见 D14。Mac 侧不改。
- 推送、打 tag、GitHub Release 和网站改动都要等用户明确同意。

---

## 15. 里程碑与估算（工作日，不含等待用户的时间）

| 里程碑 | 内容 | 估算 |
|---|---|---|
| M0 | 用户确认本计划与决策 | — |
| M1 | Core：C# 解码器、协调器、`ClaudeBrowserConnector`、设置项与迁移、单元测试 | 2 天 |
| M2 | `AUV.BrowserHost.exe` 与命名管道服务端、注册与移除逻辑、测试 | 2 天 |
| M3 | MV3 扩展：manifest、`background-chromium.js`、共享 JS 固定副本、`chrome-harness` 测试、WebView2 提取器样例测试 | 3 天 |
| M4 | 界面：Claude 设置面板、智能体页、询问框、隐私和刷新文案、原生界面检查 | 2 天 |
| M5 | 实机验证（Chrome 与 Edge、1 小时运行、场景矩阵）并修问题 | 2 天 |
| M6 | 打包、文档、发布说明草稿、最终包复验 | 1 天 |
| 合计 | | **约 12 个工作日** |

每个里程碑结束时提交到本地分支并用中文汇报，不推送。

---

## 16. 需要用户决定的事项

1. **D1 通道**：采用“原生消息 + 主机程序 + 命名管道”（推荐），还是其他方案（localhost、WebView2）？
2. **D2 主机程序形式**：独立的小程序 `AUV.BrowserHost.exe`（推荐），还是让 AUV.exe 兼任主机？
3. **D3 浏览器范围**：首发同时支持 Chrome 和 Edge（推荐，几乎不增加工作量），还是只做 Chrome？
4. **D4 分发**：首发用开发者模式加载（推荐）；是否计划以后上架 Chrome Web Store / Edge Add-ons？上架需要你自己的开发者账号、隐私政策页和审核。
5. **D5 扩展 ID**：为 Windows 生成新的 key（推荐；manifest 里只放公钥，私钥不保存，不落盘），还是沿用 Mac Chromium 原型的 key（ID `jgoknghcplngcnldmfenkghcbommaalj`）？
6. **D6 文件位置**：把扩展和主机复制到 `%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\`（推荐，放在偏好目录内，与 `workbuddy-web-*` 并列），还是另用 `%LOCALAPPDATA%\AUV\BrowserCompanion\`，或者直接引用 ZIP 解压目录（不推荐，移动或删除后就失效）？
7. **D7 读取时打开的位置**：自动（已有窗口时用后台标签页，没有窗口时用最小化小窗口，推荐），还是始终用最小化小窗口？
8. **D8 新鲜度**：Claude 沿用 Windows 规则“间隔 + 2 分钟后隐藏”（推荐，与 0.18.4 的承诺一致），还是照搬 Mac 0.18.4“过期后标记并最多再显示 2 小时”？
9. **D9 浏览器未运行**：是否允许 AUV 在询问后打开 Chrome（最小化或后台方式需实测）？自动刷新一轮只问一次，并可勾选不再询问。
10. **D10 伴侣沉默**：首发只提示你在扩展页重新加载或自己重启浏览器（推荐），还是像 Mac 那样提供“重启 Chrome”按钮（4 秒保护、可能丢失标签页）？
11. **D11 后台运行**：不申请 `background` 权限，即 Chrome 关掉所有窗口后不再读取（推荐）；还是申请，让 Chrome 在后台保持运行？
12. **D12 桌面浮窗**：Claude 有读数时像其他智能体一样出现在桌面浮窗列表里，外观不变。这样可以吗？
13. **D13 工具栏按钮**：扩展图标点击后让 AUV 立即同步一次（推荐），还是不做？
14. **D14 版本号**：发布为 AUV Windows 0.18.5、0.19.0，还是你指定的版本？
15. **D15 默认状态**：功能默认关闭，你在 Claude 设置中开启并完成设置后才读取（推荐，与 Mac 需要同意一致）。确认吗？
16. **D16 共享 JS**：固定副本加哈希比对测试，Mac 改动后需要有意同步（推荐）；还是构建时直接从 `BrowserExtension/Shared/` 复制（自动跟随 Mac）？
17. **D17 JS 测试运行方式**：用 WebView2 跑（推荐，不新增依赖），还是允许测试使用 Codex 运行时自带的签名 Node？
18. **D18 范围外项**：Claude Code 本地记录估算、Antigravity 不在本项内，确认吗？

---

## 参考

- Chrome 原生消息：https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Edge 原生消息（注册表查找顺序、双商店 ID）：https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/native-messaging
- MV3 Service Worker 生命周期（`connectNative` 保活，Chrome 105）：https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
- 扩展安装方式（Windows 外部安装须指向 Chrome Web Store）：https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions
- 移除 `--load-extension`（Chrome 137）：https://developer.chrome.com/blog/extension-news-june-2025
- Edge `ExtensionInstallForcelist`（非受管设备限制）：https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/extensioninstallforcelist
- Mac 源码（只读）：`BrowserExtension/`、`Sources/ClaudeBrowserBridgeProtocol/`、`Sources/ClaudeBrowserNativeHostCore/`、`Sources/ClaudeSafariHostIPC/`、`Sources/UMASafariBridgeHost/`、`Sources/CodexUsageUI/Connectors/Claude*.swift`、`docs/releases/AUV_Mac_0.18.2–0.18.4.md`

---

## 17. 决策记录（2026-11-08，用户选择“按推荐批准”）

| 编号 | 决定 |
|---|---|
| D1 | 原生消息 + `AUV.BrowserHost.exe` + 命名管道 |
| D2 | 独立的小程序 `AUV.BrowserHost.exe` |
| D3 | 同时支持 Chrome 与 Edge |
| D4 | 首发用开发者模式加载；上架商店以后再议 |
| D5 | 为 Windows 新生成 key，manifest 只放公钥，私钥不保存 |
| D6 | 文件放在 `%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\` |
| D7 | 自动：有普通窗口用后台标签页，否则用最小化小窗口 |
| D8 | 沿用 Windows 规则：间隔 + 2 分钟后隐藏 |
| D9 | 允许 AUV 先询问再打开浏览器；自动刷新一轮只问一次，可勾选不再询问 |
| D10 | 伴侣沉默时只提示，不替用户重启浏览器 |
| D11 | 不申请 `background` 权限 |
| D12 | Claude 有读数时出现在桌面浮窗列表，外观不变 |
| D13 | 扩展图标点击后让 AUV 立即同步一次 |
| D14 | 版本号未给推荐值，打包前再向用户确认；实现期间不改版本号 |
| D15 | 默认关闭，用户开启并完成设置后才读取 |
| D16 | 共享 JS 用固定副本 + 哈希比对测试 |
| D17 | JS 测试用 WebView2 运行 |
| D18 | Claude Code 本地估算、Antigravity 不在本项 |
