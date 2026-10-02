//
//  GCDToolsDemo.swift
//  MainActor
//
//  对应文档 §4、§6.2：GCD 的各种工具，以及 GCD 线程池 vs Swift Concurrency 协作式线程池。
//

import SwiftUI

nonisolated enum GCDExperiments {
    /// DispatchGroup：等待一组任务完成后再通知
    static func group(_ console: Console) {
        let group = DispatchGroup()
        for (name, seconds) in [("A", 0.5), ("B", 1.0), ("C", 1.5)] {
            DispatchQueue.global().async(group: group) {
                console.log("\(name) 开始（\(seconds)s）")
                Thread.sleep(forTimeInterval: seconds)
                console.log("\(name) 完成")
            }
        }
        group.notify(queue: .main) {
            console.log("group.notify(queue: .main)：全部完成")
        }
    }

    /// DispatchSemaphore：限制同时运行的任务数
    static func semaphore(_ console: Console) {
        let semaphore = DispatchSemaphore(value: 2)
        let running = RunningCounter()
        let group = DispatchGroup()
        for i in 1...6 {
            DispatchQueue.global().async(group: group) {
                semaphore.wait()
                let now = running.enter()
                console.log("任务\(i) 开始（同时运行：\(now)）")
                Thread.sleep(forTimeInterval: 0.6)
                running.leave()
                console.log("任务\(i) 结束")
                semaphore.signal()
            }
        }
        group.notify(queue: .main) {
            console.log("峰值并发数 = \(running.peak)（信号量 = 2）")
        }
    }

    /// 串行队列 vs 并发队列
    static func serialVsConcurrent(_ console: Console) {
        let serial = DispatchQueue(label: "demo.serial")
        let concurrent = DispatchQueue(label: "demo.concurrent", attributes: .concurrent)
        for i in 1...3 {
            serial.async {
                console.log("串行 任务\(i) 开始")
                Thread.sleep(forTimeInterval: 0.3)
                console.log("串行 任务\(i) 结束")
            }
        }
        for i in 1...3 {
            concurrent.async {
                console.log("并发 任务\(i) 开始")
                Thread.sleep(forTimeInterval: 0.3)
                console.log("并发 任务\(i) 结束")
            }
        }
    }

    /// 并发队列 + barrier：读可并发，写独占
    static func barrier(_ console: Console) {
        let queue = DispatchQueue(label: "demo.readwrite", attributes: .concurrent)
        for i in 1...3 {
            queue.async {
                console.log("📖 读\(i) 开始")
                Thread.sleep(forTimeInterval: 0.3)
                console.log("📖 读\(i) 结束")
            }
        }
        queue.async(flags: .barrier) {
            console.log("✍️ barrier 写 开始（独占队列）")
            Thread.sleep(forTimeInterval: 0.5)
            console.log("✍️ barrier 写 结束")
        }
        for i in 4...5 {
            queue.async {
                console.log("📖 读\(i) 开始")
                Thread.sleep(forTimeInterval: 0.3)
                console.log("📖 读\(i) 结束")
            }
        }
    }

    /// concurrentPerform：同步的并行循环
    static func concurrentPerform(_ console: Console) {
        DispatchQueue.global().async {
            console.log("concurrentPerform 开始（阻塞当前线程直到全部完成）")
            DispatchQueue.concurrentPerform(iterations: 8) { index in
                console.log("迭代 \(index)")
                Work.spin(seconds: 0.2)
            }
            console.log("concurrentPerform 返回")
        }
    }

    /// 从后台线程 main.sync 是安全的（主线程上调用会死锁）
    static func mainSyncFromBackground(_ console: Console) {
        DispatchQueue.global().async {
            console.log("后台线程调用 DispatchQueue.main.sync")
            DispatchQueue.main.sync {
                console.log("main.sync 的 block（主线程）")
            }
            console.log("main.sync 返回，后台线程继续")
        }
    }

    /// GCD：线程被阻塞时会补充新线程
    static func threadExplosion(_ console: Console) {
        let threads = ThreadSet()
        let group = DispatchGroup()
        let start = ContinuousClock.now
        console.log("GCD：提交 100 个各阻塞 100ms 的任务")
        for _ in 0..<100 {
            DispatchQueue.global().async(group: group) {
                threads.insertCurrent()
                Work.block(milliseconds: 100)
            }
        }
        group.notify(queue: .global()) {
            console.log("GCD：用了 \(threads.count) 个线程，耗时 \(start.duration(to: .now).msText)")
        }
    }

    /// Swift Concurrency：协作式线程池不会因阻塞而补充线程（所以 async 代码中不能阻塞）
    @concurrent
    static func cooperativePool(_ console: Console) async {
        let threads = ThreadSet()
        let start = ContinuousClock.now
        console.log("TaskGroup：100 个子任务各阻塞 100ms（反面示例）")
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    threads.insertCurrent()
                    Work.block(milliseconds: 100)
                }
            }
        }
        console.log("协作式线程池：用了 \(threads.count) 个线程，耗时 \(start.duration(to: .now).msText)（CPU 核心数 \(ProcessInfo.processInfo.activeProcessorCount)）")
    }
}

struct GCDToolsDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "GCD 工具箱",
            summary: """
            GCD 的常用工具。最后一组对比：同样 100 个阻塞任务，GCD 会不断开新线程（线程爆炸），
            而 Swift Concurrency 的协作式线程池线程数固定（≈ CPU 核心数），阻塞会让所有任务排队 —— 所以 async 代码里绝不能阻塞。
            """,
            console: console
        ) {
            DemoButton(title: "DispatchGroup + notify") { run(GCDExperiments.group) }
            DemoButton(title: "DispatchSemaphore 限流", note: "6 个任务，最多 2 个同时运行") { run(GCDExperiments.semaphore) }
            DemoButton(title: "串行队列 vs 并发队列") { run(GCDExperiments.serialVsConcurrent) }
            DemoButton(title: "并发队列 + barrier（读写锁）") { run(GCDExperiments.barrier) }
            DemoButton(title: "concurrentPerform 并行循环") { run(GCDExperiments.concurrentPerform) }
            DemoButton(title: "后台线程 DispatchQueue.main.sync", note: "在主线程调用会死锁，这里不演示") { run(GCDExperiments.mainSyncFromBackground) }
            DemoButton(title: "线程爆炸：GCD", note: "100 个阻塞任务") { run(GCDExperiments.threadExplosion) }
            DemoButton(title: "协作式线程池：TaskGroup", note: "同样 100 个阻塞任务") {
                let console = console
                console.clear()
                Task { await GCDExperiments.cooperativePool(console) }
            }
        }
    }

    private func run(_ experiment: (Console) -> Void) {
        console.clear()
        experiment(console)
    }
}

#Preview {
    NavigationStack { GCDToolsDemo() }
}
