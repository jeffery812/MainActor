//
//  Work.swift
//  MainActor
//
//  模拟耗时工作，以及几个线程安全的小工具。
//

import Foundation
import Synchronization

nonisolated enum Work {
    /// 同步的 CPU 忙等，模拟耗时计算（会占住当前线程）
    @discardableResult
    static func spin(seconds: Double) -> Int {
        let end = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        var iterations = 0
        while ContinuousClock.now < end { iterations &+= 1 }
        return iterations
    }

    /// 同步阻塞当前线程（不消耗 CPU，但线程被占住）
    static func block(milliseconds: Int) {
        usleep(useconds_t(milliseconds * 1000))
    }

    /// nonisolated(nonsending)：在**调用方的 actor** 上执行。
    /// 从 MainActor 调用 → 仍然在主线程跑，会卡 UI。
    nonisolated(nonsending)
    static func spinNonsending(seconds: Double, console: Console) async -> Int {
        console.log("nonisolated(nonsending) async 函数内部")
        return spin(seconds: seconds)
    }

    /// @concurrent：总是在全局并发执行器（后台线程池）上执行。
    @concurrent
    static func spinConcurrent(seconds: Double, console: Console) async -> Int {
        console.log("@concurrent async 函数内部")
        return spin(seconds: seconds)
    }
}

/// 统计"同时运行的任务数"及峰值
nonisolated final class RunningCounter: Sendable {
    private let state = Mutex((current: 0, peak: 0))

    func enter() -> Int {
        state.withLock { state in
            state.current += 1
            state.peak = max(state.peak, state.current)
            return state.current
        }
    }

    func leave() {
        state.withLock { $0.current -= 1 }
    }

    var peak: Int { state.withLock { $0.peak } }
}

/// 收集用到过的线程号
nonisolated final class ThreadSet: Sendable {
    private let ids = Mutex<Set<UInt32>>([])

    func insertCurrent() {
        let id = ThreadInfo.id
        ids.withLock { _ = $0.insert(id) }
    }

    var count: Int { ids.withLock { $0.count } }
}
