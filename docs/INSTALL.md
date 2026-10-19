# 安装与首次使用 / Installation

[中文README](../README.zh-CN.md) · [English README](../README.md)

## 中文

### 下载安装

从 [Releases](https://github.com/jaysoncbh/MilkFamily/releases/tag/v1.0.0) 打开 **v1.0.0**，在 **Assets** 中下载：

**`MilkFamily-1.0.0-macOS-arm64.zip`**

这个ZIP内包含 **`奶家族.app`**，人物、卡片、道具和动画已内置。普通安装不需要源码、Swift、Python、API Key或单独的运行素材包。

1. 电脑需要 **macOS 14及以上、Apple Silicon / M系列芯片**。当前仅提供已在本机核对的arm64版本，Intel版本尚未提供。
2. 双击下载的ZIP解压。
3. 把解压得到的 `奶家族.app` 拖入Finder侧边栏的 **应用程序（Applications）**；也可存入个人的 `~/Applications/`。
4. 从应用程序中双击打开奶家族；系统拦截未公证应用时，参照下面的首次打开说明。
5. 默认界面为英文，需要中文时打开 **Settings → Language → 中文**。
6. 选择一位普通伙伴，然后去 **Shop / 小铺** 手动领取待机卡，开始成长。
7. 软件每15秒读取本机Codex和Claude Code日志。已有历史用于统计；完成初始设置后的新增用量才推动养成。若未找到日志，在设置中选择对应日志文件夹并刷新。

### 首次打开：未公证应用

**v1.0.0采用临时签名，未经过Apple公证。** 如果macOS提示无法验证开发者，只有在确认来自本仓库、校验文件完整性且决定信任该App时，才按以下步骤打开：

1. 先尝试打开一次App。
2. 到 **系统设置 → 隐私与安全性**，找到该App的提示，点击 **仍要打开 / Open Anyway**。
3. 在随后提示中确认打开。此操作仅为该App建立例外。

步骤依据[Apple官方说明](https://support.apple.com/en-us/102445)。如果系统报告恶意软件、文件损坏或管理员策略限制，不使用上述方式绕过；请反馈具体提示。签名和外部验收状态见[检查表](RELEASE_CHECKLIST.md)。

### 选择哪个附件

| 文件 | 用途 |
| --- | --- |
| `MilkFamily-1.0.0-macOS-arm64.zip` | 普通用户安装的正式版App。 |
| `MilkFamily-Test-1.0.0-macOS-arm64.zip` | 带样卡与开发测试工具的测试版，数据目录与正式版分开。 |
| `MilkFamily-Source-1.0.0.zip` 或 GitHub的 `Source code` | 开发源码，不能像App一样直接打开使用。 |
| `MilkFamily-RuntimeAssets-1.0.0.zip` | 从源码复建时使用的单独运行素材；普通App安装不需要再下载。 |

### 更新与卸载

更新时，退出旧版，把新的同名App替换到原安装位置，再打开。升级前可以备份进度；保留下面的数据目录即可沿用伙伴、收藏和设置。不要用删除进度的方式更新。

- 正式版进度：`~/Library/Application Support/奶家族/`
- 测试版进度：`~/Library/Application Support/奶家/`

卸载时退出App，再从应用程序中移走对应App。数据目录默认保留；确认不再需要存档后可自行删除。源Codex和Claude Code日志不受卸载影响。完整数据说明见[使用与隐私](使用与隐私说明.md)。

### 常见问题

| 情况 | 处理方式 |
| --- | --- |
| 没看到App附件 | 展开Releases中的Assets；源码ZIP不是安装包。 |
| 电脑无法运行当前版本 | 核对macOS版本与芯片；当前发布包为arm64。 |
| macOS提示开发者无法验证 | 本版未公证，参照上面的首次打开说明。 |
| 解压失败或文件不完整 | 重新下载；可用发行页的SHA-256校验值核对完整性。 |
| 用量为0 | 先确认本机已有Codex / Claude Code用量日志，再在设置选择目录。没有记录的用量不会补造。 |
| 成年奶娃不在初始选择里 | 他是稀有伙伴（图鉴名成年奶蛙，A201），通过孵化获得；初始自选为普通伙伴。 |

## English

### Install the app

Open [v1.0.0 Releases](https://github.com/jaysoncbh/MilkFamily/releases/tag/v1.0.0), expand **Assets**, and choose **`MilkFamily-1.0.0-macOS-arm64.zip`**.

1. Use an **Apple Silicon / M-series Mac with macOS 14 or later**. Intel builds are not available yet.
2. Double-click the ZIP to extract **`奶家族.app`**.
3. Drag the app into **Applications** in Finder, or your personal `~/Applications/` folder.
4. Open it from Applications. If macOS blocks this unnotarized app, follow the first-launch instructions below.
5. English is the default. To switch languages, open **Settings → Language**.
6. Choose a Common starter, then claim its idle card in **Shop**.
7. Local Codex and Claude Code logs sync every 15 seconds. Choose a log folder in Settings if discovery finds none. Existing history appears in stats; newly observed usage after setup earns growth.

The regular app already contains its characters, cards and animations. **You do not need a compiler, source code, API key or separate asset pack to install it.** **v1.0.0 is ad-hoc signed and has not been notarized by Apple.** If macOS cannot verify the developer, confirm the download source and checksum first. If you choose to trust this app, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**, and confirm the per-app exception. See [Apple’s instructions](https://support.apple.com/en-us/102445). Do not override malware, corruption or administrator-policy blocks; report the exact message instead.

### Pick the right archive

- `MilkFamily-…-macOS-arm64.zip`: regular app for end users.
- `MilkFamily-Test-…-macOS-arm64.zip`: test edition, with Samples and testing tools and a separate data directory.
- `MilkFamily-Source-…zip` or GitHub’s `Source code`: developer sources, not an installable app.
- `MilkFamily-RuntimeAssets-…zip`: separate authorized artwork for a source build; not required when installing the regular app.

### Update, uninstall and troubleshoot

Quit the old app before replacing it with the new app in the same location. Keep the local data directories to retain progress: regular edition uses `~/Library/Application Support/奶家族/`; test edition uses `~/Library/Application Support/奶家/`.

To uninstall, quit and remove the app. Saved progress stays in its data directory until you choose to delete it; source Codex / Claude Code logs are unaffected. See [Usage and privacy](Usage_and_Privacy.md).

Expand Assets on the release page to find the app ZIP. If macOS cannot run the app, check the OS version and architecture. For developer-verification messages, check that release’s signing/notarization status and report the exact message; independent clean-Mac download acceptance is not complete. For a damaged download, download again and compare its SHA-256 with the release checksum.

Zero usage means no supported usage has been read yet: verify local logs and choose their folder in Settings. Adult Milk Frog (成年奶娃 / 成年奶蛙, A201) is a Rare companion found through hatching; only Common companions appear in the initial starter selection.
