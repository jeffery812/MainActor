//
//  BridgingDemo.swift
//  MainActor
//
//  对应文档 §7.11、§7.14、§7.15：把回调 / 事件流桥接到 async 世界。
//

import SwiftUI

/// 模拟一个只提供 completion handler 的旧 SDK
nonisolated enum LegacyAPI {
    /// 回调在 GCD 后台线程
    static func fetchProfile(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            completion(.success("Zhihui"))
        }
    }

    /// 回调在主队列（文档保证），但编译器不知道
    static func fetchStatus(completion: @escaping @Sendable (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion("在线")
        }
    }
}

nonisolated enum Bridges {
    /// Continuation：必须且只能 resume 一次
    static func profile(console: Console) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            LegacyAPI.fetchProfile { result in
                console.log("旧 API 回调（GCD 线程）→ continuation.resume")
                continuation.resume(with: result)
            }
        }
    }

    /// AsyncStream：把后台定时器事件包装成异步序列
    static func ticks(count: Int, console: Console) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let ticker = StreamTicker(count: count, console: console, continuation: continuation)
            continuation.onTermination = { reason in
                console.log("onTermination：\(reason)")
                ticker.cancel()
            }
            ticker.start()
        }
    }
}

private nonisolated final class StreamTicker: @unchecked Sendable {
    private let source = DispatchSource.makeTimerSource(queue: .global())
    private var produced = 0

    init(count: Int, console: Console, continuation: AsyncStream<Int>.Continuation) {
        source.schedule(deadline: .now() + 0.3, repeating: .milliseconds(300))
        source.setEventHandler { [unowned self] in
            // DispatchSource 的事件处理在同一个队列上串行执行
            produced += 1
            console.log("生产者 yield(\(produced))")
            continuation.yield(produced)
            if produced == count { continuation.finish() }
        }
    }

    func start() { source.resume() }

    func cancel() { source.cancel() }
}

struct BridgingDemo: View {
    @State private var console = Console()
    @State private var consumer: Task<Void, Never>?
    @State private var status = "-"

    var body: some View {
        DemoScreen(
            title: "桥接旧 API",
            summary: """
            ① Continuation：回调在后台线程，但 await 返回后自动回到 MainActor。
            ② AsyncStream：生产者在后台 yield，消费者用 for await 在 MainActor 上接收；取消消费任务会触发 onTermination。
            ③ MainActor.assumeIsolated：回调已知在主线程时，告诉编译器"我在 MainActor 上"（不在则崩溃）。
            """,
            console: console
        ) {
            DemoButton(title: "① withCheckedThrowingContinuation") { continuation() }
            DemoButton(title: "② AsyncStream 消费 10 个值") { consume() }
            DemoButton(title: "② 取消消费任务", note: "消费过程中点击") {
                consumer?.cancel()
            }
            DemoButton(title: "③ MainActor.assumeIsolated", note: "当前状态：\(status)") { assumeIsolated() }
        }
    }

    private func continuation() {
        let console = console
        console.clear()
        Task {
            console.log("await 前（MainActor）")
            do {
                let name = try await Bridges.profile(console: console)
                console.log("await 返回：\(name)（自动回到 MainActor）")
            } catch {
                console.log("失败：\(error)")
            }
        }
    }

    private func consume() {
        let console = console
        console.clear()
        consumer?.cancel()
        consumer = Task {
            for await value in Bridges.ticks(count: 10, console: console) {
                console.log("消费者收到 \(value)")
            }
            console.log("for await 结束\(Task.isCancelled ? "（任务被取消）" : "（流已 finish）")")
        }
    }

    private func assumeIsolated() {
        let console = console
        console.clear()
        LegacyAPI.fetchStatus { text in
            // 这个闭包是 @Sendable 的，编译器认为它不在 MainActor 上；
            // 但旧 API 保证在主队列回调，所以可以断言隔离后访问 MainActor 状态。
            MainActor.assumeIsolated {
                status = text
                console.log("assumeIsolated 内更新了 @State：\(text)")
            }
        }
    }
}

#Preview {
    NavigationStack { BridgingDemo() }
}
