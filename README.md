# Swift / SwiftUI 多任务与并发全景指南

MainActor、DispatchQueue、RunLoop、Task、GCD、OperationQueue、actor 等概念的区别与调度时机，附交互动画、四篇 Swift 并发资料（两场 WWDC 讲座、两篇文章）的阅读笔记，以及一个可运行的 iOS 演示工程。

## 在线查看

👉 **<https://jeffery812.github.io/MainActor/>**

指南是一个单文件网页 [`index.html`](index.html)，通过 GitHub Pages 发布。在 GitHub 上直接点开 `index.html` 只会看到源码，不会渲染页面，请使用上面的链接。

网页分五个页面，用侧栏顶部的切换器切换，每个页面都有自己的地址：

| 页面 | 地址 | 内容 |
|---|---|---|
| 并发全景指南 | [`#guide`](https://jeffery812.github.io/MainActor/#guide) | 主体指南，见下文 |
| WWDC25 · 268 拥抱 Swift 并发 | [`#wwdc25-268`](https://jeffery812.github.io/MainActor/#wwdc25-268) | [Embrace Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/) 视频笔记：从单线程到异步、`@concurrent`、Sendable、actor 的四个阶段，推荐的构建设置。3 个交互动画 |
| WWDC23 · 10170 结构化并发进阶 | [`#wwdc23-10170`](https://jeffery812.github.io/MainActor/#wwdc23-10170) | [Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/) 视频笔记：任务树带来的自动取消、优先级传播、task-local 值，任务组限流与 `withDiscardingTaskGroup`，服务端日志与分布式追踪。3 个交互动画 |
| 迁移到 Swift 6 | [`#swift6-migration`](https://jeffery812.github.io/MainActor/#swift6-migration) | Kodeco 教程 [Migrating to Swift 6](https://www.kodeco.com/48297451-migrating-to-swift-6-tutorial) 要点：隔离域、两条迁移路线、逐条消除诊断、隔离的协议遵循。3 个交互动画 |
| Swift 6.2 并发初探 | [`#swift62-changes`](https://jeffery812.github.io/MainActor/#swift62-changes) | SwiftLee 文章 [Swift 6.2 concurrency changes](https://www.avanderlee.com/concurrency/swift-6-2-concurrency-changes/) 要点：SE-0466、SE-0461，文中例子在六种编译设置下的本机实测 |

另有一个单独的网页 [`MainActor.html`](MainActor.html)：演示工程逐页导读，👉 **<https://jeffery812.github.io/MainActor/MainActor.html>**。侧栏切换器底部的「演示工程导读 ↗」也链接到它，详见下文[演示工程](#演示工程)。

还有一份自测卷 [`quiz.html`](quiz.html)：从指南和导读中挑出 30 道题（27 道单选、3 道多选），每题附解析和原文出处，引用的工程代码都附了原文。分练习（选完即判）和考试（交卷后判）两种模式，进度保存在浏览器里。👉 **<https://jeffery812.github.io/MainActor/quiz.html>**。侧栏切换器和导读侧栏都有入口。

并发全景指南的内容：

- 各概念的说明、对比表和代码示例
- **现状**：哪些 API 推荐、按需使用、属于遗留或应该避免
- 6 个交互动画：RunLoop Mode 与滚动、调度时机回放、阻塞 vs 挂起、线程爆炸 vs 协作式线程池、结构化并发与取消、actor 重入
- 在 iPhone 17 Pro 模拟器上的实测数据
- `Task {}` 闭包与 nonisolated async 函数隔离继承的对比实验（§7.3）
- `nonisolated` 用法大全（§9.3）：`nonisolated`、`nonisolated(nonsending)`、`@concurrent`、`nonisolated(unsafe)` 各写法的含义与选择，同步函数加 `nonisolated` 改变的是"谁能直接调用"而不是在哪个线程运行，以及常见误区

两个 WWDC 页和 Kodeco 页的示例代码是根据原文描述重建的示意，页面上已注明；SwiftLee 页引用的是原文代码；视频 transcript 保存在 [`wwdc2025-268.txt`](wwdc2025-268.txt) 和 [`wwdc2023-10170.txt`](wwdc2023-10170.txt)。

支持明暗主题切换和手机浏览。

## 本地查看

```bash
git clone git@github.com:jeffery812/MainActor.git
open MainActor/index.html
```

直接用浏览器打开 `index.html` 即可，不需要本地服务器。字体从 Google Fonts 加载，离线时会退回系统字体。

## 在自己的 fork 上发布

1. 打开仓库的 **Settings → Pages**
2. **Source** 选择 **Deploy from a branch**
3. **Branch** 选择 `main`，目录选择 `/ (root)`，点 **Save**
4. 一两分钟后即可访问 `https://<用户名>.github.io/<仓库名>/`

GitHub Pages 会把根目录的 `index.html` 作为首页。之后每次推送到 `main`，网站都会自动更新。

## 演示工程

`MainActor.xcodeproj` 是一个 SwiftUI App（iOS 26，Xcode 26），用 13 个页面演示指南里的概念。除第 13 页是可视化演示外，每个页面都会记录代码执行时所在的线程和时间：

| 页面 | 文件 |
|---|---|
| 执行时机 | `MainActor/Demos/OrderingDemo.swift` |
| 阻塞 vs 挂起 | `MainActor/Demos/BlockingDemo.swift` |
| RunLoop Mode 与滚动 | `MainActor/Demos/RunLoopModeDemo.swift` |
| Task 继承了什么 | `MainActor/Demos/TaskInheritanceDemo.swift` |
| 结构化并发 | `MainActor/Demos/StructuredConcurrencyDemo.swift` |
| actor 串行与重入 | `MainActor/Demos/ActorReentrancyDemo.swift` |
| 桥接旧 API | `MainActor/Demos/BridgingDemo.swift` |
| GCD 工具箱 | `MainActor/Demos/GCDToolsDemo.swift` |
| OperationQueue | `MainActor/Demos/OperationQueueDemo.swift` |
| 数据竞争与锁 | `MainActor/Demos/DataRaceDemo.swift` |
| `.task` 与生命周期 | `MainActor/Demos/SwiftUITaskDemo.swift` |
| AsyncSequence vs Combine | `MainActor/Demos/AsyncSequenceCombineDemo.swift` |
| TimelineView | `MainActor/Demos/TimelineViewDemo.swift` |

工程开启了 *Default Actor Isolation = MainActor* 与 *Approachable Concurrency*，`SWIFT_VERSION` 为 5.0（Swift 6.2 编译器，未启用 Swift 6 语言模式）。用 Xcode 打开工程，选择 iOS 模拟器运行即可。

### 逐页导读

[`MainActor.html`](MainActor.html)（在线：<https://jeffery812.github.io/MainActor/MainActor.html>）解释每个演示**为什么这样写**：

- 编译设置如何决定代码默认在哪个线程上运行，以及满屏的 `nonisolated` 从何而来
- 反复出现的 `let console = console`（C1–C9）：为什么加了这一行，后台闭包里就不需要 `await`；新变量是拷贝还是引用；MainActor 隔离的类为什么自动是 `Sendable`；另一种写法捕获列表 `[console]`；实际项目里推荐哪种写法
- 13 个演示逐一拆解：看什么、控制变量是什么、关键代码和看似多余的写法为什么必不可少
- 日志系统 `Console` / `LogBuffer` 深读：「MainActor 隔离的类」到底是什么意思（哪些成员归主线程、编译期与运行期各保证什么、常见误解），`Sendable`、`nonisolated let`、`Mutex`、`ContinuousClock`，以及 Mutex 与主线程的四个追问（为什么不需要 `await`、主线程能否用锁、持锁太久怎么办、调用方不知道里面有锁怎么办）
- 4 个交互示意：阻塞 vs 挂起、3 个线程同时写日志（有无 Mutex）、三种时钟测时长（`Date` / `ContinuousClock` / `SuspendingClock`）、主线程等锁时的掉帧时间线
