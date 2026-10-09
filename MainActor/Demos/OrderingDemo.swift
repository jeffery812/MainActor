//
//  OrderingDemo.swift
//  MainActor
//
//  对应文档 §11.3、§12.1、§12.2：各种"切到主线程 / 安排稍后执行"的方式的执行时机。
//

import SwiftUI

struct OrderingDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "执行时机",
            summary: """
            在主线程同步代码里用不同方式"安排"代码，观察真实的执行顺序与线程。
            • 「1 → Task.immediate → 2 → 3」一定最先：它们都在当前同步代码中执行。
            • main.async / Task {} / RunLoop.perform / OperationQueue.main 都要等当前代码返回后才执行，相互顺序不应依赖。
            • detached / global 在后台线程，可能出现在任何位置（甚至在 2 之前）。
            """,
            console: console
        ) {
            DemoButton(title: "从同步上下文调度", note: "按钮回调本身运行在 MainActor 上") {
                scheduleFromSyncContext()
            }
            DemoButton(title: "从 MainActor 的 async 上下文调度", note: "await 是潜在挂起点：已排队的任务可能插队到 B 之前") {
                Task { await scheduleFromAsyncContext() }
            }
        }
    }

    private func scheduleFromSyncContext() {
        let console = console
        console.clear()
        console.log("1 同步代码开始")

        DispatchQueue.main.async { console.log("DispatchQueue.main.async") }
        Task { console.log("Task { }（继承 MainActor，入队）") }
        Task.immediate { console.log("Task.immediate（立即同步开始执行）") }
        RunLoop.main.perform { console.log("RunLoop.main.perform") }
        OperationQueue.main.addOperation { console.log("OperationQueue.main.addOperation") }
        Task.detached { console.log("Task.detached（不继承 actor → 后台）") }
        DispatchQueue.global().async { console.log("DispatchQueue.global().async（后台）") }

        mainActorSyncFunction(console)
        console.log("3 同步代码结束")
    }

    private func mainActorSyncFunction(_ console: Console) {
        console.log("2 调用 @MainActor 同步函数（直接执行，不排队）")
    }

    private func scheduleFromAsyncContext() async {
        let console = console
        console.clear()
        console.log("A 在 MainActor 的 async 函数中")

        Task { @MainActor in console.log("Task { @MainActor }（入队，稍后执行）") }
        DispatchQueue.main.async { console.log("DispatchQueue.main.async（入队，稍后执行）") }

        // 即使已经在 MainActor 上，await 仍是潜在挂起点：上面排队的任务可能先于 B 执行
        await MainActor.run { console.log("B await MainActor.run") }
        console.log("C MainActor.run 返回后")

        try? await Task.sleep(for: .milliseconds(10))
        console.log("D await Task.sleep 之后")
    }
}

#Preview {
    NavigationStack { OrderingDemo() }
}
