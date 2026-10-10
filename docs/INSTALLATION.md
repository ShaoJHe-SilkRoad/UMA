# Install AUV / 安装 AUV

[English](#english-installation-guide) · [中文](#中文安装指南) · [Download / 下载](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip)

## English installation guide

### Before you start

You need **macOS 14 or later and an Apple silicon Mac (M-series chip)**. Check Apple menu → About This Mac if you are unsure. This release does not include an Intel version.

AUV 0.15.1 includes ThreadOS and Sectorium. You only need one app download.

### Install

1. [Download AUV-0.15.1-build2026101002.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip). Choose this application ZIP, not GitHub’s “Source code” download.
2. Double-click the ZIP in Finder. It extracts **`UMA.app`** — the app opens as **AUV**, but keeps its old filename for compatibility.
3. Drag it into **Applications** on your Mac’s internal disk. Your personal `~/Applications` folder also works. Keep the app on the internal disk if you plan to eject an external development drive.
4. Open the installed copy and follow the normal macOS first-open prompt. This release is Developer ID signed and Apple notarized.
5. Open **AUV → About AUV** and check **0.15.1**. The build number is **2026101002**; Finder → Get Info can also show the installed app’s version details.

### Upgrade from UMA or an older AUV

Quit the old app through its menu — closing the window may leave it running in the menu bar. Keep a copy of the old app as a backup, then replace it with the new `UMA.app` in the same installation folder. Open the new copy.

Your saved settings are retained. You do not need to clear preferences, history or caches. Installing AUV does not automatically install or activate Sectorium’s storage tools.

### What to do after opening

- **AUV:** choose an agent to see the usage information available for its account.
- **ThreadOS:** choose each role’s model and thinking level, copy the instruction, and paste it into your Leader conversation. [ThreadOS guide](https://shaotinghe.com/threados/).
- **Sectorium:** follow the [setup guide](https://shaotinghe.com/sectorium/) before using storage actions. It is still experimental: back up important data and start with noncritical data. Do not unplug a drive until its complete safe-eject operation succeeds.

### If something goes wrong

- **An older version opens:** quit it, then open the copy in your chosen Applications folder rather than Downloads.
- **macOS blocks the app or says it is damaged:** download it again from the official release and check the file below. Do not disable system security or force it open. If the problem remains, [report the message](https://github.com/ShaoJHe-SilkRoad/UMA/issues).
- **You need to go back:** quit AUV and restore your backed-up app to the same folder. This restores the app only; it does not undo changes to Sectorium tools, services or disk data.

### Optional: verify your download

For the ZIP saved with its original name in Downloads, run:

```sh
shasum -a 256 ~/Downloads/AUV-0.15.1-build2026101002.zip
```

The first value should match:

```text
598bd61b8a439dde426b943bee3f84e57ad46bba96b94747405ae687825d505e
```

If it differs, do not install that file. Download it again. The [release page](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.15.1) also provides `HASHES.txt` and the signing record. The signing identity is **SHAOTING HE (C6TUZVJ6SJ)**.

## 中文安装指南

### 安装前

需要 **macOS 14 或更新版本，以及 Apple silicon Mac（M 系列芯片）**。不确定时，可在苹果菜单 →“关于本机”查看。本版不提供 Intel 版本。

AUV 0.15.1 已包含线程工和分区工，只需下载一个应用。

### 安装

1. [下载 AUV-0.15.1-build2026101002.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.15.1/AUV-0.15.1-build2026101002.zip)。请选择这个应用 ZIP，不要选择 GitHub 的“Source code”源码包。
2. 在 Finder 中双击解压，得到 **`UMA.app`**。打开后显示为 **AUV**，文件名沿用旧名以兼容已有安装。
3. 将它拖入 Mac 内置盘的**“应用程序”**文件夹，也可以使用个人 `~/Applications` 文件夹。如果以后需要弹出外接开发硬盘，应用本身请放在内置盘。
4. 打开安装后的应用，按 macOS 正常首次启动提示操作。本版已使用 Developer ID 签名，并通过 Apple 公证。
5. 在 **AUV → 关于 AUV** 中确认版本为 **0.15.1**。构建号为 **2026101002**；Finder →“显示简介”也可查看已安装应用的版本信息。

### 从 UMA 或旧版 AUV 升级

先通过菜单正常退出旧应用；只关窗口可能仍会在菜单栏运行。保留一份旧应用备份，再用新的 `UMA.app` 替换原安装文件夹中的应用，然后打开新版。

已保存的设置会保留，无需清空偏好、历史或缓存。安装 AUV 不会自动安装或启用分区工的存储工具。

### 打开后做什么

- **AUV：**选择代理，查看其账户能够提供的用量信息。
- **线程工：**分别选择角色的模型与思考档位，复制指令，粘贴给 Leader。[线程工指南](https://shaotinghe.com/threados/)。
- **分区工：**先阅读[设置指南](https://shaotinghe.com/sectorium/)，再使用磁盘操作。它仍是试验功能，请先备份重要数据，用非关键数据试用；完整安全弹出成功前不要拔盘。

### 遇到问题

- **打开的还是旧版：**正常退出后，从选定的“应用程序”文件夹打开，不要打开“下载”里的旧副本。
- **macOS 阻止启动或提示应用损坏：**从正式发布页重新下载，并按下方方法校验。不要关闭系统安全检查或强行启动。仍有问题时，请[反馈具体提示](https://github.com/ShaoJHe-SilkRoad/UMA/issues)。
- **需要退回旧版：**退出 AUV，将备份的旧应用放回原位置。这只回退应用，不会撤销分区工工具、服务或磁盘数据的变化。

### 可选：校验下载文件

如果 ZIP 保留原名并位于“下载”文件夹，在终端执行：

```sh
shasum -a 256 ~/Downloads/AUV-0.15.1-build2026101002.zip
```

输出的第一个值应为：

```text
598bd61b8a439dde426b943bee3f84e57ad46bba96b94747405ae687825d505e
```

不一致就不要安装，请重新下载。[正式发布页](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.15.1)也提供 `HASHES.txt` 和签名记录；签名者为 **SHAOTING HE (C6TUZVJ6SJ)**。
