# UMA 手动上传 GitHub 指南

本指南用于把 `UMA_GitHub_Upload` 中已清理的仓库内容手动发布到 GitHub。
请先确认目标 Owner 是 `ShaoJHe-SilkRoad`，目标仓库名是 `UMA`。

> 备份 ZIP 只用于备份或传输。GitHub 不会自动把它解压成源代码仓库，也不要把
> `UMA_GitHub_Upload_Backup.zip` 当作仓库源代码上传。

## 上传前先确认

1. 关闭任何可能正在修改源文件的工具。
2. 打开 `UMA_GitHub_Upload`，确认 `README.md`、`Package.swift`、
   `Sources`、`Tests`、`Assets`、`script` 和文档都直接位于该文件夹内。
3. 确认没有 `.git`、`.build`、`.swiftpm`、app bundle、ZIP、日志、账本、
   账户数据或 Codex 会话文件。
4. 确认不要选错现有仓库。旧仓库地址为
   `ShaoJHe-SilkRoad/CodexUsageMonitor`，新目标身份为
   `ShaoJHe-SilkRoad/UMA`。

## 推荐方法：GitHub Desktop

1. 打开 GitHub Desktop。
2. 选择 **File → Add Local Repository**，添加已完成最终本机 Commit 的准备
   仓库（该仓库应保留正确 Git 历史；不要选择不含 `.git` 的清理导出副本）。
3. 登录 GitHub。
4. 创建或选择名为 `UMA` 的仓库。
5. 再次确认 Owner 是 `ShaoJHe-SilkRoad`。
6. 确认当前分支为 `main`；如果不是，请先在本机把发布分支设置为 `main`。
7. 在 Changes 中逐项检查文件，不要包含私有或生成文件。
8. 点击 **Publish repository**，或在已连接仓库中点击 **Push origin**。
9. 在 GitHub 网页打开仓库，确认默认分支为 `main`。
10. 检查 README 是否完整显示，四张 Demo 图片是否正常显示。

如果 GitHub Desktop 认为该文件夹不是 Git 仓库，说明选中了不含 `.git` 的
`UMA_GitHub_Upload` 清理副本。请返回并选择已完成最终 Commit 的准备仓库。
不要初始化或发布原始脏工作区。

## 备选方法：GitHub 网页上传

网页上传不太适合完整源代码仓库，因为文件多、目录深，也不保留本机 Git
历史。只有在明确接受这些限制时才使用。

1. 在 GitHub 上新建 `UMA`，或把旧仓库手动改名为 `UMA`：
   **Settings → General → Repository name → Rename**。
2. 打开目标仓库，选择 **Add file → Upload files**。
3. 上传 `UMA_GitHub_Upload` **里面的内容**，不要上传外层文件夹本身。
4. 不要上传备份 ZIP。
5. 不要上传 `.git`、构建输出、临时安装包、app bundle、账本或任何私有状态。
6. 输入明确的提交说明并完成上传。
7. 检查仓库根目录、`README.md`、`Sources`、`Tests` 和 Demo 图片。
8. 按 `docs/GITHUB_REPOSITORY_METADATA.md` 手动填写 About 描述和 Topics。

## 手动改名时避免改错仓库

1. 在 GitHub 页面顶部确认 Owner 为 `ShaoJHe-SilkRoad`。
2. 记录改名前的完整地址。
3. 进入 **Settings → General**，确认页面标题仍是目标仓库。
4. 把 Repository name 改为 `UMA` 并确认。
5. 返回 Code 页面，确认地址是
   `https://github.com/ShaoJHe-SilkRoad/UMA`。
6. 确认默认分支是 `main`，README 顶部显示 `UMA`。

不要在本任务中创建 Tag、Release 或上传 app bundle 作为正式发布。

## 以后添加朋友协作

1. 打开 UMA 仓库。
2. 进入 **Settings → Collaborators**（GitHub 可能显示
   **Collaborators and teams**）。
3. 点击添加协作者，核对对方 GitHub 用户名后发送邀请。
4. 让朋友通过 feature branch 和 Pull Request 协作，不要共享凭据，也不要
   直接 force-push `main`。

## 上传后隐私检查

在 GitHub 网页逐项搜索并确认不存在：

- API Key、Token、Cookie、认证文件或 Keychain 导出；
- 用户名、邮箱、账户 ID 或真实用量截图；
- `.codex` 会话、原始提供方响应、日志、trace、profile；
- `token-cost-ledger.json` 或其他 Application Support 状态；
- `.build`、`.swiftpm`、`dist`、`work`、app bundle、ZIP 或临时 package；
- 只适用于本机的绝对路径。

最后打开 Demo 图片，确认只包含说明性数据；打开
`UPLOAD_MANIFEST.txt`，核对来源 Commit、文件数和隐私扫描结果。
