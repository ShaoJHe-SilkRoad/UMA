# AUV Mac 0.18.9

**Build 2026111508 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app (DMG)](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.9/AUV_Mac_0.18.9_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.9/AUV_Mac_0.18.9_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Installing from the DMG now shows you what to do and tells you when it is done.

- **A clearer installer window.** The DMG opens with AUV on the left and Applications on the right, an arrow between them and the hint "Drag the app on the left onto Applications to install", in English and Chinese. The app's file is still named UMA.app, so it replaces an earlier install.
- **AUV says when it is installed.** Dragging out of a disk image gives no feedback, so AUV gives it: the first time a new version opens from Applications, it plays a sound and shows **AUV 0.18.9 is installed**, with a button to eject the installer disk if it is still mounted. Opened straight from the disk image, AUV says it is **not installed yet** and how to install it.
- **Reset times line up.** In 0.18.8, Claude's 5H reset line could be drawn smaller than its 7D line. Reset lines now keep one size and wrap when space is short.

The Safari Bridge inside AUV is unchanged: **UMA Safari Bridge 0.14.4**.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled, and so is the DMG. A copy of the DMG carrying a download quarantine flag passed Gatekeeper, as did the app inside it; the ZIP passed after a clean re-extraction. The full test suite ran with only known, unrelated failures.

Installed from this DMG: the installer window showed its layout; the first launch from Applications played the sound and showed the notice, and its button ejected the disk; opened from the disk image, AUV showed the not-installed warning and quit at once from it; Claude's two reset lines had the same size. An earlier build of 0.18.9 could not quit from that warning; that is fixed and a test guards it.

- **First open:** like any app downloaded from the internet, macOS asks once whether to open AUV. Signing and notarization do not remove that question.
- **Known problem:** a read and its retry can both fail when the Mac is busy, because Safari suspends the hidden page. Claude then shows its last reading until the next sync.
- **Not tried:** whether "Open Safari Settings" opens the Extensions pane directly. Physical Intel Macs and macOS 14/15.

Sectorium is unchanged and was not retested. [Windows is at 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.9_Universal.dmg`
- Size: **15,950,932 bytes**
- SHA-256:

```text
dda61efb4a3109d4ccaa505fefeb00797ce83fe3f93fbfea305fd02386204a15
```

- File: `AUV_Mac_0.18.9_Universal.zip`
- Size: **15,745,144 bytes**
- SHA-256:

```text
20e4d494a14b08669a0dd1be13f8407b5450f2444d03282e070065591bff9b9a
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111508 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用（DMG）](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.9/AUV_Mac_0.18.9_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.9/AUV_Mac_0.18.9_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

从 DMG 安装时，窗口会告诉你怎么做，装好后 AUV 会告诉你已经装好。

- **更清楚的安装窗口。** 打开 DMG 后，AUV 在左边，Applications 在右边，中间有箭头，下方有中英文提示“将左边的应用拖到 Applications 完成安装”。应用文件名仍为 UMA.app，可以直接替换旧版。
- **装好后 AUV 会提示。** 从磁盘映像拖动安装本身没有反馈，所以由 AUV 来提示：新版本第一次从“应用程序”打开时，会发出提示音并显示 **“AUV 0.18.9 已安装”**；如果安装盘还挂着，可以一键推出。直接从磁盘映像打开时，AUV 会提示 **“还没有安装”**，并说明安装方法。
- **重置时间字号一致。** 0.18.8 中，Claude 的 5H 重置时间可能比 7D 的字小。现在所有重置时间字号一致，空间不够时换行。

AUV 内置的 Safari 助手没有变化，仍为 **UMA Safari 助手 0.14.4**。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订，DMG 本身也一样。带下载隔离标记的 DMG 副本及其中的应用通过 Gatekeeper 检查；ZIP 重新解压后通过检查。全量测试中只有已知、与本版无关的失败。

从这个 DMG 安装后：安装窗口布局正确；第一次从“应用程序”打开时有提示音和提示，按钮成功推出了安装盘；直接从磁盘映像打开时显示“还没有安装”，并能立即从提示中退出；Claude 两行重置时间字号一致。0.18.9 的一个早期构建无法从该提示退出，现已修复并有测试保护。

- **第一次打开：** 与所有从网上下载的应用一样，macOS 会询问一次是否打开 AUV。签名和公证不能免去这一步。
- **已知问题：** Mac 繁忙时，Safari 会挂起隐藏页面，一次读取和它的重试可能都失败。此时 Claude 显示上次的读数，直到下一次同步。
- **未测试：** “打开 Safari 设置”能否直接打开“扩展”面板；Intel 实机；macOS 14/15。

本版未改动分区工，也未重新测试。[Windows 版为 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.9_Universal.dmg`
- 大小：**15,950,932 字节**
- SHA-256：

```text
dda61efb4a3109d4ccaa505fefeb00797ce83fe3f93fbfea305fd02386204a15
```

- 文件：`AUV_Mac_0.18.9_Universal.zip`
- 大小：**15,745,144 字节**
- SHA-256：

```text
20e4d494a14b08669a0dd1be13f8407b5450f2444d03282e070065591bff9b9a
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
