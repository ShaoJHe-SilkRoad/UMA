# AUV Mac 0.18.10

**Build 2026111519 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app (DMG)](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.10/AUV_Mac_0.18.10_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.10/AUV_Mac_0.18.10_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

A new icon, Claude syncs that no longer stop for good, and a faster and safer Sectorium.

### A new look and a welcome
- **New icon.** AUV's icon is now a bowing Qing attendant raising a ruler, in navy on cream with one red tassel: AUV as the old Beijing greeting. The Safari Bridge uses the same icon, and its Safari toolbar button now shows a small version of it instead of a blank square.
- **Welcome tune.** The first time a new version opens from Applications, AUV plays the first seven notes of 门楼 instead of a system sound. Five quick clicks on AUV's Dock icon or its menu-bar button play it again.

### Claude
- **Syncs no longer stop for good.** If a read's cleanup was interrupted, the Safari Bridge kept a stale record and refused every later read, so Claude showed its last reading indefinitely. The Bridge now clears such a record by itself. This needs **UMA Safari Bridge 0.14.7**, which ships inside AUV: Claude's page shows **Update Safari Bridge**, and one click installs it in place.
- **A suspended page gets a second chance.** With Safari on screen, AUV reads Claude's usage in a hidden background tab, and Safari sometimes suspends that tab. When a read ends that way, its automatic retry opens in a small temporary Safari window, which closes by itself. Normal reads are unchanged.
- **The Bridge stays in Applications.** AUV only treats a Bridge in /Applications or ~/Applications as installed, so an update never lands in a copy kept elsewhere, such as on an external drive.

### Sectorium
- **Faster Load and Unload.** Unload takes about 2 seconds. AUV's own work in a Load dropped from about 2.7 to 1.4 seconds; the rest is macOS attaching the disk image and the password or Touch ID approval for mounting inside the drive. Each Load, Unload and Disconnect writes a step-by-step timing log.
- **Unplugged without Disconnect.** When the drive disappears with a volume still loaded, AUV releases it at once. The next Load checks the volume read-only before mounting it, and does not mount it if the check fails. A stale attachment left from an earlier connection is released automatically.
- **Drives describe their volumes.** IMPORTANT.md at the drive's root now starts with what is on the drive and how to use it, lists each volume's settings keyed by the drive's disk ID, and shows the exact Terminal commands to load, unload and eject. Earlier copies move to `.AUV-Sectorium/previous-versions` instead of piling up in the root.
- **Scan drives.** A new button on the Sectorium page registers the volumes a connected drive's IMPORTANT.md records, if its disk ID matches; an optional setting does this whenever a drive connects. Registering never loads a volume.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled, and so is the DMG. A copy of the DMG carrying a download quarantine flag passed Gatekeeper, as did AUV and the Bridge inside it; the ZIP passed after a clean re-extraction. The full test suite ran with only known, unrelated failures.

On an installed build: the one-click Bridge update replaced 0.14.4 with 0.14.6, and later 0.14.6 with 0.14.7, in ~/Applications with the extension still enabled, and Claude synced exactly afterwards; Safari's toolbar showed the new icon. Sectorium Load and Unload were timed on a 300 GB development volume on an exFAT USB drive, and IMPORTANT.md was rewritten with the old copies archived.

- **First open:** like any app downloaded from the internet, macOS asks once whether to open AUV. Signing and notarization do not remove that question.
- **Load asks for approval:** mounting a development volume inside an external drive needs your password or Touch ID each time. That is macOS's rule for mounting inside a drive it owns.
- **Not tried live:** the temporary-window retry (covered by tests), an actual unplug without Disconnect (covered by tests), the welcome tune by ear, Scan drives on a second Mac, physical Intel Macs and macOS 14/15.
- The Safari Bridge is built for Apple silicon only, as before.

[Windows is at 0.18.7](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.7-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.10_Universal.dmg`
- Size: **17,518,416 bytes**
- SHA-256:

```text
803c8ae78f0c7e1519b15120d7db6cccfe8e3bde0d445dd1297adcafd1d531ce
```

- File: `AUV_Mac_0.18.10_Universal.zip`
- Size: **17,315,683 bytes**
- SHA-256:

```text
5f90fd70a3b1beab15ca7e46c8beeb2e8dbfa3abe9784490f488ba0cb2a9f3d8
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111519 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用（DMG）](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.10/AUV_Mac_0.18.10_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.10/AUV_Mac_0.18.10_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

新图标；Claude 同步不再一停就停住；分区工更快、更安全。

#### 新面貌与欢迎曲
- **新图标。** AUV 的图标换成一位躬身托起刻度尺的清宫侍从：墨蓝剪影、米色底、帽缨一点朱红，取 AUV 是老北京“问好”之意。Safari 助手用同一个图标，Safari 工具栏上的按钮也显示它的简化版，不再是一个空白方块。
- **欢迎曲。** 新版本第一次从“应用程序”打开时，AUV 播放《门楼》的前七个音，取代原来的系统提示音。在程序坞图标或菜单栏的 AUV 按钮上快速连点 5 下，可以再听一次。

#### Claude
- **同步不会再一直停住。** 以前一次读取的清理被打断后，Safari 助手会留下一条过期记录，之后每次读取都被拒绝，Claude 就一直显示上次的读数。现在 Safari 助手会自己清掉这种记录。这需要 **UMA Safari 助手 0.14.7**，它已内置在 AUV 中：Claude 页面会显示“更新 Safari 助手”，点一下就原地更新。
- **页面被挂起时会再试一次。** Safari 在屏幕上时，AUV 在一个隐藏的后台标签页里读取 Claude 用量，而 Safari 有时会挂起这个标签页。读取因此失败时，自动重试会改用一个临时的 Safari 小窗口，读完自动关闭。平常的读取不变。
- **Safari 助手只认“应用程序”文件夹。** AUV 只把 /Applications 或 ~/Applications 里的 Safari 助手算作已安装，更新不会装进放在别处的副本，比如外接硬盘上的那份。

#### 分区工
- **加载、卸载更快。** 卸载约 2 秒。加载中 AUV 自身的耗时从约 2.7 秒降到 1.4 秒，其余时间是 macOS 挂接磁盘映像，以及把开发卷挂载到硬盘中所需的密码或 Touch ID 授权。每次加载、卸载、断开都会写一份逐步计时日志。
- **没点“断开”就拔盘。** 开发卷还加载着、硬盘就被拔走时，AUV 会立即释放它；下次加载前先只读检查开发卷，检查不通过就不挂载。上次连接留下的失效挂接会被自动释放。
- **硬盘自己说明上面有什么。** 硬盘根目录的 IMPORTANT.md 现在开头就写明盘上有什么、怎么用，按硬盘的磁盘标识列出每个开发卷的设置，并给出可直接在“终端”运行的装载、卸载、推出命令。旧副本移到 `.AUV-Sectorium/previous-versions`，不再堆在根目录。
- **扫描硬盘。** 分区工页面新增“扫描硬盘”按钮：已连接硬盘的 IMPORTANT.md 中记录的开发卷，若磁盘标识相符，即可登记；也可以在设置中打开“连接硬盘后自动登记”。登记不会加载开发卷。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订，DMG 本身也一样。带下载隔离标记的 DMG 副本、其中的 AUV 和 Safari 助手都通过 Gatekeeper 检查；ZIP 重新解压后通过检查。全量测试中只有已知、与本版无关的失败。

在已安装的版本上：一键更新先把 Safari 助手从 0.14.4 换成 0.14.6，又从 0.14.6 换成 0.14.7，都装在 ~/Applications 原位，扩展保持启用，之后 Claude 精确同步正常；Safari 工具栏显示新图标。分区工的加载、卸载在 exFAT USB 硬盘上的 300 GB 开发卷上实测计时；IMPORTANT.md 已改写，旧副本已归档。

- **第一次打开：** 与所有从网上下载的应用一样，macOS 会询问一次是否打开 AUV。签名和公证不能免去这一步。
- **加载需要授权：** 把开发卷挂载到外接硬盘中，每次都需要密码或 Touch ID。这是 macOS 对挂载到它所管理的硬盘中的规定。
- **未实测：** 临时小窗口重试（有测试覆盖）、真正不点“断开”就拔盘（有测试覆盖）、欢迎曲的实际听感、在另一台 Mac 上扫描硬盘、Intel 实机、macOS 14/15。
- Safari 助手仍只支持 Apple silicon，与以前相同。

[Windows 版为 0.18.7](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.7-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.10_Universal.dmg`
- 大小：**17,518,416 字节**
- SHA-256：

```text
803c8ae78f0c7e1519b15120d7db6cccfe8e3bde0d445dd1297adcafd1d531ce
```

- 文件：`AUV_Mac_0.18.10_Universal.zip`
- 大小：**17,315,683 字节**
- SHA-256：

```text
5f90fd70a3b1beab15ca7e46c8beeb2e8dbfa3abe9784490f488ba0cb2a9f3d8
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
