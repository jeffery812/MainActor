//
//  TaskInheritanceDemo.swift
//  MainActor
//
//  对应文档 §6.3、§6.4、§6.8、§6.10、§10.2：
//  Task / Task.detached / DispatchQueue.global / async let / TaskGroup 分别继承了什么。
//

import SwiftUI

nonisolated enum TraceContext {
    @TaskLocal static var traceID = "无"
}

nonisolated extension TaskPriority {
    var name: String {
        switch self {
        case .high: "high(userInitiated)"
        case .medium: "medium"
        case .low: "low(utility)"
        case .background: "background"
        default: "raw(\(rawValue))"
        }
    }
}

struct TaskInheritanceDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "Task 继承了什么",
            summary: """
            同一段代码分别用 Task {}、Task.detached、DispatchQueue.global、async let、TaskGroup 启动，比较：
            actor 隔离（在哪个线程）、优先级、TaskLocal、父任务取消时是否被取消。
            """,
            console: console
        ) {
            DemoButton(title: "① actor 隔离 / 执行线程", note: "从 MainActor 上下文启动") { isolation() }
            DemoButton(title: "② 优先级", note: "父任务 priority: .low") { priority() }
            DemoButton(title: "③ TaskLocal", note: "在 withValue 作用域内启动") { taskLocal() }
            DemoButton(title: "④ 取消传播", note: "300ms 后取消父任务") { cancellation() }
        }
    }

    private func isolation() {
        let console = console
        console.clear()
        console.log("按钮回调（MainActor）")

        Task { console.log("Task { }：继承 MainActor → 主线程") }
        Task.detached { console.log("Task.detached：不继承 → 后台线程") }
        DispatchQueue.global().async { console.log("DispatchQueue.global：GCD 线程池") }

        Task {
            async let child: Void = console.log("async let 子任务：在并发执行器上")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { console.log("TaskGroup.addTask 子任务：在并发执行器上") }
            }
            await child
        }
    }

    private func priority() {
        let console = console
        console.clear()

        Task(priority: .low) {
            console.log("父 Task(priority: .low)：\(Task.currentPriority.name)")
            Task { console.log("Task { }：\(Task.currentPriority.name)（继承）") }
            Task.detached { console.log("Task.detached：\(Task.currentPriority.name)（不继承）") }
            async let child: Void = console.log("async let：\(Task.currentPriority.name)（继承）")
            await child
        }

        DispatchQueue.global(qos: .utility).async {
            let qos = DispatchQoS.QoSClass(rawValue: qos_class_self()).map { "\($0)" } ?? "unknown"
            console.log("GCD 没有 TaskPriority，用 QoS 表示：\(qos)")
        }
    }

    private func taskLocal() {
        let console = console
        console.clear()

        TraceContext.$traceID.withValue("trace-42") {
            console.log("withValue 作用域内：\(TraceContext.traceID)")
            Task { console.log("Task { }：\(TraceContext.traceID)（继承）") }
            Task.detached { console.log("Task.detached：\(TraceContext.traceID)（不继承）") }
            DispatchQueue.global().async { console.log("DispatchQueue.global：\(TraceContext.traceID)（不继承）") }
        }
        console.log("withValue 作用域外：\(TraceContext.traceID)")
    }

    private func cancellation() {
        let console = console
        console.clear()

        let parent = Task {
            let unstructured = Task { await Probe.sleepAndReport("Task { }（非结构化）", console) }
            Task.detached { await Probe.sleepAndReport("Task.detached", console) }
            async let child: Void = Probe.sleepAndReport("async let（结构化）", console)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await Probe.sleepAndReport("TaskGroup 子任务（结构化）", console) }
            }
            await child
            await unstructured.value
        }

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            console.log("⛔️ parent.cancel()")
            parent.cancel()
        }
    }
}

private nonisolated enum Probe {
    static func sleepAndReport(_ label: String, _ console: Console) async {
        do {
            try await Task.sleep(for: .seconds(1))
            console.log("\(label)：正常完成（没有被取消）")
        } catch {
            console.log("\(label)：被取消 ✅")
        }
    }
}

#Preview {
    NavigationStack { TaskInheritanceDemo() }
}
