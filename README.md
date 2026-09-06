<p align="center">
  <img src="Assets/AppIcon.png" width="148" alt="UMA app icon">
</p>

<h1 align="center">UMA</h1>

<p align="center"><strong>Local-first usage and quota monitoring for AI coding agents on macOS.</strong></p>

<p align="center">
  <a href="https://github.com/ShaoJHe-SilkRoad/UMA/releases/latest"><strong>Download latest release</strong></a>
  · macOS 14+
  · Apple Silicon
  · Developer ID signed & notarized
</p>

<p align="center">
  <img src="Assets/AgentLogos/codex.svg" width="44" alt="Codex logo">&nbsp;&nbsp;&nbsp;
  <img src="Assets/AgentLogos/claude-code.svg" width="44" alt="Claude Code logo">
</p>

<p align="center">
  <a href="#中文">中文</a> · <a href="#english">English</a>
</p>

> **Current release:** UMA 0.14.0 · build `2026090504` · tag [`v0.14.0`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.14.0)

---

## 中文

UMA 是一个原生 macOS AI Agent 用量监控应用。0.14 已从早期单一 Codex 菜单栏工具升级为一套统一产品界面：**Quick Panel、Agents & Settings、Global Settings 与 Desktop Wizard** 共用同一份 Provider 状态与偏好设置，当前正式支持 **Codex 与 Claude**。

### 0.14 的核心变化

| 功能 | 现在的行为 |
| --- | --- |
| **Quick Panel** | 菜单栏快速查看当前可用 Agent、剩余额度、重置时间，并提供 Open UMA、Scan、Refresh、Wizard 与 Settings 快捷入口。 |
| **Agents & Settings** | 主窗口以 Agent 为中心；查看额度窗口、来源、连接、freshness、最近更新时间，并执行该 Agent 对应的连接、刷新、修复或同步操作。 |
| **Global Settings** | General、Appearance、Desktop Wizard、Privacy & Data 使用同一份 `ApplicationPreferences`；不再把 Provider 的连接表单塞进全局设置。 |
| **Desktop Wizard** | 常驻桌面的小型用量视图，支持 Regular / Minimalist / Automatic、Always on Top、真实 Agent Logo 与 Light/Dark。 |
| **统一状态模型** | Quick Panel、Main、Wizard 和菜单栏消费同一份 Provider product state，而不是各自启动一套连接或缓存。 |
| **后台生命周期** | 窗口开关不再天然拥有 Provider 连接生命周期；默认关闭普通窗口后仍可继续监控，用户也可以明确改变这一行为。 |
| **Wake refresh** | macOS 唤醒后由应用级单一 observer 触发受控刷新；不会因此自动启动 Claude Accuracy Sync。 |

### 剩余额度语义

UMA 的百分比**永远表示剩余量（remaining）**，不是已使用量。

- `77%`：精确剩余 77%。
- `≈90%`：估算剩余约 90%。
- `∞`：只有数据源明确报告无限量时才显示；`100%` 不等于无限量。
- `—`：缺失、不可用或不支持；不会伪装成 `0%`。
- Compact Agent row / Wizard pill 使用**整块实体填充**表达剩余比例，而不是底部一根细进度线。
- 低剩余额度会按 Provider / plan 的既有规则进入红色警示；连接状态颜色与额度警示是两套独立语义。
- 百分比额度与 credits 不做虚假的跨单位归一化。

### 当前 Provider 行为

#### Codex

Codex 使用本机正式来源读取账户额度与相关使用信息，并复用现有登录状态。UMA 维持应用级连接生命周期；Quick Panel、Main Window、Settings 或 Wizard 的显示/关闭不会各自创建一套 Provider session。

#### Claude

Claude 在 UMA 中明确区分三个概念：

1. **Claude Code statusLine** — 在支持的 Claude Code surface 上使用结构化本地状态。
2. **Claude Desktop Local Smart** — 仅在能够合理成立时提供估算；`stale` / `unsupported` 是正常且可显示的结果。
3. **Accuracy Sync** — 用户明确触发的一次性精确同步；它不是后台持续 Safari 监控。

估算始终保留 `≈`，不会因为界面更紧凑而伪装成精确值。

### 四个主要界面

#### 1. Quick Panel

从菜单栏快速打开。只展示当前符合产品准入条件的 Agent，不承担长期设置、onboarding 或复杂诊断。

#### 2. Agents & Settings

主窗口左侧选择 Agent，右侧查看：

- quota windows / reset；
- exact / estimated / unavailable；
- connection、source、freshness；
- refresh / connect / reconnect / disconnect；
- Claude 可用时的本地来源与 Accuracy Sync 入口；
- 已存在并经过准入的 usage / task / cost 信息。

#### 3. Global Settings

- **General**：启动与生命周期、刷新、语言等全局行为；
- **Appearance**：System / Light / Dark 与显示偏好；
- **Desktop Wizard**：启用、Always on Top、Regular / Minimalist / Automatic 等；
- **Privacy & Data**：本地保留数据与受控清理/诊断操作。

#### 4. Desktop Wizard

Desktop Wizard 使用真实 Agent Logo 与状态发光效果。Minimalist 数值区域针对 `≈100%` 等最宽情况做稳定布局，不通过删除 `≈` 或动态缩小 Logo 来挤空间。

### 操作逻辑

```text
Provider sources
     │
     ▼
ProviderProductInventory / shared runtime state
     │
     ├── Menu bar / Quick Panel
     ├── Main · Agents & Settings
     ├── Global Settings
     └── Desktop Wizard

User action
     │
     ├── Refresh / Scan
     ├── Connect / Repair
     └── explicit one-shot Accuracy Sync (Claude, when available)
```

一个界面消失，不代表 Provider 必须被销毁；一个缓存值重新发布，也不代表它变成了新的实时数据。UMA 将 **precision、freshness、availability、connection 与 health** 分开表达。

### 隐私原则

UMA 是 local-first 工具。产品状态与诊断边界只允许与用量监控相关的最小信息。

UMA 不应保留：

- prompts / responses / chats；
- credentials、cookies、tokens；
- raw DOM；
- 与用量监控无关的浏览器内容；
- 不必要的账户身份或账单正文。

Claude Accuracy Sync 是显式一次性操作；0.14 不把它变成持续 Safari polling。

### 当前支持状态

| 项目 | 0.14 状态 |
| --- | --- |
| Codex | **Active support** |
| Claude | **Active support** |
| WorkBuddy | 资源/兼容代码可能存在，但当前 active runtime/UI 不重新启用 |
| Google Antigravity | 未检测/未安装时不进入 active surfaces |
| ThreadOS product page | 保留未来入口；0.14 中 runtime activity = **ZERO** |

### 下载与安装

下载当前正式版本：

**[UMA 0.14.0 — build 2026090504](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.14.0)**

直接下载：

**[UMA-0.14.0-build2026090504.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/UMA-0.14.0-build2026090504.zip)**

要求：

- macOS 14 或更高；
- Apple Silicon (`arm64`)；
- 对应 Provider 需要其本机应用/CLI 与已登录状态才能提供相应数据。

发布包使用 Developer ID 签名，并完成 Apple notarization、stapling 与 Gatekeeper 验证。解压后将 `UMA.app` 放入稳定的 Applications 位置再运行；不要通过关闭 macOS 安全机制来绕过正常安装流程。

SHA-256 与延期验收说明与 Release 一同发布：[`HASHES.txt`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/HASHES.txt) · [`DEFERRED-QA.md`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/DEFERRED-QA.md)

### 从源码开发

```bash
./script/build_and_run.sh
```

这是开发入口，不等于正式 Release 签名/公证流程。SwiftPM 当前目标为 macOS 14+；正式发布包使用独立的 release packaging、Developer ID 与 notarization 流程。

### 0.15 Roadmap

0.15 正在拆成两条独立开发线；以下均为**计划中的工作，不属于当前 0.14 release**：

- **Windows support** — 在原生 Windows 环境实现 UMA 的平台支持，同时保持共享 quota / freshness / privacy 语义。
- **UMA × ThreadOS × Sectorium ecosystem** — 在 macOS 侧探索可操作的生态集合；状态、命令和生命周期必须通过明确接口集成，而不是让多个系统同时争夺同一任务的所有权。

---

## English

UMA is a native macOS usage and quota monitor for AI coding agents. Version 0.14 evolves the project from a Codex-only menu-bar utility into a shared product model across **Quick Panel, Agents & Settings, Global Settings, and Desktop Wizard**, with active support for **Codex and Claude**.

### What changed in 0.14

- **Quick Panel** for fast quota checks and actions from the menu bar.
- **Agent-centered Main window** with quota windows, source, freshness, connection state, reset times, and provider-specific actions.
- **Real global Settings** backed by one shared preference model.
- **Desktop Wizard** with Regular / Minimalist / Automatic modes, real agent logos, always-on-top behavior, and stable Light/Dark presentation.
- **Shared provider state** across menu bar, Quick Panel, Main, and Wizard instead of surface-owned connector lifecycles.
- **Controlled wake refresh** with a single application-owned observer.
- **Solid remaining-usage fills** on compact rows/pills; the filled area represents what is left, not what has been consumed.

### Quota semantics

Percentages always mean **remaining**:

- `77%` — exact remaining percentage.
- `≈90%` — estimated remaining percentage.
- `∞` — only when an admitted source explicitly reports unlimited usage.
- `—` — unavailable, missing, or unsupported; never converted to `0%`.

Low remaining levels use plan-aware alert coloring. Connection health and quota severity remain separate visual semantics. Percentage quotas and credit-based quotas are not falsely normalized into the same unit.

### Provider model

**Codex** uses admitted local account sources and an application-owned lifecycle so window visibility does not arbitrarily own the provider connection.

**Claude** keeps three concepts separate:

1. **Claude Code statusLine** — structured local state where supported.
2. **Claude Desktop Local Smart** — estimate-only when qualified; stale/unsupported is a valid outcome.
3. **Accuracy Sync** — an explicit one-shot precision action, not continuous Safari monitoring.

Estimated values remain visibly estimated with `≈`.

### Product surfaces

- **Quick Panel** — glanceable current agents, remaining quota, reset time, Scan, Refresh, Wizard, and Settings shortcuts.
- **Agents & Settings** — detailed agent workspace for quota, source, freshness, connection, and provider-specific actions.
- **Global Settings** — General, Appearance, Desktop Wizard, and Privacy & Data.
- **Desktop Wizard** — compact always-available usage view with Regular / Minimalist / Automatic density and real agent-logo rendering.

### Runtime model

```text
Provider sources
     │
     ▼
ProviderProductInventory / shared runtime state
     │
     ├── Menu bar / Quick Panel
     ├── Main · Agents & Settings
     ├── Global Settings
     └── Desktop Wizard
```

Closing a surface is not the same thing as disconnecting a provider. Republishing cached data is not treated as a new successful observation. Precision, freshness, availability, connection, and health are modeled separately.

### Privacy

UMA is local-first and usage-metadata focused. It is designed not to retain prompts, responses, chats, credentials, cookies, tokens, raw DOM, unrelated browser content, or unnecessary billing/account payloads.

Claude Accuracy Sync remains explicit and one-shot in 0.14; it does not enable continuous Safari polling.

### Current support

| Component | 0.14 status |
| --- | --- |
| Codex | **Active support** |
| Claude | **Active support** |
| WorkBuddy | Dormant compatibility/assets only; active runtime is not re-enabled |
| Google Antigravity | Hidden from active surfaces when absent/unavailable |
| ThreadOS product page | Reserved future seam; runtime activity is **ZERO** in 0.14 |

### Download

**[UMA 0.14.0 — build 2026090504](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.14.0)**

Direct download:

**[UMA-0.14.0-build2026090504.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/UMA-0.14.0-build2026090504.zip)**

Requirements:

- macOS 14 or later;
- Apple Silicon (`arm64`);
- the relevant local provider app/CLI and signed-in state for provider data.

The release is Developer ID signed, Apple-notarized, stapled, and Gatekeeper-validated. Move `UMA.app` to a stable Applications location before normal use.

Release integrity and deferred qualification notes are published alongside the app: [`HASHES.txt`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/HASHES.txt) · [`DEFERRED-QA.md`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.14.0/DEFERRED-QA.md)

### Development

```bash
./script/build_and_run.sh
```

This is a development entry point, not the Developer ID/notarized release pipeline. The current SwiftPM package targets macOS 14+.

### 0.15 roadmap

Two development tracks are planned in parallel; neither is part of the current 0.14 release:

- **Windows support** — native Windows development while preserving shared quota, freshness, and privacy semantics.
- **UMA × ThreadOS × Sectorium ecosystem** — macOS operational integration through explicit interfaces and ownership boundaries rather than competing lifecycle controllers.

---

## Security & release integrity

Current public release: [`v0.14.0`](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.14.0), build `2026090504`.

The GitHub Release publishes the app archive, SHA-256 manifest, and Founder-accepted deferred-QA disclosure. Deferred items are intentionally documented as deferred rather than being represented as completed validation.
