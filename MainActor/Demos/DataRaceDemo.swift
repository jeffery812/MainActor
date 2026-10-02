//
//  DataRaceDemo.swift
//  MainActor
//
//  对应文档 §1、§4.4、§6.11、§7：数据竞争，以及各种保护方式的结果与耗时。
//

import SwiftUI
import Synchronization

/// ❌ 没有任何保护。@unchecked Sendable 只是让编译器闭嘴，并不会变得线程安全。
private nonisolated final class UnsafeBox: @unchecked Sendable {
    var value = 0
}

private nonisolated final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    func increment() { lock.withLock { _value += 1 } }
    var value: Int { lock.withLock { _value } }
}

private nonisolated final class MutexBox: Sendable {
    private let state = Mutex(0)
    func increment() { state.withLock { $0 += 1 } }
    var value: Int { state.withLock { $0 } }
}

private nonisolated final class AtomicBox: Sendable {
    private let state = Atomic(0)
    func increment() { state.wrappingAdd(1, ordering: .relaxed) }
    var value: Int { state.load(ordering: .relaxed) }
}

private nonisolated final class QueueBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "demo.counter")
    private var _value = 0
    func increment() { queue.sync { _value += 1 } }
    var value: Int { queue.sync { _value } }
}

actor CounterActor {
    private(set) var value = 0
    func increment() { value += 1 }
}

nonisolated enum RaceExperiments {
    static let workers = 4
    static let iterations = 50_000
    static var expected: Int { workers * iterations }

    private static func measure(_ label: String, _ console: Console, _ body: () -> Int) {
        let start = ContinuousClock.now
        let result = body()
        let mark = result == expected ? "✅" : "❌"
        console.log("\(mark) \(label)：\(result)，耗时 \(start.duration(to: .now).msText)")
    }

    /// 用 concurrentPerform 让 4 个线程同时递增
    private static func hammer(_ increment: (Int) -> Void) {
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for _ in 0..<iterations { increment(worker) }
        }
    }

    static func runLocks(_ console: Console) {
        DispatchQueue.global(qos: .userInitiated).async {
            console.log("\(workers) 个线程 × \(iterations) 次 += 1，期望 \(expected)")

            measure("无保护", console) {
                let box = UnsafeBox()
                hammer { _ in box.value += 1 }
                return box.value
            }
            measure("NSLock", console) {
                let box = LockedBox()
                hammer { _ in box.increment() }
                return box.value
            }
            measure("Mutex", console) {
                let box = MutexBox()
                hammer { _ in box.increment() }
                return box.value
            }
            measure("Atomic", console) {
                let box = AtomicBox()
                hammer { _ in box.increment() }
                return box.value
            }
            measure("串行 DispatchQueue.sync", console) {
                let box = QueueBox()
                hammer { _ in box.increment() }
                return box.value
            }
        }
    }

    @concurrent
    static func runActor(_ console: Console) async {
        let counter = CounterActor()
        let start = ContinuousClock.now
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workers {
                group.addTask {
                    for _ in 0..<iterations { await counter.increment() }
                }
            }
        }
        let result = await counter.value
        let mark = result == expected ? "✅" : "❌"
        console.log("\(mark) actor（每次 await 跨隔离调用）：\(result)，耗时 \(start.duration(to: .now).msText)")
    }
}

struct DataRaceDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "数据竞争与锁",
            summary: """
            4 个线程同时对同一个计数器做 += 1。
            无保护时结果通常小于期望值（丢失更新）；其余方式结果正确，但耗时不同。
            actor 每次递增都要 await 跨隔离，开销最大 —— 小而快的同步临界区更适合 Mutex / Atomic。
            """,
            console: console
        ) {
            DemoButton(title: "运行：无保护 / NSLock / Mutex / Atomic / 串行队列") {
                console.clear()
                RaceExperiments.runLocks(console)
            }
            DemoButton(title: "运行：actor") {
                let console = console
                Task { await RaceExperiments.runActor(console) }
            }
        }
    }
}

#Preview {
    NavigationStack { DataRaceDemo() }
}
