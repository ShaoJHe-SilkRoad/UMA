<p align="center"><img src="Assets/AppIcon.png" width="128" alt="AUV app icon"></p>

# AUV — Agent Usage Viewer

**See your AI usage, set up your coding team, and manage a virtual development disk — in one Mac app.**

[Download AUV 0.15.1](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip) · [Installation guide](docs/INSTALLATION.md) · [中文](#中文)

Requires **macOS 14 or later and an Apple silicon Mac**. Developer signed and Apple notarized.

## What you can do

| Area | What it does |
| --- | --- |
| **AUV** | View remaining AI usage, account information and local usage estimates. Keep an eye on them from the main window, menu bar or desktop assistant. |
| **ThreadOS** | Choose a model and thinking level for Leader, Coder Cluster, Reviewer Cluster and QA. Copy one instruction and paste it into your Leader conversation. |
| **Sectorium** | Create or use an APFS virtual development disk on a drive, start or stop it, and request safe ejection of an external drive. **Early-stage feature; see the safety note below.** |

![AUV usage overview with sample data](docs/images/0.15.1/auv-en.png)

The app supports English and Chinese, light and dark appearance, and keyboard navigation. Unavailable usage figures stay unknown; local cost estimates are not subscription bills.

## Install in three steps

1. [Download the ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip) and double-click it in Finder.
2. Move **`UMA.app`** to **Applications** on your Mac. It opens as **AUV**; the filename is kept for compatibility with earlier versions.
3. Open it from Applications and follow the normal macOS first-open prompt.

Upgrading? Quit the old app first, keep a backup of it, and replace it in the same location. Your saved settings are retained. [Full installation and troubleshooting guide](docs/INSTALLATION.md).

## ThreadOS: choose, copy, paste

![ThreadOS team settings with sample data](docs/images/0.15.1/threados-en.png)

Set each role separately, check the instruction preview, then click **Generate and Copy**. Paste it into the Leader responsible for your development folder. That Leader applies the choices to its own team; AUV does not select a project or send messages for you.

Thinking levels include Low, Medium, High and Ex High. **Ultra** is available for supported models; GPT-6 Luna does not offer it in this release. The receiving client must also support your choice. If a manual model change is needed for the Leader itself, it should tell you exactly what to select. Copying an instruction does not change a model by itself.

[ThreadOS guide](https://shaotinghe.com/threados/)

## Sectorium: a development disk on your drive

Sectorium uses a file-based APFS disk image. It does **not** repartition or format the physical drive. You can use an existing image, including DEV_APFS, rather than create another one. **Stop** closes the virtual disk; **Safe Eject** prepares the entire external drive for unplugging.

> **Sectorium is in early development.** Back up important data and try it with noncritical data first. Interrupted operations or unexpected disconnection can cause data loss. Do not unplug until the complete safe-eject operation succeeds.

This release has not been tested through live disk creation, mounting, ejection or automatic mounting on hardware. Treat those functions as experimental. Sectorium reads device status and I/O statistics, not your project file contents.

[Sectorium setup and safety guide](https://shaotinghe.com/sectorium/)

## Release and support

Current release: **0.15.1**, build **2026101002**, for Apple silicon. Intel Macs are not supported by this download. AUV was previously called UMA.

Ultra command generation was tested; live Ultra execution was not. Some window and keyboard checks remain incomplete. [Detailed release checks and known limits](https://github.com/ShaoJHe-SilkRoad/UMA/blob/v0.15.1/docs/releases/0.15.1.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues).

---

## 中文

**一个 Mac 应用，查看 AI 用量、设置开发团队、管理虚拟开发盘。**

[下载 AUV 0.15.1](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip) · [安装指南](docs/INSTALLATION.md#中文安装指南)

需要 **macOS 14 或更新版本，以及 Apple silicon Mac（M 系列芯片）**。应用已签名并通过 Apple 公证。

### 三个功能区

| 功能区 | 能做什么 |
| --- | --- |
| **AUV** | 查看 AI 剩余额度、账户信息和本地用量估算，也可以从菜单栏或桌面助手查看。 |
| **ThreadOS · 线程工** | 分别选择 Leader、Coder Cluster、Reviewer Cluster 和 QA 的模型与思考档位，复制一条指令，粘贴给 Leader 执行。 |
| **Sectorium · 分区工** | 在硬盘上创建或使用 APFS 虚拟开发盘，启动、停止开发盘，以及请求安全弹出外接硬盘。**仍处于早期开发阶段。** |

支持中英文、明暗主题和键盘操作。取不到的用量显示为未知；本地费用估算不等于订阅账单。

### 下载与升级

1. [下载 ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip)，在 Finder 中双击解压。
2. 将 **`UMA.app`** 移入 Mac 内置盘的**“应用程序”**文件夹。打开后显示为 **AUV**，文件名沿用旧名以兼容已有安装。
3. 从“应用程序”打开，按 macOS 的正常首次启动提示操作。

升级时先正常退出旧版，保留旧应用备份，再替换原位置的应用。已保存的设置会保留。[完整安装与排错步骤](docs/INSTALLATION.md#中文安装指南)。

### 线程工：选择、复制、粘贴

分别设置四个角色，查看指令预览，点击**“生成并复制指令”**，粘贴给负责开发目录的 Leader。接收指令的 Leader 只处理自己的团队，AUV 不选择项目，也不代发消息。

思考档位有 Low、Medium、High 和 Ex High，部分模型还支持 **Ultra**；本版 GPT-6 Luna 不提供 Ultra。接收端也必须支持所选组合。Leader 自身若需要手动切换模型，应说明具体操作。复制成功不代表模型已经切换。

[线程工使用指南](https://shaotinghe.com/threados/)

### 分区工：在硬盘上使用开发盘

分区工创建的是文件型 APFS 虚拟盘，**不会重新分区或格式化物理硬盘**。已有 DEV_APFS 等镜像可以直接接纳，无需重建。**“停止”**只关闭虚拟盘；准备拔出整个外接硬盘时，应使用**“安全弹出”**。

> **分区工仍处于早期开发阶段。** 请先备份重要数据，优先使用非关键数据试用。操作中断或意外断连可能导致数据损失；完整安全弹出成功前不要拔盘。

本版尚未完成真实设备上的创建、挂载、弹出和自动挂载测试，这些功能应作为试验功能使用。分区工读取设备状态和 I/O 统计，不扫描项目文件内容。

[分区工设置与安全指南](https://shaotinghe.com/sectorium/)

### 版本与帮助

当前版本 **0.15.1**，构建号 **2026101002**，适用于 Apple silicon；此下载包不支持 Intel Mac。AUV 原名 UMA。

Ultra 指令生成已测试，真实 Ultra 执行未测试；部分窗口与键盘检查尚未完成。[详细版本记录与已知限制](https://github.com/ShaoJHe-SilkRoad/UMA/blob/v0.15.1/docs/releases/0.15.1.md) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)。
