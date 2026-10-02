//
//  BlockingDemo.swift
//  MainActor
//
//  对应文档 §6.3、§6.4、§6.17、§13：哪些写法会把耗时工作留在主线程。
//  本工程开启了 Default Actor Isolation = MainActor 与 Approachable Concurrency。
//

import SwiftUI

struct BlockingDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "阻塞 vs 挂起",
            summary: """
            每个按钮做 2 秒工作。观察下方图标：停止转动 = 主线程被阻塞。
            日志中绿色 main 表示工作在主线程上执行。
            """,
            console: console
        ) {
            Spinner()

            DemoButton(title: "❌ Thread.sleep(2s) 在主线程", note: "阻塞主线程") {
                blockMainThread()
            }
            DemoButton(title: "❌ Task { 同步计算 }", note: "Task 继承 MainActor，计算仍在主线程") {
                taskInheritingMainActor()
            }
            DemoButton(title: "❌ await nonisolated(nonsending) 函数", note: "nonsending 在调用方（MainActor）上执行") {
                callNonsending()
            }
            DemoButton(title: "✅ await @concurrent 函数", note: "切到后台线程池，返回后回到 MainActor") {
                callConcurrent()
            }
            DemoButton(title: "✅ Task.detached { 同步计算 }", note: "不继承 actor，在后台执行") {
                detached()
            }
            DemoButton(title: "✅ DispatchQueue.global → main.async", note: "GCD 经典写法") {
                gcdGlobal()
            }
            DemoButton(title: "✅ await Task.sleep(2s)", note: "挂起而非阻塞：主线程空闲") {
                taskSleep()
            }
        }
    }

    private func blockMainThread() {
        console.log("主线程 Thread.sleep(2s) 开始")
        Thread.sleep(forTimeInterval: 2)
        console.log("Thread.sleep 结束")
    }

    private func taskInheritingMainActor() {
        let console = console
        Task {
            console.log("Task { } 开始同步计算")
            let n = Work.spin(seconds: 2)
            console.log("Task { } 计算完成（\(n) 次迭代）")
        }
    }

    private func callNonsending() {
        let console = console
        Task {
            console.log("调用 nonsending 函数前")
            let n = await Work.spinNonsending(seconds: 2, console: console)
            console.log("nonsending 返回（\(n) 次迭代）")
        }
    }

    private func callConcurrent() {
        let console = console
        Task {
            console.log("调用 @concurrent 函数前")
            let n = await Work.spinConcurrent(seconds: 2, console: console)
            console.log("@concurrent 返回，已回到 MainActor（\(n) 次迭代）")
        }
    }

    private func detached() {
        let console = console
        Task.detached {
            console.log("Task.detached 开始同步计算")
            let n = Work.spin(seconds: 2)
            await MainActor.run { console.log("MainActor.run 回到主线程（\(n) 次迭代）") }
        }
    }

    private func gcdGlobal() {
        let console = console
        DispatchQueue.global(qos: .userInitiated).async {
            console.log("DispatchQueue.global 开始计算")
            let n = Work.spin(seconds: 2)
            DispatchQueue.main.async { console.log("DispatchQueue.main.async 回到主线程（\(n) 次迭代）") }
        }
    }

    private func taskSleep() {
        let console = console
        Task {
            console.log("await Task.sleep(2s) 开始（挂起）")
            try? await Task.sleep(for: .seconds(2))
            console.log("Task.sleep 结束，恢复执行")
        }
    }
}

/// 由主线程逐帧驱动的旋转图标：主线程一旦被阻塞就会停转
private struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 180))
                Text(context.date.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2))))
                    .font(.title3.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NavigationStack { BlockingDemo() }
}
