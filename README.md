# Swift / SwiftUI 多任务与并发全景指南

MainActor、DispatchQueue、RunLoop、Task、GCD、OperationQueue、actor 等概念的区别与调度时机，附 6 个交互动画，以及一个可运行的 iOS 演示工程。

## 在线查看

👉 **<https://jeffery812.github.io/MainActor/>**

指南是一个单文件网页 [`index.html`](index.html)，通过 GitHub Pages 发布。在 GitHub 上直接点开 `index.html` 只会看到源码，不会渲染页面，请使用上面的链接。

页面内容：

- 各概念的说明、对比表和代码示例
- **现状**：哪些 API 推荐、按需使用、属于遗留或应该避免
- 6 个交互动画：RunLoop Mode 与滚动、调度时机回放、阻塞 vs 挂起、线程爆炸 vs 协作式线程池、结构化并发与取消、actor 重入
- 在 iPhone 17 Pro 模拟器上的实测数据

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

`MainActor.xcodeproj` 是一个 SwiftUI App（iOS 26，Xcode 26），用 11 个页面演示指南里的概念，每个页面都会记录代码执行时所在的线程和时间：

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

工程开启了 *Default Actor Isolation = MainActor* 与 *Approachable Concurrency*，`SWIFT_VERSION` 为 5.0（Swift 6.2 编译器，未启用 Swift 6 语言模式）。用 Xcode 打开工程，选择 iOS 模拟器运行即可。

`MainActor_DispatchQueue_RunLoop.pdf` 是早期版本的导出，内容不如在线页面新，请以网页为准。
