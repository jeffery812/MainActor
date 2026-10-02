//
//  Console.swift
//  MainActor
//
//  线程安全的日志：在调用 `log` 的那一刻记录线程与时间，保证日志顺序就是真实的执行顺序。
//

import SwiftUI
import Synchronization

/// 一条日志：记录发生时所在的线程与相对时间
nonisolated struct LogEntry: Identifiable, Sendable {
    let id: Int
    let elapsed: Duration
    let message: String
    let isMainThread: Bool
    let threadID: UInt32
}

nonisolated enum ThreadInfo {
    /// 同步函数：可在任意上下文（包括 async 函数）中调用，读取"此刻"所在的线程
    static func current() -> (isMain: Bool, id: UInt32) {
        (pthread_main_np() != 0, pthread_mach_thread_np(pthread_self()))
    }

    static var id: UInt32 { pthread_mach_thread_np(pthread_self()) }
}

nonisolated extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }

    var msText: String { String(format: "%.0f ms", milliseconds) }
}

/// 用 Mutex 保护的日志缓冲区，任何线程都可以写入
nonisolated final class LogBuffer: Sendable {
    private struct State: Sendable {
        var entries: [LogEntry] = []
        var nextID = 0
        var start = ContinuousClock.now
    }

    private let state = Mutex(State())

    func append(_ message: String) {
        let thread = ThreadInfo.current()
        state.withLock { state in
            state.entries.append(LogEntry(
                id: state.nextID,
                elapsed: state.start.duration(to: .now),
                message: message,
                isMainThread: thread.isMain,
                threadID: thread.id
            ))
            state.nextID += 1
        }
    }

    func snapshot() -> [LogEntry] {
        state.withLock { $0.entries }
    }

    func reset() {
        state.withLock { state in
            state.entries.removeAll()
            state.start = .now
        }
    }
}

/// 供 SwiftUI 显示的日志模型。
/// `log` 是 nonisolated 的，可以在任意线程 / 任意 actor 上同步调用。
@Observable
final class Console {
    private(set) var entries: [LogEntry] = []

    nonisolated let buffer = LogBuffer()

    nonisolated func log(_ message: String) {
        buffer.append(message)
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func refresh() {
        entries = buffer.snapshot()
    }

    func clear() {
        buffer.reset()
        entries = []
    }
}

// MARK: - Views

struct ConsoleView: View {
    let console: Console

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("日志").font(.headline)
                Text("绿色 = 主线程，橙色 = 后台线程（数字为线程号）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") { console.clear() }
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                List(Array(console.entries.enumerated()), id: \.element.id) { index, entry in
                    LogRow(index: index, entry: entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .onChange(of: console.entries.count) {
                    if let last = console.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct LogRow: View {
    let index: Int
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("#\(index + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(entry.elapsed.msText)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            ThreadBadge(entry: entry)
            Text(entry.message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct ThreadBadge: View {
    let entry: LogEntry

    var body: some View {
        Text(entry.isMainThread ? "main" : "T\(entry.threadID)")
            .font(.system(.caption2, design: .monospaced).bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(minWidth: 44)
            .background(entry.isMainThread ? Color.green : Color.orange, in: Capsule())
    }
}

/// 每个演示页的通用布局：上半部分是说明和按钮，下半部分是日志
struct DemoScreen<Controls: View>: View {
    let title: String
    let summary: String
    let console: Console
    @ViewBuilder let controls: Controls

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        controls
                    }
                    .padding()
                }
                .frame(height: geometry.size.height * 0.5)

                Divider()

                ConsoleView(console: console)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DemoButton: View {
    let title: String
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}
