//
//  AsyncSequenceCombineDemo.swift
//  MainActor
//
//  同一件事分别用 Combine 和 AsyncSequence 实现，对比两者的差异：
//  推送 vs 拉取、线程、缓冲、生命周期、取消、错误处理，以及两者之间的转换。
//  日志中 [C] = Combine，[A] = AsyncSequence。
//

import Combine
import SwiftUI

struct AsyncSequenceCombineDemo: View {
    @State private var console = Console()
    @State private var lab = CombineAsyncLab()

    var body: some View {
        DemoScreen(
            title: "AsyncSequence vs Combine",
            summary: """
            每个按钮用两种方式做同一件事。[C] = Combine：Publisher 推送（push），sink 在发送方或 Scheduler 指定的线程上被调用。\
            [A] = AsyncSequence：消费者用 for await 拉取（pull），在当前 actor（这里是 MainActor）上执行。
            新代码优先 AsyncSequence；Combine 的 debounce、throttle、combineLatest 等时间和组合操作符，标准库中没有对应，需要 swift-async-algorithms 包。
            """,
            console: console
        ) {
            DemoButton(title: "① 变换管道", note: "filter → map → prefix，两种写法结果相同") { lab.pipeline(console) }
            DemoButton(title: "② 定时器", note: "Timer.publish vs AsyncStream + Task.sleep") { lab.timer(console) }
            DemoButton(title: "③ 通知", note: "publisher(for:) 同步推送 vs notifications(named:) 异步拉取") { lab.notifications(console) }
            DemoButton(title: "④ 慢消费者：缓冲策略", note: "Combine 全部排队；AsyncStream .bufferingNewest(2) 丢弃中间的值") { lab.buffering(console) }
            DemoButton(title: "⑤ 忘记保存句柄", note: "丢掉 AnyCancellable 立即取消；丢掉 Task 照样运行") { lab.forgetHandles(console) }
            DemoButton(title: "⑥ 取消", note: "1 秒后 cancellable.cancel() 与 task.cancel()") { lab.cancellation(console) }
            DemoButton(title: "⑦ 错误处理", note: "completion: .failure vs for try await + catch") { lab.errors(console) }
            DemoButton(title: "⑧ 互相转换", note: "@Published 的 .values；AsyncStream → Subject") { lab.bridging(console) }
        }
        .onDisappear { lab.stopAll() }
    }
}

/// 保存所有订阅与任务，切换实验或离开页面时统一停止
final class CombineAsyncLab {
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []

    static let ping = Notification.Name("demo.ping")

    func stopAll() {
        cancellables.removeAll()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func start(_ console: Console) {
        stopAll()
        console.clear()
    }

    // MARK: ① 变换管道

    func pipeline(_ console: Console) {
        start(console)

        // Combine：Publisher 把值推给 sink
        (1...10).publisher
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 10 }
            .prefix(3)
            .sink(receiveCompletion: { console.log("[C] 完成：\($0)") },
                  receiveValue: { console.log("[C] 收到 \($0)") })
            .store(in: &cancellables)

        // AsyncSequence：消费者用 for await 逐个拉取
        tasks.append(Task {
            for await value in Self.numbers(1...10).filter({ $0.isMultiple(of: 2) }).map({ $0 * 10 }).prefix(3) {
                console.log("[A] 收到 \(value)")
            }
            console.log("[A] 完成：for await 循环结束")
        })
    }

    // MARK: ② 定时器

    func timer(_ console: Console) {
        start(console)

        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .scan(0) { count, _ in count + 1 }
            .prefix(5)
            .sink { console.log("[C] tick \($0)") }
            .store(in: &cancellables)

        tasks.append(Task {
            var count = 0
            for await _ in Self.ticks(every: .milliseconds(500)).prefix(5) {
                count += 1
                console.log("[A] tick \(count)")
            }
        })
    }

    // MARK: ③ 通知

    func notifications(_ console: Console) {
        start(console)

        NotificationCenter.default.publisher(for: Self.ping)
            .prefix(3)
            .sink { console.log("[C] 收到通知 #\($0.userInfo?["n"] ?? "?")（在 post 调用内同步执行）") }
            .store(in: &cancellables)

        tasks.append(Task {
            for await note in NotificationCenter.default.notifications(named: Self.ping).prefix(3) {
                console.log("[A] 收到通知 #\(note.userInfo?["n"] ?? "?")（稍后在 MainActor 上执行）")
            }
            console.log("[A] 收满 3 个，循环结束")
        })

        tasks.append(Task {
            try? await Task.sleep(for: .milliseconds(100))   // 等监听者开始等待
            for n in 1...4 {
                console.log("post #\(n)")
                NotificationCenter.default.post(name: Self.ping, object: nil, userInfo: ["n": n])
                console.log("post #\(n) 返回")
                try? await Task.sleep(for: .milliseconds(300))
            }
        })
    }

    // MARK: ④ 慢消费者：缓冲策略

    func buffering(_ console: Console) {
        start(console)

        let subject = PassthroughSubject<Int, Never>()
        Self.slowCombineConsumer(subject, console: console).store(in: &cancellables)

        // AsyncStream 只保留最新的 2 个值
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(2))
        tasks.append(Task {
            for await value in stream {
                console.log("[A] 处理 \(value)（每个耗时 200ms）")
                try? await Task.sleep(for: .milliseconds(200))
            }
            console.log("[A] 流结束")
        })

        tasks.append(Task {
            try? await Task.sleep(for: .milliseconds(50))    // 让两个消费者先就绪
            for value in 1...8 {
                subject.send(value)
                if case .dropped(let old) = continuation.yield(value) {
                    console.log("[A] 缓冲已满，丢弃 \(old)")
                }
            }
            console.log("生产者：8 个值已全部发出，没有被慢消费者拖住")
            subject.send(completion: .finished)
            continuation.finish()
        })
    }

    /// 在 nonisolated 上下文中创建订阅，保证 sink 闭包不被推断为 MainActor 隔离（它运行在后台串行队列上）
    private nonisolated static func slowCombineConsumer(_ subject: PassthroughSubject<Int, Never>, console: Console) -> AnyCancellable {
        subject
            .receive(on: DispatchQueue(label: "demo.combine.slow"))
            .sink(receiveCompletion: { _ in console.log("[C] 流结束") },
                  receiveValue: { value in
                      console.log("[C] 处理 \(value)（每个耗时 200ms）")
                      Thread.sleep(forTimeInterval: 0.2)
                  })
    }

    // MARK: ⑤ 忘记保存句柄

    func forgetHandles(_ console: Console) {
        start(console)

        // Combine：没有保存 AnyCancellable，它被释放的同时订阅就被取消
        _ = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .handleEvents(receiveCancel: { console.log("[C] AnyCancellable 被释放 → 订阅立即取消，一个 tick 都收不到") })
            .sink { _ in console.log("[C] tick（不会出现）") }

        // AsyncSequence：没有保存 Task，它照样运行到结束（也就无法从外部取消）
        Task {
            var count = 0
            for await _ in Self.ticks(every: .milliseconds(300)).prefix(3) {
                count += 1
                console.log("[A] tick \(count)（没有保存 Task，照样运行）")
            }
            console.log("[A] 收满 3 个后结束")
        }
    }

    // MARK: ⑥ 取消

    func cancellation(_ console: Console) {
        start(console)

        let subscription = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .scan(0) { count, _ in count + 1 }
            .handleEvents(receiveCancel: { console.log("[C] 收到取消") })
            .sink { console.log("[C] tick \($0)") }

        let consumer = Task {
            var count = 0
            for await _ in Self.ticks(every: .milliseconds(300), onTermination: { console.log("[A] onTermination：\($0)") }) {
                count += 1
                console.log("[A] tick \(count)")
            }
            console.log("[A] for await 结束（任务已取消）")
        }

        tasks.append(Task {
            try? await Task.sleep(for: .seconds(1))
            console.log("⛔️ subscription.cancel()  /  consumer.cancel()")
            subscription.cancel()   // 等价于释放最后一个对它的引用
            consumer.cancel()
        })
    }

    // MARK: ⑦ 错误处理

    func errors(_ console: Console) {
        start(console)

        // Combine：错误是 Publisher 类型的一部分（Failure），通过 completion 送达
        [1, 2, 3].publisher
            .tryMap { value -> Int in
                if value == 3 { throw DemoError.failed("第 3 个值") }
                return value
            }
            .sink(receiveCompletion: { completion in
                      if case .failure(let error) = completion { console.log("[C] completion: .failure(\(error))") }
                  },
                  receiveValue: { console.log("[C] 收到 \($0)") })
            .store(in: &cancellables)

        // AsyncSequence：用 for try await 迭代，错误用 do / catch 捕获
        tasks.append(Task {
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
                continuation.yield(2)
                continuation.finish(throwing: DemoError.failed("第 3 个值"))
            }
            do {
                for try await value in stream { console.log("[A] 收到 \(value)") }
            } catch {
                console.log("[A] catch: \(error)")
            }
        })
    }

    // MARK: ⑧ 互相转换

    func bridging(_ console: Console) {
        start(console)

        // Combine → AsyncSequence：任何 Publisher 都有 .values
        let counter = PublishedCounter()
        tasks.append(Task {
            for await value in counter.$value.values.prefix(4) {
                console.log("[C→A] for await counter.$value.values 收到 \(value)")
            }
        })
        tasks.append(Task {
            for _ in 1...3 {
                try? await Task.sleep(for: .milliseconds(200))
                counter.value += 1
            }
        })

        // AsyncSequence → Combine：没有内置转换，用 Subject 转发
        let subject = PassthroughSubject<Int, Never>()
        subject
            .sink(receiveCompletion: { _ in console.log("[A→C] Subject 完成") },
                  receiveValue: { console.log("[A→C] sink 收到 \($0)") })
            .store(in: &cancellables)
        tasks.append(Task {
            for await value in Self.numbers(1...3) { subject.send(value * 100) }
            subject.send(completion: .finished)
        })
    }

    // MARK: - 辅助

    private nonisolated static func numbers(_ range: ClosedRange<Int>) -> AsyncStream<Int> {
        AsyncStream { continuation in
            for value in range { continuation.yield(value) }
            continuation.finish()
        }
    }

    /// 标准库没有定时器序列，用 AsyncStream + Task.sleep 实现。
    /// 生产者跑在协作线程池上，Task.sleep 不依赖 RunLoop，所以拖动列表不会影响它。
    private nonisolated static func ticks(
        every interval: Duration,
        onTermination: (@Sendable (AsyncStream<Void>.Continuation.Termination) -> Void)? = nil
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let producer = Task {
                // 睡到绝对截止时间，而不是每轮 sleep(for: interval)：
                // 后者每次的唤醒延迟会累加，越往后越晚
                let clock = ContinuousClock()
                var next = clock.now + interval
                while true {
                    // 被取消时 sleep 抛错，直接退出；用 try? 吞掉错误会多发一个值
                    do { try await Task.sleep(until: next, clock: clock) } catch { break }
                    continuation.yield(())
                    next += interval
                    // 落后超过一个周期（例如进程被挂起过）时跳过，不连续补发
                    while next <= clock.now { next += interval }
                }
            }
            continuation.onTermination = { reason in
                producer.cancel()
                onTermination?(reason)
            }
        }
    }
}

final class PublishedCounter: ObservableObject {
    @Published var value = 0
}

#Preview {
    NavigationStack { AsyncSequenceCombineDemo() }
}
