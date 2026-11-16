# AUV Mac 0.18.11

**Build 2026111601 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app (DMG)](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.11/AUV_Mac_0.18.11_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.11/AUV_Mac_0.18.11_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Sectorium's Disconnect works in one click again, and it clears disk images stored on the drive by itself.

- **Disconnect no longer stops at "an app is using this drive".** In 0.18.10, the macOS helper process that serves a loaded development volume's disk image was listed as an app using the drive, so Disconnect could not go ahead while a volume was loaded. Disconnect releases that image itself, so the helper is no longer counted.
- **Disk images stored on the drive are ejected first.** If you opened a disk image that lives on the drive or inside a development volume, such as an installer DMG you downloaded there, macOS refused to unload the volume around it. Unload and Disconnect now eject such images first, the innermost first, and stop only if an app is using one of them, naming it.

The Safari Bridge inside AUV is unchanged: **UMA Safari Bridge 0.14.7**. Coming from 0.18.10 there is nothing to update in Claude's page.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled, and so is the DMG. A copy of the DMG carrying a download quarantine flag passed Gatekeeper, as did AUV and the Bridge inside it; the ZIP passed after a clean re-extraction. The full test suite ran with only known, unrelated failures.

On an installed build with DEV_APFS loaded on an exFAT USB drive: the activity check passed, and one Disconnect unmounted the volume, released its image, unmounted the drive and ejected it, ready to unplug.

- **Not tried live:** ejecting a disk image stored inside a development volume (covered by tests); physical Intel Macs and macOS 14/15.
- **Load asks for approval:** mounting a development volume inside an external drive needs your password or Touch ID each time.

[Windows is at 0.18.7](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.7-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.11_Universal.dmg`
- Size: **17,590,314 bytes**
- SHA-256:

```text
1c3dc14959235081b79554795048f25c39cd242bcc70a67219513d0b40a7810e
```

- File: `AUV_Mac_0.18.11_Universal.zip`
- Size: **17,389,815 bytes**
- SHA-256:

```text
6b507a3295e81f3940b99c8f78d4f1c25bfefdd4ffb7aba291ae4c9ede931cee
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111601 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用（DMG）](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.11/AUV_Mac_0.18.11_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.11/AUV_Mac_0.18.11_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

分区工的“安全断开”恢复一键完成，并会自己清掉存放在硬盘上的磁盘映像。

- **“安全断开”不再卡在“有应用正在使用此硬盘”。** 0.18.10 中，为已加载开发卷的磁盘映像提供服务的 macOS 辅助进程被当成了“正在使用硬盘的应用”，开发卷加载着时无法安全断开。安全断开本来就会释放这个映像，所以该进程不再计入。
- **先推出存放在硬盘上的磁盘映像。** 如果你打开过存放在硬盘或开发卷里的磁盘映像（比如下载到那里的安装盘），macOS 会拒绝卸载它所在的开发卷。现在“卸载开发卷”和“安全断开”会先推出这些映像，里层的先推；只有当某个映像正被应用使用时才会停下，并说明是哪个应用。

AUV 内置的 Safari 助手没有变化，仍为 **UMA Safari 助手 0.14.7**。从 0.18.10 升级，Claude 页面无需再更新。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订，DMG 本身也一样。带下载隔离标记的 DMG 副本、其中的 AUV 和 Safari 助手都通过 Gatekeeper 检查；ZIP 重新解压后通过检查。全量测试中只有已知、与本版无关的失败。

在已安装的版本上，DEV_APFS 加载在 exFAT USB 硬盘上：占用检查通过，一次“安全断开”依次卸载开发卷、释放其镜像、卸载硬盘并推出，可以直接拔盘。

- **未实测：** 推出存放在开发卷里的磁盘映像（有测试覆盖）；Intel 实机；macOS 14/15。
- **加载需要授权：** 把开发卷挂载到外接硬盘中，每次都需要密码或 Touch ID。

[Windows 版为 0.18.7](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.7-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.11_Universal.dmg`
- 大小：**17,590,314 字节**
- SHA-256：

```text
1c3dc14959235081b79554795048f25c39cd242bcc70a67219513d0b40a7810e
```

- 文件：`AUV_Mac_0.18.11_Universal.zip`
- 大小：**17,389,815 字节**
- SHA-256：

```text
6b507a3295e81f3940b99c8f78d4f1c25bfefdd4ffb7aba291ae4c9ede931cee
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
