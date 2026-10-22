# AUV Mac 0.17.6

**Build 2026102202 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.6/AUV_Mac_0.17.6_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

You can put your agents in the order you want, and the menu bar follows it.

- **Drag the agent list into an order.** In the AUV window, drag one agent row onto another to move it there. The agent on top is the one you see first.
- **The order is kept until you change it again.** It is saved the moment you change it and survives quitting the app. It is stored by agent, not by position, so an agent appearing, disappearing or being renamed will not scramble it. An agent you have not placed yet appears at the end of the list rather than jumping to the top.
- **The menu bar number follows your order.** It belongs to the topmost agent that has a reading. If the agent you put on top has nothing to report right now, the number passes to the next agent in your order rather than disappearing.
- **The quick panel follows it too**, so the menu bar panel and the main window never disagree about which agent is first.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## What this does not change

Until you drag something, nothing changes. With no order of your own, Codex keeps priority for the menu bar number exactly as before, and the lists appear exactly as they did. Nothing about which agents are found, what they report, or how any figure is calculated is affected by this release.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction, including with a download quarantine flag applied. Physical Intel Macs and macOS 14/15 were not tested.

The drag itself was exercised on the running app rather than only in tests, which is the part a test cannot answer: dragging one agent above another reordered the list, the order was written immediately, it was still there after quitting and relaunching, and the menu bar kept showing the second agent's figure because the one moved to the top had nothing to report at that moment — the fallback this release describes. The ordering rules behind it — where an unplaced agent goes, what happens to an agent that is no longer installed, which agent the menu bar reads — are covered by tests, and each was confirmed to fail when its rule is removed.

An earlier attempt at the drag did not work at all, because the row was a button and the button's own gesture swallowed it. That was found by trying it on the running app, not by any test, and the rows are no longer buttons; their button role and keyboard action are declared explicitly so assistive technology is unaffected.

Sectorium is unchanged in this release and was not retested.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.6_Universal.zip`
- Size: **14,627,465 bytes**
- SHA-256:

```text
d9b59df69bdcdd055b675414901409854f0b7fe30945baaa88c50c3e37962b95
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102202 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.6/AUV_Mac_0.17.6_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

你可以把智能体排成自己想要的顺序，菜单栏也会跟着这个顺序。

- **拖动智能体列表排序。** 在 AUV 窗口中，把一个智能体行拖到另一行上，即可移到该位置。排在最上面的，就是你最先看到的。
- **顺序会一直保留，直到你再次更改。** 更改的那一刻即保存，退出应用后依然有效。它按智能体标识保存而非按位置，因此某个智能体出现、消失或改名都不会打乱它。你尚未安排过的智能体会出现在列表末尾，而不会跳到最前。
- **菜单栏数字跟随你的顺序。** 它属于你排在最上面、且当前有读数的那个智能体。如果置顶的那个此刻没有数据，数字会交给你顺序中的下一个，而不是消失。
- **菜单栏面板也跟随同一顺序**，因此面板与主窗口不会在"谁排第一"上出现分歧。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换"应用程序"中的旧版前，请先正常退出旧应用。

### 本版不改变的事

在你拖动之前，一切照旧。没有你自己的顺序时，菜单栏数字仍与此前一样由 Codex 优先，列表的显示也完全不变。本版不影响能找到哪些智能体、它们报告什么，以及任何数值的计算方式。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。安装包已完成 Developer ID 签名、Apple 公证与票据装订；重新解压后（含加上下载隔离标记的情况）仍通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

拖动本身是在运行中的应用上实测的，而不只是跑测试——这恰是测试回答不了的部分：把一个智能体拖到另一个上方后列表确实重排，顺序立即写入，退出并重新启动后依然存在；而菜单栏仍显示第二个智能体的数值，因为被移到顶部的那个当时没有读数，这正是本版所述的回退行为。其背后的排序规则——未安排过的智能体排在哪里、已不存在的智能体如何处理、菜单栏读取哪一个——都有测试覆盖，且每条规则被移除后对应测试都确实失败。

最初的拖动实现完全无效，因为那一行是按钮，按钮自身的手势把拖拽吞掉了。这是在运行的应用上试出来的，任何测试都不会告诉我们；现在这些行不再是按钮，其按钮角色与键盘操作改为显式声明，辅助技术不受影响。

本版未改动分区工，也未重新测试。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.6_Universal.zip`
- 大小：**14,627,465 字节**
- SHA-256：

```text
d9b59df69bdcdd055b675414901409854f0b7fe30945baaa88c50c3e37962b95
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
