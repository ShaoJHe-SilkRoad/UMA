# AUV Mac 0.17.5

**Build 2026102201 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.5/AUV_Mac_0.17.5_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

A crash fix, and the Claude page no longer disappears when it has usage to show but no percentage.

- **AUV no longer quits when the Codex app-server goes away.** 0.17.4 could abort — the whole app, not just the connection — when the local Codex process it talks to exited or was replaced while AUV was reading its output. The read reported that through a mechanism Swift cannot catch, so it ended the process. It is now an ordinary end-of-stream, and the session simply reconnects. Two writes to child processes could abort the same way and are fixed with it.
- **Claude appears when it has measured local activity, even without a percentage.** Before, a Claude agent with no exact quota anchor was hidden entirely, discarding token and cost figures AUV had already measured. It now shows what it measured, and still never invents a remaining percentage it does not have.
- **The empty Claude panel explains itself.** It used to say "connect or refresh this agent", which cannot produce a percentage here: refreshing re-reads the same local files, and local activity records token usage, not a remaining allowance. It now names the two things that do produce one — Claude Code writing its official status line when you run it in a terminal, and Claude Desktop's local plan cache for twenty minutes after you use it.
- **Claude's local activity is read more completely.** Three cases used to discard a whole file without saying so: a record file readable by other users was treated as unreadable, which included the `journal.jsonl` files Claude Code writes; one very long line threw away every valid record beside it in the same file; and a file being appended to while AUV read it was indistinguishable from one it could not read, rather than being retried. The coverage figure the Claude page shows was understating itself as a result.
- **Recognized model count is the real count.** It reported 0 or 1 where the data already named every model family in use.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## What this does not change

Claude still produces no remaining percentage from local activity alone, because local activity does not contain one. A percentage comes from an exact usage anchor: Claude Code's status line, or Claude Desktop's local plan cache within twenty minutes of use. 0.17.5 makes AUV truthful about that rather than silent; it does not create a figure that is not there.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction, including with a download quarantine flag applied. Physical Intel Macs and macOS 14/15 were not tested.

The crash fix is covered by tests that cannot assert in the usual way: an abort leaves nothing to catch, so each of the four behaviours was confirmed by removing it and watching the test process die instead of fail — signal 6 for the three raising calls, signal 13 once the pipe signal is no longer ignored. Signal 6 is the signature in the field report that prompted the fix. The field crash itself was not reproduced on demand before and after, because it needed the Codex child process to exit at a particular moment; what was reproduced, and removed, is the aborting mechanism on that exact code path.

The local activity changes were measured against this Mac's real Claude Code data, before and after: files read in full rose from 51 of 56 to 56 of 56 and the coverage figure from 91% to 100%, while the token totals and both cost figures were byte-identical, because those five journal files hold no usage records at all. So that part corrects a coverage figure and closes two paths that had not yet discarded real usage here; it did not recover any.

The Claude page's admission and guidance changes were verified by test and seen on this Mac. Sectorium is unchanged in this release and was not retested; its own real-disk tests remain intermittently unstable on this machine, independently of anything in this release.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.5_Universal.zip`
- Size: **14,598,515 bytes**
- SHA-256:

```text
f0730b1f6bd1814617e63280895246ab7b6e9b78c3ea36903aabced449c83e3a
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102201 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.5/AUV_Mac_0.17.5_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

一个崩溃修复；另外，Claude 页面在有用量可显示但没有百分比时，不再整个消失。

- **Codex app-server 退出时 AUV 不再崩溃。** 0.17.4 在读取本地 Codex 进程输出的过程中，若该进程退出或被替换，可能直接终止**整个应用**而非仅断开连接。失败是通过 Swift 无法捕获的机制报告的，于是进程被结束。现在它只是普通的流结束，会话会自行重连。另有两处向子进程写入的调用可能以同样方式崩溃，一并修复。
- **Claude 有可统计的本地活动时就会显示，即使没有百分比。** 此前，没有精确额度锚点的 Claude 智能体会被整个隐藏，连 AUV 已经统计出的令牌和费用数值一起丢弃。现在它会显示已统计到的内容，同时仍然不会编造它并不掌握的剩余百分比。
- **Claude 的空面板会说明原因。** 它原先显示"连接或刷新此智能体"，而这在此处不可能产生百分比：刷新只是重读同样的本地文件，而本地活动记录的是令牌用量，不是剩余额度。现在它会点明真正能产出百分比的两条途径——在终端运行 Claude Code 时它通过官方状态栏写入，以及使用 Claude 桌面版后 20 分钟内其本地额度缓存。
- **Claude 的本地活动读取更完整。** 此前有三种情况会无声丢弃整个文件：其他用户可读的记录文件被当作不可读（这包含 Claude Code 写出的 `journal.jsonl`）；一行过长会把同一文件中其余所有有效记录一起丢掉；以及 AUV 读取期间被追加写入的文件，与读不了的文件无从区分，而不是重试一次。Claude 页面显示的覆盖率此前因此低报。
- **已识别模型数是真实数量。** 它原先只报 0 或 1，而数据里早已记录了全部在用的模型系列。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换"应用程序"中的旧版前，请先正常退出旧应用。

### 本版不改变的事

仅凭本地活动，Claude 仍然得不出剩余百分比——因为本地活动里本就没有这个数。百分比来自精确用量锚点：Claude Code 的状态栏，或使用 Claude 桌面版后 20 分钟内其本地额度缓存。0.17.5 让 AUV 把这件事说清楚，而不是沉默；它不会凭空造出一个不存在的数字。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。安装包已完成 Developer ID 签名、Apple 公证与票据装订；重新解压后（含加上下载隔离标记的情况）仍通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

崩溃修复的测试无法用通常方式断言：进程被终止后没有可捕获的东西，因此四处行为各自是通过"撤掉该修复后观察测试进程被信号杀死而非断言失败"来确认的——三处抛异常的调用对应 signal 6，不再忽略管道信号时对应 signal 13。signal 6 正是促成本次修复的崩溃报告中的签名。原始的现场崩溃没有做改前改后的按需复现，因为它需要 Codex 子进程在特定时刻退出；被复现并消除的，是那条代码路径上的终止机制本身。

本地活动的改动在本机真实 Claude Code 数据上做了改前改后实测：完整读取的文件从 56 个中的 51 个升至 56 个，覆盖率从 91% 升至 100%；而令牌总量与两项费用数值完全一致，因为那 5 个 journal 文件中根本没有用量记录。所以这部分修正的是一个覆盖率数字，并关闭了两条在本机尚未真正丢弃用量的路径，它没有恢复任何用量。

Claude 页面的准入与说明文案改动经测试验证，并已在本机实际查看。分区工本版未改动，也未重新测试；它自身读取真实磁盘的测试在本机仍然间歇性不稳定，与本版内容无关。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.5_Universal.zip`
- 大小：**14,598,515 字节**
- SHA-256：

```text
f0730b1f6bd1814617e63280895246ab7b6e9b78c3ea36903aabced449c83e3a
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
