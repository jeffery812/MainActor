//
//  StructuredConcurrencyDemo.swift
//  MainActor
//
//  对应文档 §7.5、§7.6、§7.7：顺序 await / async let / TaskGroup / 限流 / 错误导致的取消。
//

import SwiftUI

nonisolated enum DemoError: Error {
    case failed(String)
}

nonisolated enum FakeAPI {
    /// 模拟网络请求：挂起指定时间，可以选择失败
    static func fetch(_ name: String, seconds: Double, console: Console, fail: Bool = false) async throws -> String {
        console.log("▶︎ \(name) 开始")
        do {
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        } catch {
            console.log("✖︎ \(name) 被取消")
            throw error
        }
        if fail {
            console.log("💥 \(name) 抛出错误")
            throw DemoError.failed(name)
        }
        console.log("✔︎ \(name) 完成")
        return name
    }
}

struct StructuredConcurrencyDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "结构化并发",
            summary: """
            三个 1 秒的请求：顺序 await 约 3 秒，async let 约 1 秒。
            TaskGroup 演示动态数量的并行、限制并发数，以及一个子任务失败时其余子任务被自动取消。
            """,
            console: console
        ) {
            DemoButton(title: "顺序 await", note: "一个接一个，约 3s") { run(sequential) }
            DemoButton(title: "async let", note: "并行，约 1s") { run(asyncLet) }
            DemoButton(title: "TaskGroup 限流", note: "8 个任务，最多同时 3 个，约 3s") { run(limitedGroup) }
            DemoButton(title: "ThrowingTaskGroup 出错", note: "一个子任务失败 → 其余被取消") { run(failingGroup) }
        }
    }

    private func run(_ experiment: @escaping (Console) async -> Void) {
        let console = console
        console.clear()
        Task {
            let elapsed = await ContinuousClock().measure { await experiment(console) }
            console.log("⏱ 总耗时 \(elapsed.msText)")
        }
    }

    private func sequential(_ console: Console) async {
        _ = try? await FakeAPI.fetch("用户", seconds: 1, console: console)
        _ = try? await FakeAPI.fetch("订单", seconds: 1, console: console)
        _ = try? await FakeAPI.fetch("通知", seconds: 1, console: console)
    }

    private func asyncLet(_ console: Console) async {
        async let user = FakeAPI.fetch("用户", seconds: 1, console: console)
        async let orders = FakeAPI.fetch("订单", seconds: 1, console: console)
        async let notices = FakeAPI.fetch("通知", seconds: 1, console: console)
        _ = try? await (user, orders, notices)
    }

    private func limitedGroup(_ console: Console) async {
        let jobs = (1...8).map { "任务\($0)" }
        let maxConcurrent = 3

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0..<maxConcurrent where next < jobs.count {
                let job = jobs[next]
                next += 1
                group.addTask { _ = try? await FakeAPI.fetch(job, seconds: 1, console: console) }
            }
            // 每完成一个，再补一个，保证在途任务不超过 maxConcurrent
            while await group.next() != nil {
                if next < jobs.count {
                    let job = jobs[next]
                    next += 1
                    group.addTask { _ = try? await FakeAPI.fetch(job, seconds: 1, console: console) }
                }
            }
        }
    }

    private func failingGroup(_ console: Console) async {
        do {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await FakeAPI.fetch("A（2s）", seconds: 2, console: console) }
                group.addTask { try await FakeAPI.fetch("B（2s）", seconds: 2, console: console) }
                group.addTask { try await FakeAPI.fetch("C（0.5s 后失败）", seconds: 0.5, console: console, fail: true) }
                for try await name in group {
                    console.log("收到结果：\(name)")
                }
            }
        } catch {
            console.log("TaskGroup 抛出：\(error)")
        }
    }
}

#Preview {
    NavigationStack { StructuredConcurrencyDemo() }
}
