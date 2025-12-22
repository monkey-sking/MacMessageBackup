# Mac Message Backup

一款专为 macOS 设计的 iMessage 和通话记录备份工具。它可以将您的信息和通话记录安全地备份到 Gmail (IMAP) 或同步到日历，拥有原生的 macOS 界面和极速的备份性能。

<img src="MacMessageBackup/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="128" alt="App Icon">

## 主要功能

*   **iMessage & 短信备份**：将本地 `chat.db` 中的所有短信和 iMessage 备份到 Gmail，支持附件和完整对话内容。
*   **通话记录备份**：将通话记录备份到 Gmail，保留通话时长、类型（呼入/呼出）等元数据。
*   **日历同步**：将通话记录同步到 macOS 本地日历，方便在日历视图中回顾通话历史。
*   **极速备份引擎**：
    *   内置 Python 批量处理引擎，通过复用 IMAP 连接大幅提升备份速度。
    *   无需频繁握手，支持每秒处理数百条记录。
*   **原生 macOS 体验**：
    *   **菜单栏常驻**：在菜单栏实时显示备份进度（如 "正在备份 52/460"），不占用 Dock 空间。
    *   **完全后台运行**：点击菜单栏即可快速开始或取消备份。
    *   **权限自动管理**：自动检测并引导用户授予“完全磁盘访问权限”（用于读取 iMessage 数据库）。
*   **断点续传**：自动记录备份进度，中断后可从上次停止的位置继续备份，无需从头开始。

## 技术特点

*   **SwiftUI + AppKit**：采用现代 SwiftUI 构建界面，结合 AppKit 实现底层系统交互。
*   **Python 集成**：利用 Python 的 `imaplib` 处理复杂的 IMAP 协议交互，实现高效的批量上传。
*   **SQLite 直接读取**：直接读取 macOS 系统数据库 (`chat.db`, `CallHistory.storedata`)，确保数据完整性。
*   **安全**：
    *   密码存储在 macOS 钥匙串 (Keychain) 中。
    *   直接与 Gmail 通信，无中间服务器。

## 安装与运行 requirements

*   macOS 13.0 (Ventura) 或更高版本
*   Xcode 14+ (用于编译)
*   Python 3 (macOS 内置即可)

### 编译步骤

1.  克隆项目：
    ```bash
    git clone https://github.com/yourusername/MacMessageBackup.git
    cd MacMessageBackup
    ```
2.  打开 `MacMessageBackup.xcodeproj`。
3.  确保 Signing & Capabilities 中选择了你的开发团队。
4.  点击 Run (或 Cmd+R) 运行。

## 🛡️ 安装与运行问题 (必读)

由于本项目是个人开源项目，没有购买 Apple 开发者签名（需 $99/年），macOS 的安全机制（Gatekeeper）会默认阻止应用运行。您可能会遇到以下报错：
*   **"无法打开 MacMessageBackup，因为它来自身份不明的开发者。"**
*   **"MacMessageBackup 已损坏，无法打开。你应该将它移到废纸篓。"** (常见于 macOS 13+)

请按照以下方法解决（任选其一，推荐方法 1）：

### 方法 1：右键打开 (推荐，最简单)
适用于大多数情况：
1.  在 Finder 中找到 `MacMessageBackup.app`。
2.  **右键点击** (或 Control+点击) 图标，选择 **"打开" (Open)**。
3.  在弹出的警告框中，点击 **"打开"** 按钮。
4.  *此操作仅第一次需要，之后可直接双击运行。*

### 方法 2：系统设置 "仍要打开" (常规方法)
如果您双击打开后被拦截，可以去系统设置里允许：
1.  双击运行应用，关闭“无法打开”的警告弹窗。
2.  打开 **系统设置** -> **隐私与安全性**。
3.  滚动到下方的 **"安全性"** 区域。
4.  找到提示 *"MacMessageBackup" 已被阻止使用...*，点击右侧的 **"仍要打开" (Open Anyway)** 按钮。
5.  在弹出的确认框中输入密码并确认。

### 方法 3：终端修复 (进阶，解决"应用已损坏")
如果上述方法均无效，或提示“应用已损坏”，请使用终端彻底移除隔离标记：
1.  打开 `终端 (Terminal)`。
2.  复制以下命令（**注意最后有一个空格**）：
    ```bash
    sudo xattr -r -d com.apple.quarantine 
    ```
3.  将 `MacMessageBackup.app` 从 Finder 拖入终端窗口。
4.  按回车，输入密码并确认。

---

### "完全磁盘访问权限" (Full Disk Access)
iMessage (`chat.db`) 和通话记录数据库属于 macOS 的核心隐私数据，受系统严格保护（SIP）。应用必须获得 **完全磁盘访问权限** 才能读取这些数据。

*   **为什么需要？**：没有此权限，应用只能看到空文件夹，无法读取任何短信或通话记录。
*   **如何授权？**：
    1.  应用首次启动时会弹出提示窗口，点击 "Open System Settings"。
    2.  或者手动前往：`系统设置` -> `隐私与安全性` -> `完全磁盘访问权限`。
    3.  点击 `+` 号，添加 `MacMessageBackup` 并开启开关。
*   **权限范围**：应用**只读**取 `~/Library/Messages` 和 `~/Library/CallHistory` 目录，绝不会修改您的任何系统数据。

### 3. 数据安全与网络
*   **本地运行**：应用的所有逻辑均在本地运行。
*   **无中间服务器**：应用直接通过 IMAP/SMTP 协议连接 `imap.gmail.com` 和 `smtp.gmail.com`，**不经过**任何第三方的中转服务器。
*   **密码安全**：您的 Gmail 密码（App Password）经过加密存储在 macOS 本地的 **钥匙串 (Keychain)** 中，只有本应用可以访问。

## ⚠️ 风险提示

1.  **请使用 "应用专用密码" (App Password)**：
    *   为了安全，**切勿**直接使用您的 Gmail 主密码。
    *   请前往 [Google 账户设置](https://myaccount.google.com/security) -> "两步验证" -> "应用专用密码"，生成一个 16 位的独立密码供本应用使用。
    *   这样不仅更安全，也避免了因两步验证导致的登录失败。
2.  **数据备份**：
    *   虽然本应用是“只读”操作，不会删除本地数据，但进行任何批量操作前，建议您确认 Time Machine 备份正常。
3.  **单向备份**：
    *   本工具主要用于**归档**（上传到 Gmail）。虽然支持备份到日历，但目前不支持从 Gmail *还原* 回手机（那是 iOS 系统限制的）。

## 隐私声明

本项目秉持 **"Your Data, Your Control"** 原则：
*   **不收集**任何用户数据、行为日志或崩溃报告。
*   **不联网**（除了直连 Gmail 服务器）。
*   源代码完全开源，欢迎审查代码逻辑。

## 许可证

MIT License
