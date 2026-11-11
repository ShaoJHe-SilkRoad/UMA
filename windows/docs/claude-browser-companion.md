# AUV Claude browser companion (Chrome / Edge) · AUV Claude 浏览器伴侣

[English](#english) · [中文](#中文)

## English

AUV for Windows reads Claude's exact plan limits through a small companion extension in Chrome or Edge. It works like the Mac's Safari companion: for each sync, the extension opens claude.ai's official Usage page (`https://claude.ai/new#settings/usage`) in a background tab, reads the plan-limit percentages and reset times, and closes the tab. Browser sync is **off** until you turn it on.

### What is read and what is not

- **Read:** the 5-hour and weekly (all models) used percentages, their reset times, and when they were read.
- **Never read or sent:** passwords, cookies, tokens, conversations, page text, your plan name, e-mail or organization, and any other tab. Claude tabs you open yourself are not read.
- Your Claude sign-in stays in the browser. AUV keeps the figures in memory only and shows them while they are current: up to the refresh interval plus two minutes.
- The extension asks for: *Read and change your data on claude.ai* (limited to `https://claude.ai/new*`, the Usage page), and *Communicate with cooperating native applications* (AUV's helper). It also uses `storage` and `alarms`.

### Set up

1. In AUV, select **Claude** and choose **Connect** on the *Connect Claude* card (also in Claude settings). Confirm once. The companion stays where it is, inside the AUV folder: the extension is `<AUV folder>\BrowserCompanion\extension` and its helper is `<AUV folder>\BrowserCompanion\host\AUV.BrowserHost.exe`. AUV writes two small setup files beside the helper, registers it for Chrome and Edge under your Windows account (`HKEY_CURRENT_USER`) and turns Claude sync on. Nothing is copied elsewhere and no administrator rights are needed; your settings stay in `%LOCALAPPDATA%\AUV.Windows.UI.Preview`. If the registration belongs to AUV's own companion in another folder (another AUV version, or the 0.18.5 copy), it is replaced without asking; only another program's registration makes AUV ask first.
   - The AUV folder must be one you can write to. Under `C:\Program Files` (or a read-only share) Connect stops and says so: move the AUV folder to Documents or another drive and choose Connect again.
   - If AUV 0.18.5 had copied the companion to `%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\`, AUV asks once, after Connect succeeds, whether to delete that copy (default **No**; keep it while you still run 0.18.5). If a browser is still running the old helper, that file is in use: AUV deletes everything else, says that the rest will be removed after the browser closes, and finishes when the old helper exits or at AUV's next start. Only that folder is touched.
2. A checklist follows the next steps and ticks each one when AUV sees it happen:
   - ① **Registered for Chrome and Edge**: ticked by Connect.
   - ② **Load the extension**: choose **Load in Chrome** (or **Load in Edge**). AUV copies the extension folder's path, opens the browser's extensions page and shows what to do: turn on **Developer mode** → **Load unpacked** → press **Ctrl+V** in the folder window's address bar → **Select Folder**. Ticked when that browser's companion answers AUV.
   - ③ **Sign in to claude.ai**: **Open claude.ai** opens it in that browser; you sign in yourself. Ticked at the first exact reading.
3. Once all three are ticked, the checklist becomes one line: *Connected · Chrome · last reading 14:05*.

The browser, where the Usage page opens, whether to ask before opening the browser, and the extension folder (with Copy folder path and Open folder) are under **Advanced** in Claude settings.

The extension's ID is `jnbjegolfmhehndgimjidefmggpnagji`. The browser may remind you that a developer-mode extension is installed; that is expected for an extension that is not from the Chrome Web Store or Edge Add-ons.

### How syncs happen

- Refresh All, automatic refresh, **Sync now** (Claude settings), and the companion's toolbar button all start a sync.
- If a normal browser window is open, the Usage page opens as an inactive tab in it; otherwise it opens in a small minimized window. You can choose either one under **Read in**.
- Chrome and Edge quit when their last window closes. So when that minimized window is the browser's only window, the companion keeps it minimized with a blank tab instead of closing it, and later reads reuse it. You may see it in the taskbar; closing it is fine, and the next read opens a new one.
- A read that gets no answer ends after about 6 seconds of silence and is retried 20 seconds after the sync started.
- If the browser is not running, AUV asks whether to open it minimized. During automatic refresh it asks once per stretch, and you can tell it not to ask.
- If the companion stops answering, AUV says so. Reload the extension on the browser's extensions page, or restart the browser. AUV never restarts your browser.

### Update

Each AUV version comes in its own folder, and the companion is used from there. When you start a new AUV with Claude sync on, it moves the browsers' registration to its own folder by itself (AUV's own registration, so it does not ask; only a failure is shown, with **Retry**). The previous AUV folder is never changed.

The browser, however, still runs the extension from the previous folder. Asking it to reload (AUV does that for an extension from another build, at most once every 10 minutes) cannot help here, because a reload reads the same old folder. So the checklist shows step 2 again: choose **Load in Chrome** (or Edge) once to load the extension from the new folder. If the browser still lists the previous AUV extension, remove it there. The reload request only helps when a new build is put into the same folder.

### Remove

1. In Claude settings choose **Remove companion**. AUV deletes its two registry keys (only keys that point into its own folder) and the two setup files it wrote, and turns browser sync off. The companion files inside the AUV folder stay; they go when you delete the AUV folder. If the 0.18.5 copy under `%LOCALAPPDATA%` still exists, AUV offers to delete it too (default No).
2. Remove the extension on the browser's extensions page; AUV cannot do that for you.

To remove the registration by hand:

```bat
reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
```

### Troubleshooting

| AUV says | What to do (the Claude card offers the matching button) |
|---|---|
| Waiting for Chrome or Edge with the AUV companion | Open the browser where you loaded the extension. Check that the extension is on in its extensions page. |
| The companion needs access to claude.ai | On the extension's details page, set *Site access* to allow `claude.ai`. |
| Sign in to claude.ai | Sign in to claude.ai in that browser, then refresh. |
| The AUV extension in Chrome (or Edge) is from a different build | AUV asks the extension to reload itself; the message goes away once it has. If it stays (always the case right after upgrading from AUV 0.18.5), choose **Open Chrome extensions page** beside it and reload the extension once. |
| The AUV extension in Chrome (or Edge) still comes from your previous AUV folder | You started a new AUV (a new folder). Choose **Load in Chrome** (or Edge) in step 2 to load the extension from this AUV's folder; reloading the old one does not help. |
| The browser companion is not answering | Reload the extension, or restart the browser. |
| Claude's Usage page layout is not recognized | claude.ai changed its page. No figure is shown rather than a wrong one; an AUV update is needed. |

The reader recognizes claude.ai's Usage page in English and in Chinese (简体中文). In another interface language it reads nothing and says so; switch claude.ai to English or Chinese.

---

## 中文

AUV Windows 版通过 Chrome 或 Edge 中的一个小型伴侣扩展读取 Claude 的精确套餐额度，做法与 Mac 上的 Safari 伴侣相同：每次同步时，扩展在后台标签页打开 claude.ai 官方用量页（`https://claude.ai/new#settings/usage`），读取套餐额度百分比和重置时间，然后关闭该标签页。浏览器同步默认**关闭**，需要你自己开启。

### 读取什么，不读取什么

- **读取：**5 小时窗口和每周（所有模型）窗口的已用百分比、各自的重置时间，以及读取时间。
- **从不读取或发送：**密码、Cookie、令牌、对话、页面文字、套餐名称、邮箱或组织，以及任何其他标签页。你自己打开的 Claude 标签页不会被读取。
- 你的 Claude 登录状态留在浏览器中。AUV 只在内存中保留这些读数，并且只在它们仍算当前时显示，即刷新间隔 + 2 分钟以内。
- 扩展申请的权限：“读取和更改你在 claude.ai 上的数据”（仅限用量页所在的 `https://claude.ai/new*`）、“与协作的本机应用通信”（即 AUV 的辅助程序），另外使用 `storage` 和 `alarms`。

### 设置

1. 在 AUV 中选择 **Claude**，在“连接 Claude”卡片上选择**连接**（Claude 设置中也有），确认一次即可。伴侣就留在 AUV 文件夹里使用：扩展是 `<AUV 文件夹>\BrowserCompanion\extension`，辅助程序是 `<AUV 文件夹>\BrowserCompanion\host\AUV.BrowserHost.exe`。AUV 在辅助程序旁写入两个小的设置文件，在你的 Windows 账户下（`HKEY_CURRENT_USER`）为 Chrome 和 Edge 注册它，并开启 Claude 同步。不会复制到其他位置，也不需要管理员权限；你的设置仍在 `%LOCALAPPDATA%\AUV.Windows.UI.Preview`。如果已有的注册是 AUV 自己在其他文件夹中的伴侣（另一版本的 AUV，或 0.18.5 的副本），会直接替换，不再询问；只有其他程序的注册才会先询问你。
   - AUV 文件夹必须可写。如果放在 `C:\Program Files`（或只读共享）下，“连接”会停止并说明原因：请把 AUV 文件夹移到“文档”或其他磁盘，再选择“连接”。
   - 如果 AUV 0.18.5 曾把伴侣复制到 `%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\`，“连接”成功后 AUV 会询问一次是否删除该副本（默认**否**；如果还在运行 0.18.5，请保留）。如果浏览器仍在运行旧的辅助程序，该文件正被占用：AUV 会先删除其余文件，并提示剩余部分将在浏览器关闭后删除；旧辅助程序退出时或下次启动 AUV 时再完成删除。只处理该文件夹。
2. 接下来的步骤显示为一份清单，AUV 看到某一步完成时会自动打勾：
   - ① **已为 Chrome 和 Edge 注册**：选择“连接”后打勾。
   - ② **加载扩展**：选择**在 Chrome 中加载**（或**在 Edge 中加载**）。AUV 会复制扩展文件夹的路径，打开浏览器的扩展页，并提示操作：开启**开发者模式** → **加载已解压的扩展程序** → 在文件夹窗口的地址栏按 **Ctrl+V** 粘贴路径 → **选择文件夹**。该浏览器中的伴侣回应 AUV 后打勾。
   - ③ **登录 claude.ai**：**打开 claude.ai** 会在该浏览器中打开网站，由你自己登录。第一次读到精确读数时打勾。
3. 三步都打勾后，清单收起为一行：“已连接 · Chrome · 上次读数 14:05”。

浏览器、用量页的打开位置、打开浏览器前是否询问，以及扩展文件夹（含“复制文件夹路径”“打开文件夹”）都在 Claude 设置的**高级**中。

扩展 ID 为 `jnbjegolfmhehndgimjidefmggpnagji`。浏览器可能提示你装有开发者模式扩展；不是从 Chrome 应用商店或 Edge 加载项商店安装的扩展都会这样，属正常现象。

### 同步如何进行

- “全部刷新”、自动刷新、**立即同步**（Claude 设置），以及伴侣在工具栏上的按钮，都会触发一次同步。
- 如果浏览器有打开的普通窗口，用量页会在其中以非活动标签页打开；没有时，会在一个最小化的小窗口中打开。你可以在**读取位置**中固定选择其中一种。
- Chrome 和 Edge 在最后一个窗口关闭时会退出。因此，当这个最小化窗口是浏览器唯一的窗口时，伴侣不会关闭它，而是保留为一个带空白标签页的最小化窗口，之后的读取会复用它。任务栏里可能会看到它；关掉也没关系，下一次读取会再开一个。
- 页面沉默约 6 秒没有回应时，这次读取会结束，并在同步开始 20 秒后重试一次。
- 浏览器未运行时，AUV 会询问是否以最小化方式打开它。自动刷新时同一轮只问一次，你也可以让它不再询问。
- 伴侣没有响应时，AUV 会提示你。请在浏览器扩展页重新加载扩展，或重启浏览器。AUV 不会替你重启浏览器。

### 更新

每个版本的 AUV 都在自己的文件夹里，伴侣也从那里使用。开启 Claude 同步时启动新版 AUV，它会自动把浏览器注册改为指向自己的文件夹（这是 AUV 自己的注册，所以不询问；只有失败时才显示原因和**重试**按钮）。上一份 AUV 的文件夹从不改动。

但浏览器中运行的仍是上一个文件夹里的扩展。让它“重新加载”（AUV 会对来自其他构建的扩展这样请求，每个浏览器最多每 10 分钟一次）在这里没有用，因为重新加载读的还是原来的旧文件夹。所以清单会重新显示第 2 步：选择一次**在 Chrome 中加载**（或 Edge），从新文件夹加载扩展；如果浏览器里还列着旧的 AUV 扩展，请把它移除。“重新加载”请求只在新构建放进同一文件夹时才有用。

### 移除

1. 在 Claude 设置中选择**移除伴侣**。AUV 会删除它的两个注册表项（只删除指向它自己文件夹的项）和它写入的两个设置文件，并关闭浏览器同步。AUV 文件夹中的伴侣文件会保留，删除 AUV 文件夹时一并删除。如果 `%LOCALAPPDATA%` 下 0.18.5 的副本还在，AUV 也会询问是否删除（默认“否”）。
2. 在浏览器扩展页中移除扩展；AUV 无法替你移除。

手动删除注册：

```bat
reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
```

### 排错

| AUV 显示 | 处理方法（Claude 卡片上有对应按钮） |
|---|---|
| 正在等待装有 AUV 伴侣的 Chrome 或 Edge | 打开你加载扩展的那个浏览器，并在扩展页确认扩展已开启。 |
| 伴侣需要访问 claude.ai | 在扩展详情页把“网站访问权限”设为允许 `claude.ai`。 |
| 请在浏览器中登录 claude.ai | 在该浏览器中登录 claude.ai，然后刷新。 |
| Chrome（或 Edge）中的 AUV 扩展来自不同的构建 | AUV 会请扩展自行重新加载，完成后提示就会消失。如果提示一直存在（从 AUV 0.18.5 升级后必然如此），请选择旁边的**打开 Chrome 扩展页**，手动重新加载一次扩展。 |
| Chrome（或 Edge）中的 AUV 扩展仍来自上一份 AUV 的文件夹 | 你启动的是新的 AUV（新文件夹）。请在第 2 步选择**在 Chrome 中加载**（或 Edge），从这份 AUV 的文件夹加载扩展；对旧扩展“重新加载”没有用。 |
| 浏览器伴侣没有响应 | 重新加载扩展，或重启浏览器。 |
| 无法识别 Claude 用量页的布局 | claude.ai 改版了页面。AUV 宁可不显示也不显示错误数字，需要等 AUV 更新。 |

读取程序能识别英文和简体中文的 claude.ai 用量页。其他界面语言下读不到数据，AUV 会显示原因；请把 claude.ai 切换为英文或中文。
