//
//  RunLoopModeDemo.swift
//  MainActor
//
//  对应文档 §3、§6、§11.4、§12.1、§12.3：RunLoop Mode 对滚动期间执行的影响。
//

import Combine
import SwiftUI

struct RunLoopModeDemo: View {
    @State private var model = TickModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("每个计数器每 0.1 秒 +1。按住下方列表拖动（不要松手），观察哪些计数器停止。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("当前主 RunLoop mode：\(model.currentMode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(model.currentMode.contains("Tracking") ? .red : .primary)

                CounterRow(title: "Timer.publish(in: .default)", value: model.timerDefault, pausesOnScroll: true)
                CounterRow(title: "Timer.publish(in: .common)", value: model.timerCommon, pausesOnScroll: false)
                CounterRow(title: "receive(on: RunLoop.main)", value: model.receiveOnRunLoop, pausesOnScroll: true)
                CounterRow(title: "receive(on: DispatchQueue.main)", value: model.receiveOnMainQueue, pausesOnScroll: false)
                CounterRow(title: "RunLoop.main.perform(inModes: [.default])", value: model.runLoopPerformDefault, pausesOnScroll: true)
                CounterRow(title: "DispatchQueue.main.async", value: model.mainQueueAsync, pausesOnScroll: false)
                CounterRow(title: "Task { @MainActor } + Task.sleep", value: model.taskSleepLoop, pausesOnScroll: false)
            }
            .padding()

            Divider()

            List(0..<200, id: \.self) { row in
                Text("第 \(row) 行 —— 按住拖动我")
                    .foregroundStyle(.secondary)
            }
            .listStyle(.plain)
        }
        .navigationTitle("RunLoop Mode 与滚动")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct CounterRow: View {
    let title: String
    let value: Int
    let pausesOnScroll: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(pausesOnScroll ? "滚动时暂停" : "滚动时继续")
                .font(.caption2)
                .foregroundStyle(pausesOnScroll ? .red : .green)
            Text("\(value)")
                .font(.callout.monospacedDigit().bold())
                .frame(width: 50, alignment: .trailing)
        }
    }
}

@Observable
final class TickModel {
    var timerDefault = 0
    var timerCommon = 0
    var receiveOnRunLoop = 0
    var receiveOnMainQueue = 0
    var runLoopPerformDefault = 0
    var mainQueueAsync = 0
    var taskSleepLoop = 0
    var currentMode = "-"

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var ticker: BackgroundTicker?
    @ObservationIgnored private var loopTask: Task<Void, Never>?

    func start() {
        guard ticker == nil else { return }

        // 1) RunLoop 定时器：注册在不同 mode
        Timer.publish(every: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in self?.timerDefault += 1 }
            .store(in: &cancellables)
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.timerCommon += 1 }
            .store(in: &cancellables)

        // 2) 后台线程产生事件，再用不同的 Scheduler 切回主线程
        let ticker = BackgroundTicker(interval: .milliseconds(100), model: self)
        ticker.subject
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.receiveOnRunLoop += 1 }
            .store(in: &cancellables)
        ticker.subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.receiveOnMainQueue += 1 }
            .store(in: &cancellables)
        ticker.resume()
        self.ticker = ticker

        // 3) Swift Concurrency：MainActor 上的循环任务
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                taskSleepLoop += 1
                currentMode = RunLoop.main.currentMode?.rawValue ?? "nil"
            }
        }
    }

    func stop() {
        cancellables.removeAll()
        ticker?.cancel()
        ticker = nil
        loopTask?.cancel()
        loopTask = nil
    }
}

/// 在 GCD 后台队列上运行的定时源（DispatchSource 不依赖 RunLoop）
private nonisolated final class BackgroundTicker: @unchecked Sendable {
    let subject = PassthroughSubject<Void, Never>()
    private let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
    private weak var model: TickModel?

    init(interval: DispatchTimeInterval, model: TickModel) {
        self.model = model
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in self?.tick() }
    }

    func resume() { source.resume() }

    func cancel() { source.cancel() }

    private func tick() {
        subject.send(())

        let model = model
        DispatchQueue.main.async {
            MainActor.assumeIsolated { model?.mainQueueAsync += 1 }
        }
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { model?.runLoopPerformDefault += 1 }
        }
        // perform(inModes:) 不会主动唤醒 RunLoop，这里手动唤醒
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

#Preview {
    NavigationStack { RunLoopModeDemo() }
}
