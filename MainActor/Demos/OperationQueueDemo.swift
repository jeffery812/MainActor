//
//  OperationQueueDemo.swift
//  MainActor
//
//  对应文档 §4：依赖、最大并发数、取消、暂停。
//

import SwiftUI

nonisolated enum OperationExperiments {
    private static func step(_ name: String, _ seconds: Double, _ console: Console) {
        console.log("\(name) 开始")
        Thread.sleep(forTimeInterval: seconds)
        console.log("\(name) 完成")
    }

    /// 依赖：添加顺序与执行顺序无关，由依赖关系决定
    static func dependencies(_ console: Console) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2

        let download = BlockOperation { step("下载", 0.6, console) }
        let unzip = BlockOperation { step("解压（依赖下载）", 0.4, console) }
        let save = BlockOperation { step("保存（依赖解压）", 0.3, console) }
        let analytics = BlockOperation { step("上报统计（无依赖）", 0.3, console) }
        let done = BlockOperation { console.log("✅ 全部完成（OperationQueue.main，依赖保存与上报）") }

        unzip.addDependency(download)
        save.addDependency(unzip)
        done.addDependency(save)
        done.addDependency(analytics)

        // 故意倒序添加
        queue.addOperations([save, unzip, download, analytics], waitUntilFinished: false)
        OperationQueue.main.addOperation(done)   // 依赖可以跨队列
    }

    /// 取消：未开始的操作直接不执行；已在运行的需要自己检查 isCancelled
    static func cancellation(_ console: Console) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2

        for i in 1...6 {
            let operation = BlockOperation()
            operation.addExecutionBlock { [unowned operation] in
                console.log("操作\(i) 开始")
                for _ in 0..<10 {
                    if operation.isCancelled {
                        console.log("操作\(i) 检测到 isCancelled，提前退出")
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                console.log("操作\(i) 完成")
            }
            queue.addOperation(operation)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            console.log("⛔️ cancelAllOperations()")
            queue.cancelAllOperations()
        }
    }

    /// 暂停 / 恢复：暂停只影响尚未开始的操作
    static func suspension(_ console: Console) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.isSuspended = true
        for i in 1...3 {
            queue.addOperation { step("操作\(i)", 0.2, console) }
        }
        console.log("队列已暂停，添加了 3 个操作，1 秒后恢复")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            console.log("▶︎ isSuspended = false")
            queue.isSuspended = false
        }
    }
}

struct OperationQueueDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "OperationQueue",
            summary: """
            OperationQueue 是 GCD 的面向对象封装，多了：依赖关系、最大并发数、取消、暂停/恢复。
            日志中观察执行顺序与线程。
            """,
            console: console
        ) {
            DemoButton(title: "依赖关系", note: "下载 → 解压 → 保存；上报统计独立；maxConcurrent = 2") {
                run(OperationExperiments.dependencies)
            }
            DemoButton(title: "取消", note: "6 个 1 秒的操作，1.5 秒后 cancelAllOperations") {
                run(OperationExperiments.cancellation)
            }
            DemoButton(title: "暂停 / 恢复", note: "maxConcurrent = 1 即串行队列") {
                run(OperationExperiments.suspension)
            }
        }
    }

    private func run(_ experiment: (Console) -> Void) {
        console.clear()
        experiment(console)
    }
}

#Preview {
    NavigationStack { OperationQueueDemo() }
}
