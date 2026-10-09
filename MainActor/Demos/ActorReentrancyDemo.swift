//
//  ActorReentrancyDemo.swift
//  MainActor
//
//  对应文档 §7.10、§14：actor 保证串行访问，但在 await 处可重入。
//

import SwiftUI

/// 同步方法：actor 保证同一时间只有一个调用在执行
actor SerialWorker {
    func work(_ name: String, console: Console) {
        console.log("\(name) 开始（actor 内）")
        Work.spin(seconds: 0.2)
        console.log("\(name) 结束")
    }
}

/// 朴素缓存：await 期间其他调用可以进入 actor，导致重复下载
actor NaiveImageCache {
    private var cache: [String: String] = [:]
    private(set) var downloadCount = 0

    func image(for key: String, console: Console) async -> String {
        if let cached = cache[key] {
            console.log("命中缓存")
            return cached
        }
        downloadCount += 1
        let number = downloadCount
        console.log("开始下载 #\(number)（await 期间 actor 可处理其他调用）")
        try? await Task.sleep(for: .milliseconds(500))
        let image = "image-\(key)"
        cache[key] = image
        console.log("下载 #\(number) 完成，写入缓存")
        return image
    }
}

/// 修正：缓存"进行中的 Task"，重入的调用复用同一个下载
actor DedupImageCache {
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<String, Never>] = [:]
    private(set) var downloadCount = 0

    func image(for key: String, console: Console) async -> String {
        if let cached = cache[key] {
            console.log("命中缓存")
            return cached
        }
        if let task = inFlight[key] {
            console.log("复用进行中的下载")
            return await task.value
        }
        downloadCount += 1
        let number = downloadCount
        let task = Task {
            console.log("开始下载 #\(number)")
            try? await Task.sleep(for: .milliseconds(500))
            return "image-\(key)"
        }
        inFlight[key] = task
        let image = await task.value
        cache[key] = image
        inFlight[key] = nil
        console.log("下载 #\(number) 完成，写入缓存")
        return image
    }
}

struct ActorReentrancyDemo: View {
    @State private var console = Console()

    var body: some View {
        DemoScreen(
            title: "actor 串行与重入",
            summary: """
            ① 5 个任务并发调用 actor 的同步方法：开始/结束成对出现，从不交错 —— actor 保证串行。
            ② 5 个任务同时加载同一张图片：朴素实现在 await 处被重入，下载 5 次。
            ③ 缓存进行中的 Task 后只下载 1 次。
            """,
            console: console
        ) {
            DemoButton(title: "① actor 串行执行", note: "同步方法不会交错") { serial() }
            DemoButton(title: "② 朴素缓存（重入问题）", note: "期望下载 1 次，实际 5 次") { naive() }
            DemoButton(title: "③ 去重缓存", note: "复用进行中的 Task") { dedup() }
        }
    }

    private func serial() {
        let console = console
        console.clear()
        let worker = SerialWorker()
        Task {
            await withTaskGroup(of: Void.self) { group in
                for i in 1...5 {
                    group.addTask { await worker.work("调用\(i)", console: console) }
                }
            }
            console.log("全部完成")
        }
    }

    private func naive() {
        let console = console
        console.clear()
        let cache = NaiveImageCache()
        Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 1...5 {
                    group.addTask { _ = await cache.image(for: "avatar", console: console) }
                }
            }
            console.log("朴素缓存：总下载次数 = \(await cache.downloadCount)")
        }
    }

    private func dedup() {
        let console = console
        console.clear()
        let cache = DedupImageCache()
        Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 1...5 {
                    group.addTask { _ = await cache.image(for: "avatar", console: console) }
                }
            }
            console.log("去重缓存：总下载次数 = \(await cache.downloadCount)")
        }
    }
}

#Preview {
    NavigationStack { ActorReentrancyDemo() }
}
