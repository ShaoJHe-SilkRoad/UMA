# AUV Mac 0.17.7

**Build 2026102401 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.7/AUV_Mac_0.17.7_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

A fix for saved ThreadOS team settings, and the product's own name where it was still wrong.

- **A saved team setup from an older model catalogue is no longer rejected.** Each saved setup records which model catalogue it was written against. The roles AUV filled in by default did not: they always named the newest models, so a setup saved against an older catalogue came back carrying models that catalogue never had, and AUV refused it as invalid. Defaults now come from the catalogue the setup is pinned to, so an older setup opens as what it was.
- **The product is called AUV in the one place it still said UMA.** The Claude consent text — what you read before allowing any local reading at all — named the old product. So did the suggested filename when you save diagnostics.
- **The Ultra thinking level reads in Chinese.** It was left untranslated in the team-settings menus, and the marker that shows when its availability is not yet known dropped the translation entirely.

Nothing about which agents are found, what they report, or how any usage figure is calculated changed in this release.

## What this does not change

Your existing team setup is untouched. The default roles are only consulted when a setup does not specify one, and on the current catalogue they resolve to the same models as before, with one exception: the Repair role's default moves from GPT-5.6 Terra to GPT-6 Luna, because it now takes the worker tier from the catalogue rather than a value frozen into the app.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction, including with a download quarantine flag applied. Physical Intel Macs and macOS 14/15 were not tested.

The catalogue fix and both naming fixes are covered by tests that were each confirmed to fail when their change is removed. Nine tests that had been failing for several releases are now passing; they were what exposed the saved-setup defect, after sitting red long enough that nobody read them. Five tests still fail on the machine used for release checks — Sectorium's own disk tests, one settings layout case and one timing bound — and none of them touch what this release changes.

Two corrections were made during this work and are recorded because the reasoning was wrong, not just the code. The model-catalogue divergence that looked like an inconsistency is deliberate: the Ultra level exists only in one catalogue, so the check that reads it is what makes that level selectable, and unifying it either way broke something real. And a reported defect in the team-settings menus — that they offered combinations the generator would refuse — was not real; a test now pins the menu and the generator together so the question is settled by evidence rather than argument.

Sectorium is unchanged in this release and was not retested.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.7_Universal.zip`
- Size: **14,632,275 bytes**
- SHA-256:

```text
11e947fce88e511c23835e81e05e81c2f1807a20add7f911ec27195d5676ff55
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102401 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.7/AUV_Mac_0.17.7_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

修复已保存的 ThreadOS 团队设置，以及产品名仍写错的那一处。

- **按较早模型目录保存的团队设置不再被判为无效。** 每份已保存的设置都记录了它所依据的模型目录，但 AUV 自动填入的默认角色不记录——它们总是指向最新的模型。于是按较早目录保存的设置再打开时，带着那个目录从未有过的模型，被 AUV 判为无效。现在默认角色改为从该设置所钉的目录读取，旧设置能按它原本的样子打开。
- **产品名在仅存的那一处由 UMA 改为 AUV。** Claude 同意书——你在允许任何本地读取之前所读的文本——仍写着旧产品名；保存诊断文件时的默认文件名也是。
- **Ultra 思考档位有了中文。** 它此前在团队设置菜单中未翻译；而当其可用性尚未确定时，那个标记更是完全丢掉译名。

本版不改变能找到哪些智能体、它们报告什么，以及任何用量数值的计算方式。

### 本版不改变的事

你现有的团队设置不受影响。默认角色只在某项设置未指定时才会被取用；在当前目录下，它们解析出的模型与此前相同，只有一个例外：修复（Repair）角色的默认值从 GPT-5.6 Terra 变为 GPT-6 Luna，因为它现在取自目录中的工人层级，而不再是冻结在应用里的固定值。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换"应用程序"中的旧版前，请先正常退出旧应用。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。安装包已完成 Developer ID 签名、Apple 公证与票据装订；重新解压后（含加上下载隔离标记的情况）仍通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

目录修复与两处命名修复均有测试覆盖，且每一处在移除对应改动后测试确实失败。此前连续多个版本失败的九条测试现已全部通过——正是它们暴露了已保存设置的这个缺陷，只是红得太久以致无人去读。用于发布验证的机器上仍有五条测试失败：分区工自身的磁盘测试、一条设置布局用例和一条时限判定，它们都不涉及本版所改动的内容。

本次工作中有两处判断被推翻，这里一并记录，因为错的是推理而不只是代码。那个看似不一致的模型目录分歧其实是刻意设计：Ultra 档位只存在于其中一个目录，所以读取它的那处检查正是该档位得以可选的原因，往任一方向"统一"都会破坏真实功能。另外，此前报告的"团队设置菜单会提供生成器随后拒绝的组合"这一缺陷并不成立；现在有一条测试把菜单与生成器钉在一起，让这个问题由证据而非推理来回答。

本版未改动分区工，也未重新测试。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.7_Universal.zip`
- 大小：**14,632,275 字节**
- SHA-256：

```text
11e947fce88e511c23835e81e05e81c2f1807a20add7f911ec27195d5676ff55
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
