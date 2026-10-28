<p align="center"><img src="Assets/AppIcon.png" width="128" alt="AUV app icon"></p>

# AUV — Agent Usage Viewer

**Check your AI allowance, prepare coding-team instructions, and manage a development volume from one app.**

| Platform | Download | Requirements |
| --- | --- | --- |
| macOS | [Download for Mac — 0.18.0](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip) | macOS 14+ · Apple silicon and Intel · Universal app · signed and notarized |
| Windows | [Download for Windows — 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip) | Windows 11 · x64 · portable ZIP · **unsigned** |

[Install or upgrade](docs/INSTALLATION.md) · [Mac release notes](docs/releases/AUV_Mac_0.18.0.md) · [Mac compatibility](docs/MAC_COMPATIBILITY.md) · [中文](#中文)

## Three workspaces

| Workspace | What you can do |
| --- | --- |
| **AUV** | See the account allowance your connected agents provide, along with clearly labelled local estimates. Check it from the main window, menu bar or desktop assistant. |
| **ThreadOS** | Choose models and thinking levels for your coding team. Copy the generated instruction into your Leader conversation to apply it. |
| **Sectorium** | On Mac, create or register a file-based APFS development volume, load it for work, unload it, or safely disconnect its external drive. |

Supports English and Chinese, light and dark appearance, and keyboard navigation. Available data depends on the connected provider and account. AUV shows unknown values honestly; a local cost estimate is not a subscription bill.

## Get started on Mac

1. [Download the Universal ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip) and double-click it to unpack.
2. Move **`UMA.app`** to **Applications** on your Mac's internal disk. It opens as **AUV**; the filename is retained for existing installations.
3. Open AUV. To see Codex allowance, install and sign in to the official Codex app with your ChatGPT account, then allow the local connection in AUV and choose **Scan for Agents**, then **Refresh All**.

Upgrading? Quit the old AUV before replacing it. Keep your saved settings. Version **0.18.0**, build **2026102801**, is Developer ID signed and Apple notarized.

The package includes Apple silicon and Intel versions. Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. Physical Intel Macs and macOS 14/15 have not yet been tested. [Compatibility details](docs/MAC_COMPATIBILITY.md).

### Codex usage

AUV reads the allowance reported by the Codex app on this Mac. It does not count messages on the ChatGPT website. Version 0.17.2 improves compatibility with Codex versions that return fewer connection details. An unavailable optional token statistic does not hide an otherwise valid account allowance.

Already signed in but no usage appears? Follow [First connection and troubleshooting](docs/FIRST_INSTALL_TROUBLESHOOTING.md). Each provider still needs its own supported account and setup.

### Claude usage

Claude quota bars turn red when little remains and green when plenty does. Claude does not report which plan you are on and AUV does not guess, so set **Claude plan** to Pro or Max in the Claude agent's settings; until then the bars stay neutral grey. Turn on **Token Cost Estimate** in the Claude agent's settings and, when this Mac has local Claude Code activity, the Claude page also shows an API-equivalent cost estimate for the last seven days and lifetime, calculated here from token totals and public list prices. It is an estimate, not a subscription bill, and no billing or payment information is read.

### ThreadOS: choose, copy, apply

Set each role's model and thinking level, review the instruction, then choose **Generate and Copy**. Paste it into the Leader responsible for your project. AUV does not dispatch work or change another app's settings by itself.

[ThreadOS guide](https://shaotinghe.com/threados/)

### Sectorium: Load, Unload, Disconnect

A development volume is an APFS disk image stored on your drive. Creating one does not repartition or format the physical drive. You can register an existing image instead.

| Action | What happens |
| --- | --- |
| **Load** | Mount the development volume so you can work in it. |
| **Unload** | Unmount the development volume; keep the parent drive connected. You can load it again. |
| **Disconnect** | Safely eject the entire external drive so you can unplug it. |

Sectorium remembers registered volumes across page changes. It listens for macOS disk changes and checks consistency every five minutes. If an app is holding the drive open, resolve that occupancy before retrying; wait for successful disconnection before unplugging.

The basic Load → Unload → Load and Disconnect cycle has been confirmed on the tested external-drive setup. This does not establish compatibility with every drive or filesystem. Keep a backup of important data. [Sectorium guide](https://shaotinghe.com/sectorium/).

## Windows 0.16.3

Extract the entire ZIP and run **AUV.exe**; verify **0.16.3** in AUV.exe → Properties → Details → Product version. The .NET desktop runtime is included. WorkBuddy's optional connection needs WebView2 Runtime. Enable the floating Wizard in Settings; click the AUV tray icon for usage. **Ctrl+Shift+Q** quits completely. Preserve **%LOCALAPPDATA%\AUV.Windows.UI.Preview** during upgrades. See the [Windows guide](docs/INSTALLATION.md#windows-installation-guide) for unsigned-build verification and provider limits.


Windows build **20261011.1** remains a separate release. Codex read-only usage is available; WorkBuddy Credit sync is experimental and needs WebView2 Runtime. Claude and Antigravity live connections are unavailable. ThreadOS generates and copies instructions; receiving-client application and live Ultra execution remain untested. **Sectorium is UI only on Windows; storage operations are disabled.**

[Windows release notes](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3) · [Windows source and build instructions](windows/README.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**查看 AI 额度、生成开发团队指令，在 Mac 上管理开发卷。**

| 平台 | 下载 | 要求 |
| --- | --- | --- |
| macOS | [下载 Mac 版 · 0.18.0](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip) | macOS 14 及以上 · Apple silicon 和 Intel · 通用包 · 已签名并通过公证 |
| Windows | [下载 Windows 版 · 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip) | Windows 11 · x64 · 便携 ZIP · **未签名** |

[安装与升级](docs/INSTALLATION.md#中文安装指南) · [Mac 更新说明](docs/releases/AUV_Mac_0.18.0.md#中文) · [Mac 兼容性](docs/MAC_COMPATIBILITY.md#中文)

### 三个功能区

| 功能区 | 能做什么 |
| --- | --- |
| **AUV** | 查看已连接智能体提供的账户额度，以及明确标注的本地估算。支持主窗口、菜单栏和桌面助手。 |
| **ThreadOS · 线程工** | 为开发团队选择模型与思考档位，生成一条指令，复制给项目的 Leader 执行。 |
| **Sectorium · 分区工** | 在 Mac 上创建或登记文件型 APFS 开发卷，装载、卸载开发卷，或安全断开整个外接硬盘。 |

支持中英文、明暗主题和键盘操作。可显示的数据取决于智能体及账户；取不到的数值保持未知，本地费用估算不等于订阅账单。

### Mac 快速开始

1. [下载通用 ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip)，双击解压。
2. 将 **`UMA.app`** 移入 Mac 内置盘的**“应用程序”**文件夹。打开后显示为 **AUV**，文件名保留以兼容已有安装。
3. 打开 AUV。查看 Codex 额度时，先安装官方 Codex 并用 ChatGPT 账户登录，再在 AUV 中允许本机连接，点击**“扫描智能体”**，再点**“全部刷新”**。

升级前先正常退出旧版，再替换应用，保留已有设置。当前 Mac 版本为 **0.18.0**，构建号 **2026102801**，已完成 Developer ID 签名和 Apple 公证。

通用包包含 Apple silicon 与 Intel 版本。包验证在 macOS 27.2 的 Apple silicon Mac 上进行，并通过 Rosetta 2 运行 Intel 程序。尚未在 Intel 实机或 macOS 14/15 上测试。[兼容性详情](docs/MAC_COMPATIBILITY.md#中文)。

### Codex 用量

AUV 显示本机 Codex 返回的账户额度，不统计 ChatGPT 网页消息数。0.17.2 改善了不同 Codex 版本的连接兼容性；缺少可选 token 统计时，已取得的账户额度仍能显示。

已经登录却看不到额度时，请查看[首次连接与排错](docs/FIRST_INSTALL_TROUBLESHOOTING.md#中文)。各智能体仍需自己的受支持账户与连接设置。

### Claude 用量

Claude 额度条在余量偏低时变红、充足时变绿。Claude 不报告订阅方案，AUV 也不猜测，请在 Claude 智能体设置中将 **Claude 方案**设为 Pro 或 Max；未设置前保持中性灰色。在 Claude 智能体设置中打开 **Token 费用估算**，且本机存在本地 Claude Code 活动时，Claude 页面还会显示近 7 天与累计的 API 等效费用估算，依据令牌总量和公开价目表在本机计算。该数值属于估算而非订阅账单，也不会读取任何账单或支付信息。

### 线程工：选择、复制、执行

分别设置各角色的模型与思考档位，查看指令后点击**“生成并复制”**，粘贴给负责项目的 Leader。AUV 不会自行派发任务或修改其他应用的设置。

[线程工指南](https://shaotinghe.com/threados/)

### 分区工：装载、卸载、断开

开发卷是存放在硬盘上的 APFS 镜像文件，创建时不会重新分区或格式化物理硬盘。已有镜像可以直接登记使用。

| 操作 | 含义 |
| --- | --- |
| **Load · 装载** | 挂载开发卷，开始工作。 |
| **Unload · 卸载** | 卸载开发卷，母盘保持连接，之后可以再次装载。 |
| **Disconnect · 断开** | 安全弹出整个外接硬盘，完成后可以拔线。 |

切换页面不会丢失已登记的开发卷。分区工使用 macOS 磁盘变化通知，并每五分钟检查状态一致性。若应用仍占用硬盘，先处理占用再重试；断开成功前请保持硬盘连接。

基本的装载→卸载→再次装载及断开流程，已在本次外接硬盘环境中确认可用。这不代表所有硬盘和文件系统都经过测试。请保留重要数据备份。[分区工指南](https://shaotinghe.com/sectorium/)。

### Windows 0.16.3

构建号 **20261011.1**。全部解压 ZIP 后运行 **AUV.exe**，在 AUV.exe 文件属性 → 详细信息确认 0.16.3。已包含 .NET 桌面运行时；可选 WorkBuddy 连接需 WebView2 Runtime。设置中启用独立桌面浮窗，托盘图标展开用量，**Ctrl+Shift+Q** 完全退出。升级请保留 **%LOCALAPPDATA%\AUV.Windows.UI.Preview**。

Codex 只读用量已接入；WorkBuddy 同步为试验功能；Claude/Antigravity 实时连接不可用。线程工可生成和复制，接收端与真实 Ultra 执行未验证。分区工**仅为界面，存储后台未实现，磁盘操作禁用**。详见[Windows 安装指南](docs/INSTALLATION.md#windows-中文安装指南)。


[Windows 更新说明](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
