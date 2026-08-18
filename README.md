# iosm3u8 — iPad M3U8 下载器

复刻 [`@lzwme/m3u8-dl`](https://github.com/lzwme/m3u8-dl) WebUI 功能的原生 iPadOS 应用：
多线程 TS 下载、AES-128 解密、断点续传、TS 合并、可选转 MP4、任务管理、抖音/微博/皮皮虾链接解析、边下边播、密码保护。

- **技术栈**：SwiftUI + SwiftData + URLSession + AVKit + CommonCrypto +（可选）ffmpeg-kit-ios
- **最低系统**：iPadOS 17.0（SwiftData / @Observable / navigationDestination(item:)）
- **工程生成**：XcodeGen（`project.yml`）

## 功能

| 模块 | 功能 |
|------|------|
| 下载 | 多线程分片下载、AES-128 解密（含密钥轮换）、失败重试（指数退避）、`.part` 断点续传、流式写入、重启自动恢复分片与进度 |
| 管理 | 任务增删改、批量操作（暂停/恢复/删除）、搜索过滤、实时进度与速度、日志、分片状态 |
| 解析 | 抖音/微博/皮皮虾分享链接解析、任意网页 m3u8 自动提取、多码率选择 |
| 播放 | 边下边播（合并文件增长跟随）、倍速（0.5–2x）、全屏、画中画 |
| 配置 | 线程数、并发任务数、保存目录、Headers、分片过滤正则、重试次数、密码保护（Keychain + Face ID） |
| 后台 | BGTaskScheduler 后台续传、启动自动续传 |

## 目录结构

```
iosm3u8/
├─ project.yml              # XcodeGen 工程定义（唯一工程源，xcodeproj 由它生成）
├─ iosm3u8/
│  ├─ App/                  # 入口（模型容器、锁屏）、AppDelegate（后台任务注册）
│  ├─ Models/               # SwiftData：DownloadTask（状态机/分片/密钥/变体）、AppConfig
│  ├─ Core/
│  │  ├─ M3U8Parser.swift   # master/media 列表解析、相对 URL、KEY/IV（含轮换）、BYTERANGE、过滤
│  │  ├─ StreamingDownloader.swift  # 流式下载、Range 续传、BYTERANGE
│  │  ├─ AESDecrypter.swift # CommonCrypto AES-128-CBC、跨块 IV 链、PKCS7、序号派生 IV
│  │  ├─ TSMerger.swift     # 增量按序合并（边下边播）
│  │  ├─ TaskEngine.swift   # 单任务引擎：解析→并发下载→解密→合并
│  │  ├─ DownloadManager.swift     # 单例：CRUD、批量、并发上限、自动/后台续传、转码收尾
│  │  ├─ FFmpegKitBridge.swift     # TS→MP4 转封装（可选依赖，未集成自动降级）
│  │  ├─ AsyncSemaphore.swift      # 并发信号量
│  │  └─ BackgroundTaskManager.swift # BGTaskScheduler 后台续传
│  ├─ Network/              # HTTPClient（重定向追踪）、抖音/微博/皮皮虾解析、通用网页提取
│  ├─ Playback/             # PlayerModel（边下边播/倍速/画中画）、PlayerView、控制条
│  ├─ Views/                # 侧边栏、任务卡片/列表/详情、新建弹窗、解析页、设置、锁屏
│  ├─ Utilities/            # FileManager 扩展、Keychain、密码管理、格式化
│  └─ Resources/            # Info.plist（ATS/文件共享/后台模式）、Assets
├─ iosm3u8Tests/            # M3U8Parser / AESDecrypter / TSMerger 纯逻辑单测
└─ Frameworks/              # FFmpegKit.xcframework（按需下载，不入库）
```

## 构建步骤（macOS + Xcode 16）

```bash
# 1. 安装 XcodeGen（若已安装可跳过）
brew install xcodegen

# 2. 下载 ffmpeg-kit 二进制（可选，跳过则无法转 MP4）
#    官方仓库 https://github.com/arthenica/ffmpeg-kit 已于 2025-01 停止维护，
#    但仍可从其 Releases 页面下载 iOS 版本（推荐 https 包，体积较小）。
#    解压后将 FFmpegKit.xcframework 放到：
mkdir -p Frameworks
#    （把解压出的 FFmpegKit.xcframework 复制到 Frameworks/ 目录）

# 3. 生成 Xcode 工程（若未放 ffmpeg-kit，先删除 project.yml 中
#    dependencies 下的 framework 块再执行）
xcodegen generate

# 4. 打开工程，设置签名团队后运行
open iosm3u8.xcodeproj
```

> 说明：`iosm3u8.xcodeproj` 由 `xcodegen generate` 生成（已加入 .gitignore），
> 修改工程配置请改 `project.yml` 后重新生成；Info.plist 为手工维护文件。

### 运行单元测试

Xcode 菜单 `Product ▸ Test`（⌘U），或命令行：

```bash
xcodebuild test -project iosm3u8.xcodeproj -scheme iosm3u8 -destination 'platform=iPadOS Simulator,name=iPad Pro 13-inch (M4)'
```

覆盖：M3U8 解析（相对 URL/密钥/密钥轮换/多码率/BYTERANGE/过滤）、AES 加解密与跨块流式解密、TS 按序合并/续传。

## 关键设计说明

- **沙盒与文件共享**：任务产物在 `Documents/<保存目录>/<任务ID>/` 下；Info.plist 已开启
  `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，可在「文件」App 中访问；
  分享/导出用系统 ShareLink（Activity View）。
- **ATS**：`NSAllowsArbitraryLoads` 已开启以支持 http 源；`NSAllowsLocalNetworking` 兼容内网。
- **断点续传**：分片先写 `.part`，恢复时按已有大小发 `Range` 请求续传（服务器不支持 Range
  时自动截断重写）；已完成的 `.ts` 分片直接跳过；合并文件缺失时自动重建。
- **边下边播**：分片按序完成即追加进 `merged.ts`；播放器检测到文件增长且播放到当前末尾时
  自动重建 AVPlayerItem 继续播放。
- **后台下载**：前台使用常规 URLSession；进入后台由 BGTaskScheduler（约 15 分钟起，系统调度）
  唤醒续传。iOS 对后台时间有硬性限制，长任务请保持前台或频繁打开 App 触发续传。
- **密码保护**：密码以「盐::SHA-256」形式存于 Keychain，不落明文；可选 Face ID / Touch ID 解锁。
- **AES-128**：IV 优先取 `#EXT-X-KEY` 的 IV 属性，否则按分片序号（12 字节零 + 4 字节大端）派生；
  解密为跨块 CBC 链 + PKCS7 剥离，流式进行不占内存。支持密钥轮换：每个分片记录其生效的
  `#EXT-X-KEY`（含 `METHOD=NONE` 切回明文），按分片取对应密钥解密。

## 常见问题

- **App 图标警告**：`Assets.xcassets/AppIcon.appiconset` 未放置 1024×1024 PNG，构建会告警，
  放入图标后重新构建即可。
- **MP4 转换不可用**：`设置 ▸ 关于` 显示「未集成」时，按上面步骤 2 添加 FFmpegKit.xcframework
  并重新 `xcodegen generate`；未集成时任务自动降级为 TS 输出，不影响下载。
- **首次运行报签名错误**：在 Xcode 的 `Signing & Capabilities` 中选择你的开发者团队。
- **后台续传不生效**：确认在系统「设置 ▸ 通用 ▸ 后台 App 刷新」中允许本 App；模拟器上
  BGTask 需手动触发（`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.m3u8dl.iosm3u8.refresh"]`）。
