# AUV 安装、升级与首次使用 / Installation, upgrade and first use

适用于 **AUV 0.15.1 / Build 2026101002**。原名 UMA；下载包中的应用仍名为 `UMA.app`，打开后显示 **AUV**。ThreadOS（线程工）与 Sectorium（分区工）包含在同一个应用中，无需分别下载三个 App。

For **AUV 0.15.1 / build 2026101002**, formerly UMA. The application inside the download is still named `UMA.app`; it displays **AUV** when opened. ThreadOS and Sectorium are included in the same application.

[中文步骤](#中文安装指南) · [English steps](#english-installation-guide) · [发布页 / Release](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.15.1) · [ThreadOS](https://shaotinghe.com/threados/) · [Sectorium](https://shaotinghe.com/sectorium/)

## 中文安装指南

### 1. 系统要求与正确下载

- **macOS 14 或更新版本，Apple silicon Mac（M 系列芯片）。** 在苹果菜单 →“关于本机”确认。本次没有 Intel 下载包。
- 下载 [AUV-0.15.1-build2026101002.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip)，以及发布页的 `HASHES.txt`。不选 GitHub 自动生成的 “Source code” 压缩包；那是源码，不能直接安装。
- 本版使用 **Developer ID Application: SHAOTING HE (C6TUZVJ6SJ)** 签名，Apple 公证已接受，公证票据已附加。该记录针对正式发行包，不代表磁盘操作已在你的设备验收。

下载 ZIP 的 SHA-256 应为：

```text
598bd61b8a439dde426b943bee3f84e57ad46bba96b94747405ae687825d505e
```

可选校验：如果文件保留原名并位于“下载”文件夹，在终端执行下列只读命令，比对输出开头的 64 位值与上述值及 `HASHES.txt`。校验不相同就停止安装并重新下载。

```sh
shasum -a 256 ~/Downloads/AUV-0.15.1-build2026101002.zip
```

### 2. 首次安装

1. 在 Finder 双击 ZIP，解压出 `UMA.app`。无需打开“显示包内容”，也无需运行源码中的脚本。
2. 将 `UMA.app` 拖入内置磁盘的“应用程序”文件夹（`/Applications`），或个人“应用程序”文件夹（`~/Applications`）。选择一个位置并持续使用；如果系统要求批准该位置的文件复制，按正常系统流程完成。
3. 从刚才的安装位置打开应用，不要继续从“下载”或临时解压目录启动。Sectorium 的必要控制链不能依赖将来要弹出的外接硬盘。
4. 若 macOS 显示正常的首次打开确认，确认来源和版本后按系统界面操作。若报告应用损坏、来源无法验证或被安全策略阻止，先重新下载并核对哈希；不要关闭 Gatekeeper、移除隔离属性或修改系统安全设置来强行启动。
5. 在 **AUV → About AUV（关于 AUV）** 核对版本 **0.15.1** 和构建 **2026101002**。若只显示版本，可在 Finder 选中安装位置的 `UMA.app` →“显示简介”复核；详细构建身份也记录在发布页的 `RELEASE-MANIFEST.json`。显示旧版时，先正常退出旧副本，再从正确安装位置打开。

### 3. 从 UMA / 较早 AUV 升级

1. 保存当前工作，使用应用菜单正常退出旧 UMA/AUV；关闭窗口不一定退出菜单栏进程。
2. 在内置磁盘保留旧 `UMA.app` 副本，例如单独的备份文件夹，不覆盖唯一的旧版备份。
3. 将新解压的 `UMA.app` 复制到**原来使用的同一个安装位置**，在 Finder 的替换提示中正常完成替换。
4. 打开新副本，检查版本、语言、主题、既有模型选择和所需账户显示。原 bundle ID `com.silkrd.uma` 及偏好身份保留；无需删除偏好、历史、缓存或重新建立所有设置。

应用替换不会自动证明 Sectorium 工具、服务或磁盘就绪；也不是对旧存储组件的全面升级承诺。如果正常退出或替换被系统拒绝，处理该具体提示，不要强杀进程或删除无关文件。

### 4. 首次使用三个入口

| 入口 | 首次操作 | 完成标志 |
| --- | --- | --- |
| AUV | 查看所需代理/账户；使用它原有的设置入口完成必要连接 | 数据可读取；未知或未连接仍如实显示，不把未知当作零 |
| ThreadOS / 线程工 | 为四个角色选择模型和思考档位，预览后复制，粘贴给负责开发目录的 Leader | 指令已复制仅证明复制；由接收端分别报告请求、提交、经验证生效值 |
| Sectorium / 分区工 | 先核对物理硬盘、开发盘关系及组件状态，再选择创建、接纳或启动 | 组件、服务、磁盘各有独立状态；只有核验就绪才可开始开发 |

ThreadOS 界面无需额外安装一个 App。实际执行模型设置仍需要受支持的 Codex/Leader 环境和有效团队绑定；AUV 不会自动创建团队或发送指令。既有 provider/浏览器连接沿用各自设置，不因安装 AUV 自动获得权限。详细操作见 [ThreadOS 指南](https://shaotinghe.com/threados/)。

### 5. Sectorium 工具与开发盘设置

**分区工仍处于早期开发阶段。先独立备份重要数据，优先用非关键测试数据评估。以下是操作说明，不是对当前版本真实安装、自动挂载或安全弹出已验收的声明。**

1. 打开顶部 **Sectorium / 分区工**，选择目标物理硬盘，检查容量、宿主卷及开发镜像关系。内置系统盘和外接盘用途不同；不要仅凭 `diskN` 编号或名称认定目标。
2. 打开分区工页面的 **Settings / 设置**，查看“组件”。缺少时使用 **Install HESectorium / 安装 HESectorium**；只有在明确兼容的已有组件需要修复时才使用修复。若显示冲突、身份无效或恢复失败，展开诊断并停止后续存储操作；不要删除旧 helper、服务或恢复材料来清除提示。
3. 安装工具与创建开发盘是两件事。已有开发镜像时，使用 **Adopt existing disk / 接纳已有开发盘**，选择该镜像并等待身份、镜像与设备关系核验；不要为“安装”重建或覆盖原有 `DEV_APFS`。
4. 没有开发镜像时，使用 **Create development disk / 创建开发盘**，填写名称、逻辑容量（默认 100 GiB），选择是否区分大小写及是否加密，再选择目标硬盘上的保存位置。它创建 APFS sparsebundle 文件，不重分区或格式化整块硬盘。逻辑上限不代表预留物理容量；按界面处理可用空间不足或同名冲突。加密密码妥善保管，丢失可能无法解锁；不要写入诊断或公开报告。
5. 创建界面的“创建后启动”默认关闭，可自行选择。已有或新建镜像未启动时，使用 **Start / 启动**；加密镜像按界面解锁。等待磁盘状态明确为可开发/就绪，不能把“已连接”“组件已安装”或命令退出成功视为就绪。
6. 自动挂载按需设置。**偏好已启用、plist 已安装、服务实际已加载和磁盘就绪分别判断。** 当前组件安装及偏好保存不会自动加载或重启 launchd 服务；未加载/未知时，自动挂载尚未确认，不要假定下次插盘必然生效。本指南不要求手动执行服务部署命令；先按界面手动启动，并保留具体诊断以处理配置。
7. 日常离开时，**Stop / 停止**只停止虚拟开发盘；要拔出外接硬盘，使用 **Safe eject / 安全弹出整块硬盘**。先保存工作并关闭已知写入程序，核对确认窗口的目标和受影响卷，再执行。只有完整弹出确认成功才拔线。忙碌、未知或部分完成时不能拔线；不强制卸载、不杀进程、不删除锁来重试。内置系统硬盘不使用物理弹出。

工具安装会涉及用户目录中的控制器、兼容 helper、配置及 LaunchAgent 文件；不应为每个入口部署第二套服务。未知旧安装不能盲目接纳。更多状态、隐私和失败说明见 [Sectorium 指南](https://shaotinghe.com/sectorium/)。

### 6. 常见问题与回退

| 问题 | 处理 |
| --- | --- |
| 解压后仍叫 UMA.app | 正常兼容名称，打开后为 AUV；不要下载另一个所谓 AUV 模块包 |
| 显示旧版本或出现两个应用 | 正常退出旧副本，只从选定安装目录启动；用“关于 AUV”核对，不靠窗口外观判断 |
| “损坏”、无法验证、哈希不符 | 停止，重新下载正式 ZIP 并复核；保留准确系统提示，不绕过安全检查 |
| Intel Mac 或 macOS 过旧 | 当前发行包不支持；不要把源码压缩包当作兼容安装包 |
| 用量或模型能力显示未知 | 检查对应 provider/原生客户端的连接与能力；应用安装和复制指令并不证明后端已连接或模型已生效 |
| 分区工组件安装失败/冲突 | 查看失败步骤和恢复信息，保留现有数据与组件；不反复修复、删除记录或强制挂载 |
| 自动化偏好开启但服务未知/未加载 | 不等于自动挂载已运行；分别核对组件、服务与就绪状态，暂用已支持的手动入口 |
| 弹出失败或部分完成 | 保持连接，处理报告的占用/依赖，刷新后仅使用明确提供的恢复动作；不能显示“可拔线” |

需要回退应用时：正常退出新版，把保留的旧 App 放回原安装位置，再打开核对。**应用回退不会自动回退 Sectorium helper、服务配置、镜像或数据变更**；不要通过删除用户数据或重建镜像回退。提交问题时提供 macOS/芯片、版本/build、失败步骤与必要诊断，先移除路径、账户和项目等隐私信息。

本说明补齐安装操作；没有新增实机测试结论。0.15.1 的已测范围、已知基线测试失败、待补原生截图以及未执行的真实磁盘/服务场景，继续以 [发布说明](releases/0.15.1.md) 为准。

## English installation guide

### 1. Requirements and downloads

- **macOS 14 or later, Apple silicon Mac (M-series).** Check Apple menu → About This Mac. There is no Intel binary in this release.
- Download [AUV-0.15.1-build2026101002.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip) and `HASHES.txt` from the release. GitHub’s automatically generated “Source code” archives are not installable applications.
- The distribution is signed by **Developer ID Application: SHAOTING HE (C6TUZVJ6SJ)**, accepted by Apple notarization and stapled. This describes the released archive, not storage validation on your computer.

Expected archive SHA-256:

```text
598bd61b8a439dde426b943bee3f84e57ad46bba96b94747405ae687825d505e
```

Optional verification, when the original filename is in Downloads: run the following read-only command in Terminal and compare its first 64 characters with this value and `HASHES.txt`. Stop and download again if they differ.

```sh
shasum -a 256 ~/Downloads/AUV-0.15.1-build2026101002.zip
```

### 2. First installation

1. Double-click the ZIP in Finder to extract `UMA.app`. Do not open its package contents or run source/build scripts to install it.
2. Move it to the internal disk’s Applications folder (`/Applications`) or your personal Applications folder (`~/Applications`). Choose one location and keep using it. Complete any normal system approval needed for copying there.
3. Open the installed copy, rather than the copy in Downloads or a temporary folder. Required Sectorium controls must not depend on an external drive you intend to eject.
4. Respond to a normal macOS first-open confirmation after checking the source. If macOS reports damage, an unverifiable application or a security-policy block, download again and verify the hash. Do not disable Gatekeeper, remove quarantine attributes or change security settings to force it open.
5. Open **AUV → About AUV** and check **0.15.1**, build **2026101002**. If only the version is shown, check the installed `UMA.app` with Finder → Get Info; the detailed build identity is also in the release’s `RELEASE-MANIFEST.json`. If an older version appears, quit that copy normally and open the intended installation.

### 3. Upgrade from UMA or an older AUV

1. Save your work and quit the old application through its menu. Closing a window may leave its menu-bar process running.
2. Retain the old `UMA.app` in a separate backup folder on the internal disk. Do not overwrite your only old-version backup.
3. Copy the new `UMA.app` into **the same installation location you were using**, accepting Finder’s normal replacement prompt.
4. Open it and check the version, language, appearance, saved model choices and required account displays. Bundle ID `com.silkrd.uma` and preference identities are retained. Do not erase preferences, history or caches to upgrade.

Replacing the application does not establish that Sectorium helpers, services or disks are ready, nor promise a complete upgrade of legacy storage components. Resolve a specific system refusal rather than force-killing processes or deleting unrelated files.

### 4. First use

| Area | First action | What completion means |
| --- | --- | --- |
| AUV | Select the required agent/account and configure its existing connection settings | Readable data; disconnected/unknown values stay explicit |
| ThreadOS | Select models/thinking for four roles, preview and copy, then paste to the Leader responsible for the development root | Copying is not activation; the receiver reports requested, submitted and verified effective values separately |
| Sectorium | Check the physical-drive/image relationship and components before creating, adopting or starting | Components, service observation and verified storage readiness are separate |

ThreadOS needs no separate application installation. Execution still needs a supported Codex/Leader environment and valid team bindings; AUV does not create teams or send commands automatically. Existing provider/browser connections retain their own setup and permission requirements. See the [ThreadOS guide](https://shaotinghe.com/threados/).

### 5. Sectorium components and development disks

**Sectorium is in early development. Keep an independent backup and evaluate with noncritical data first. These instructions are not a claim that real installation, automation or safe eject has been validated for this release.**

1. Open **Sectorium**, select the physical drive, and review its capacity, host volumes and image relationship. Do not identify a target solely by a name or `diskN` number.
2. Open its **Settings** and inspect Components. Use **Install HESectorium** if missing, or repair only a recognized compatible installation that needs repair. Stop on conflicts, invalid identity or failed recovery and inspect diagnostics; do not delete helpers, services or recovery material to dismiss an error.
3. Tool installation is separate from creating a disk. For an existing image, use **Adopt existing disk**, select the image, and wait for identity/device-chain validation. Do not recreate or overwrite an existing `DEV_APFS` merely to “install” it.
4. For a new image, use **Create development disk**. Choose its name, logical capacity (default 100 GiB), case sensitivity and optional encryption, then a location on the selected drive. This creates an APFS sparsebundle file, not physical repartitioning or formatting. Logical capacity does not reserve that much space. Resolve space or name conflicts through the interface. Keep an encryption password safe; losing it can prevent unlocking. Do not put it in logs or reports.
5. “Start after creation” defaults off. Use **Start** for a stopped image; unlock encrypted images when prompted. Wait for verified development readiness. A connected drive, installed components or successful command exit alone is insufficient.
6. Configure automation only if wanted. **Enabled preference, installed plist, observed loaded service and disk readiness are different states.** Component installation and preference saving do not load/restart launchd. If service state is not loaded or unknown, automatic mounting is unconfirmed. This guide does not ask you to run service-deployment commands; use the supported manual start flow and retain specific diagnostics for configuration issues.
7. **Stop** affects the virtual development disk. To unplug external hardware, use **Safe eject / whole-drive eject**. Save work, close known writers, review the target and affected volumes in the confirmation, then proceed. Unplug only after the full eject succeeds. Busy, unknown or partial completion is not safe to unplug. Do not force-unmount, kill processes or delete locks. Internal system hardware is not physically ejected through this workflow.

Component installation concerns a user-local controller, compatibility helpers, configuration and LaunchAgent files. Do not deploy a competing service for each entry point or blindly adopt an unknown legacy installation. See [Sectorium](https://shaotinghe.com/sectorium/) for state, privacy and recovery details.

### 6. Troubleshooting and rollback

| Issue | Action |
| --- | --- |
| The extracted app is named UMA.app | Expected compatibility name; it displays AUV. No separate AUV module download is needed |
| Old version or duplicate application | Quit the old copy and open only the chosen installation; verify About AUV rather than judging its appearance |
| Damage, unverifiable app or checksum mismatch | Stop, download the official ZIP again and verify it; retain the exact system message instead of bypassing security |
| Intel Mac or older macOS | This binary is unsupported; a source archive is not a compatible installer |
| Usage/model capability is unknown | Check that provider/native client’s connection and capabilities; installing or copying does not prove backend activation |
| Sectorium install conflict/failure | Inspect the failed step and recovery record; preserve existing data/components rather than repeatedly repairing or forcing mounting |
| Automation enabled but service unknown/not loaded | Automatic mounting is unconfirmed; check components, service and readiness separately and use supported manual controls |
| Eject failed or partly completed | Keep the drive connected, resolve the reported occupancy/dependency, refresh and use only the offered recovery action |

To roll back the application, quit normally, return your backed-up App to the same installation location, then open and verify it. **Application rollback does not automatically revert Sectorium helpers, service configuration, images or data changes.** Do not erase user data or recreate images as a rollback. When reporting a problem, include macOS/chip, version/build, the failed step and necessary diagnostics after removing private paths, account and project information.

This guide adds instructions, not new runtime evidence. The release’s tested scope, known baseline test failures, pending native screenshots and unexecuted live storage/service scenarios remain documented in the [release notes](releases/0.15.1.md).
