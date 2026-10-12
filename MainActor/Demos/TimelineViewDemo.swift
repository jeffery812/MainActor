//
//  TimelineViewDemo.swift
//  MainActor
//
//  对应文档 §8.4：TimelineView 按时间表重绘视图。
//  覆盖全部内置调度表（periodic / everyMinute / animation / explicit）和自定义调度表，
//  以及跳秒与扫秒、限帧与暂停、Canvas 动画、秒表、context.cadence，和不需要 TimelineView 的情况。
//

import SwiftUI

struct TimelineViewDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                TimelineView 按「调度表」（TimelineSchedule）给出的时间点重新计算内容闭包，\
                闭包参数 context.date 就是这次刷新对应的时间点。它不需要 Timer，也没有要手动停止的对象。
                每张卡片演示一种场景，蓝色小字是对应写法，「已刷新 N 次」是内容闭包被重新计算的次数。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)

                PeriodicCard()
                EveryMinuteCard()
                TickVersusSweepCard()
                FrameRateCard()
                CanvasCard()
                StopwatchCard()
                ExplicitCard()
                CustomScheduleCard()
                SelfUpdatingTextCard()
                TipsCard()
            }
            .padding()
        }
        .navigationTitle("TimelineView")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ① 每秒刷新

private struct PeriodicCard: View {
    @State private var meter = UpdateMeter()

    var body: some View {
        DemoCard(
            title: "① 每秒刷新：.periodic(from:by:)",
            code: "TimelineView(.periodic(from: .now, by: 1)) { context in … }",
            note: """
            按固定间隔刷新，适合时钟、倒计时。context.cadence 表示系统建议的刷新粒度，用于 watchOS 抬腕前等降频场景，\
            可据此隐藏秒数这类变化太快的内容。实测 iOS 26 模拟器上所有调度表报告的都是 .minutes（即使每帧刷新），所以 iOS 上不要依据它做判断。
            """
        ) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let count = meter.tick(context.date)
                VStack(spacing: 4) {
                    Text(context.date.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.default, value: context.date)
                    Text("cadence: \(context.cadence.name) · 已刷新 \(count) 次")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - ② 每分钟刷新

private struct EveryMinuteCard: View {
    @State private var meter = UpdateMeter()

    var body: some View {
        DemoCard(
            title: "② 每分钟刷新：.everyMinute",
            code: "TimelineView(.everyMinute) { context in … }",
            note: """
            在每分钟的第 0 秒刷新。第一次计算时，context.date 是当前这一分钟的开始，而不是视图出现的时刻。\
            适合只显示到分钟的内容（时钟、「还有 x 分钟开始」），比每秒刷新省电。
            """
        ) {
            TimelineView(.everyMinute) { context in
                let count = meter.tick(context.date)
                VStack(spacing: 4) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("context.date = \(context.date.formatted(.dateTime.hour().minute().second())) · 已刷新 \(count) 次")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - ③ 跳秒 vs 扫秒

private struct TickVersusSweepCard: View {
    var body: some View {
        DemoCard(
            title: "③ 跳秒 vs 扫秒",
            code: """
            TimelineView(.periodic(from: .now, by: 1)) { ClockFace(…).animation(.spring, value: context.date) }
            TimelineView(.animation) { ClockFace(…) }
            """,
            note: """
            左边每秒刷新一次，两次刷新之间的移动交给 SwiftUI 动画补齐；右边每帧刷新，指针连续移动。\
            指针角度用累计秒数计算（不对 360° 取余），否则从 59 秒到 0 秒时动画会倒转一圈。
            """
        ) {
            HStack(spacing: 32) {
                VStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ClockFace(date: context.date, sweep: false)
                            .animation(.spring(duration: 0.35, bounce: 0.45), value: context.date)
                    }
                    Text("跳秒").font(.caption)
                }
                VStack {
                    TimelineView(.animation) { context in
                        ClockFace(date: context.date, sweep: true)
                    }
                    Text("扫秒").font(.caption)
                }
            }
        }
    }
}

private struct ClockFace: View {
    let date: Date
    let sweep: Bool
    private let size: CGFloat = 110

    var body: some View {
        // 从参考日期（2001-01-01 00:00 UTC）起的本地累计秒数；参考日期正好是整点，取余结果和本地时间一致
        let local = date.timeIntervalSinceReferenceDate + Double(TimeZone.current.secondsFromGMT(for: date))
        let seconds = sweep ? local : local.rounded(.down)
        ZStack {
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 2)
            ForEach(0..<12) { tick in
                Capsule()
                    .fill(.secondary)
                    .frame(width: 2, height: tick % 3 == 0 ? 10 : 5)
                    .offset(y: -size / 2 + 8)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            hand(length: size * 0.26, width: 4, degrees: local / 3600 * 30, color: .primary)
            hand(length: size * 0.38, width: 3, degrees: local / 60 * 6, color: .primary)
            hand(length: size * 0.42, width: 1.5, degrees: seconds * 6, color: .red)
            Circle().fill(.red).frame(width: 6, height: 6)
        }
        .frame(width: size, height: size)
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(degrees))
    }
}

// MARK: - ④ 限制帧率与暂停

private struct FrameRateCard: View {
    @State private var paused = false

    var body: some View {
        DemoCard(
            title: "④ 每帧刷新、限制帧率与暂停：.animation",
            code: """
            TimelineView(.animation) { … }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { … }
            """,
            note: """
            .animation 跟随屏幕刷新率每帧刷新，作用类似 CADisplayLink；手指按住拖动页面时也照常刷新。minimumInterval 限制最短刷新间隔，内容不需要每帧变化时可以省电；\
            paused 为 true 时停止刷新，视图停在最后一帧。
            """
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    RateSpinner(title: "不限", minimumInterval: nil, paused: paused)
                    RateSpinner(title: "1/30 秒", minimumInterval: 1 / 30, paused: paused)
                    RateSpinner(title: "1/5 秒", minimumInterval: 1 / 5, paused: paused)
                }
                Toggle("paused", isOn: $paused)
                    .font(.subheadline.monospaced())
            }
        }
    }
}

private struct RateSpinner: View {
    let title: String
    let minimumInterval: Double?
    let paused: Bool
    @State private var meter = UpdateMeter()

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval, paused: paused)) { context in
            let count = meter.tick(context.date)
            let angle = (context.date.timeIntervalSinceReferenceDate * 180).truncatingRemainder(dividingBy: 360)
            VStack(spacing: 6) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(angle))
                Text(title).font(.caption.weight(.semibold))
                Text("\(meter.fps, format: .number.precision(.fractionLength(0))) fps")
                    .font(.caption.monospacedDigit())
                Text("\(count) 帧")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ⑤ Canvas 动画

private struct CanvasCard: View {
    var body: some View {
        DemoCard(
            title: "⑤ 与 Canvas 组合：逐帧绘制",
            code: "TimelineView(.animation) { context in Canvas { ctx, size in … } }",
            note: """
            TimelineView 提供时间，Canvas 按时间直接绘制，适合波形、粒子、进度光效等自定义动画。\
            每帧只重新执行绘制闭包，不创建大量子视图，开销比用 ForEach 摆放很多小视图低。
            """
        ) {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, size in
                    let colors: [Color] = [.blue, .purple, .teal]
                    for (index, color) in colors.enumerated() {
                        let layer = CGFloat(index)
                        let speed = 1.6 + layer * 0.7
                        let amplitude = size.height * (0.32 - layer * 0.08)
                        let frequency = (1 + layer * 0.5) * 2 * .pi / size.width
                        var path = Path()
                        for x in stride(from: CGFloat.zero, through: size.width, by: 2) {
                            let y = size.height / 2 + sin(x * frequency + time * speed) * amplitude
                            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        graphics.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 2.5)
                    }
                }
            }
            .frame(height: 110)
        }
    }
}

// MARK: - ⑥ 秒表

private struct StopwatchCard: View {
    @State private var accumulated: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRunning: Bool { startedAt != nil }

    var body: some View {
        DemoCard(
            title: "⑥ 秒表：状态只记录开始时间",
            code: """
            TimelineView(.animation(minimumInterval: 0.01, paused: !isRunning)) { context in
                let elapsed = accumulated + context.date.timeIntervalSince(startedAt)
            }
            """,
            note: """
            @State 只保存「累计时长」和「本次开始时间」，显示的时长每次刷新时由 context.date 计算出来，不需要每 10ms 修改一次状态。\
            暂停时把本段时长加进累计值，并用 paused 停止刷新。
            """
        ) {
            VStack(spacing: 12) {
                TimelineView(.animation(minimumInterval: 0.01, paused: !isRunning)) { context in
                    let current = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
                    Text(Self.format(accumulated + current))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                }
                HStack {
                    Button(isRunning ? "暂停" : "开始") {
                        if let startedAt {
                            accumulated += Date.now.timeIntervalSince(startedAt)
                            self.startedAt = nil
                        } else {
                            startedAt = .now
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("复位") {
                        accumulated = 0
                        startedAt = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let centiseconds = Int(interval * 100)
        return String(format: "%02d:%02d.%02d", centiseconds / 6000, centiseconds / 100 % 60, centiseconds % 100)
    }
}

// MARK: - ⑦ 指定时间点

private struct ExplicitCard: View {
    private static let steps: [(offset: TimeInterval, text: String)] = [
        (0, "准备"), (1.5, "3"), (2.5, "2"), (3.5, "1"), (4.5, "出发 🚀"),
    ]
    @State private var dates: [Date] = []
    @State private var meter = UpdateMeter()

    var body: some View {
        DemoCard(
            title: "⑦ 只在指定时间点刷新：.explicit(dates)",
            code: "TimelineView(.explicit([t0, t0 + 1.5, t0 + 2.5, t0 + 3.5, t0 + 4.5])) { … }",
            note: """
            只在给定的几个时间点刷新，间隔可以不均匀，适合引导动画、分步提示、已知时刻的状态切换。\
            时间点用完后不再刷新（「已刷新」次数不再增加）；调度表变化时（再点一次「开始」），按新的时间点重新开始。\
            实测 iOS 26 上数组的最后一个时间点不会触发刷新，所以代码在末尾多加了一个时间点。
            """
        ) {
            VStack(spacing: 12) {
                TimelineView(.explicit(dates)) { context in
                    let count = meter.tick(context.date)
                    let step = dates.lastIndex { $0 <= context.date }.map { min($0, Self.steps.count - 1) }
                    VStack(spacing: 4) {
                        Text(step.map { Self.steps[$0].text } ?? "点「开始」")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: step)
                        Text("已刷新 \(count) 次")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button("开始") {
                    let start = Date.now
                    dates = Self.steps.map { start.addingTimeInterval($0.offset) }
                    // 实测（iOS 26）：数组中的最后一个时间点不会触发刷新，所以末尾多加一个时间点，
                    // 让「出发」按时出现；多加的这个点同样不会触发刷新
                    dates.append(start.addingTimeInterval(Self.steps[Self.steps.count - 1].offset + 0.5))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - ⑧ 自定义调度表

/// 自定义调度表：距离参考时间越久，刷新得越慢。
/// 1 分钟内每秒刷新，1 小时内每分钟刷新，之后每小时刷新；低频模式下不做秒级刷新。
/// 时间点对齐到参考时间的整秒 / 整分 / 整时，「x 分钟前」恰好在跨过整分钟时更新。
nonisolated struct RelativeTimeSchedule: TimelineSchedule {
    let reference: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        sequence(first: startDate) { date in
            let age = date.timeIntervalSince(reference)
            let step: TimeInterval = age < 60 && mode != .lowFrequency ? 1 : age < 3600 ? 60 : 3600
            return reference.addingTimeInterval((max(0, age) / step).rounded(.down) * step + step)
        }
    }

    static func text(for reference: Date, at date: Date) -> String {
        let age = Int(date.timeIntervalSince(reference))
        switch age {
        case ..<1: return "刚刚"
        case ..<60: return "\(age) 秒前"
        case ..<3600: return "\(age / 60) 分钟前"
        default: return "\(age / 3600) 小时前"
        }
    }
}

private struct Message: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
}

private struct CustomScheduleCard: View {
    @State private var messages: [Message] = [
        Message(text: "55 秒前发的消息", date: .now.addingTimeInterval(-55)),
        Message(text: "59 分 50 秒前发的消息", date: .now.addingTimeInterval(-3590)),
    ]

    var body: some View {
        DemoCard(
            title: "⑧ 自定义调度表：TimelineSchedule",
            code: """
            nonisolated struct RelativeTimeSchedule: TimelineSchedule {
                func entries(from startDate: Date, mode: TimelineScheduleMode) -> some Sequence<Date>
            }
            """,
            note: """
            内置调度表不够用时，实现 entries(from:mode:) 返回一串时间点即可。本例是消息列表的「x 分钟前」：\
            1 分钟内每秒刷新，之后每分钟刷新。观察第一条：满 1 分钟后刷新次数增长明显变慢。\
            mode 为 .lowFrequency 时（例如 watchOS 抬腕前）应减少刷新。
            """
        ) {
            VStack(spacing: 8) {
                ForEach(messages) { message in
                    MessageRow(message: message)
                }
                Button("发一条新消息") {
                    messages.insert(Message(text: "新消息 #\(messages.count + 1)", date: .now), at: 0)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct MessageRow: View {
    let message: Message
    @State private var meter = UpdateMeter()

    var body: some View {
        TimelineView(RelativeTimeSchedule(reference: message.date)) { context in
            let count = meter.tick(context.date)
            HStack {
                Text(message.text).font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(RelativeTimeSchedule.text(for: message.date, at: context.date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tint)
                    Text("已刷新 \(count) 次")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - ⑨ 不需要 TimelineView 的情况

private struct SelfUpdatingTextCard: View {
    @State private var start = Date.now

    var body: some View {
        DemoCard(
            title: "⑨ 不需要 TimelineView：会自己更新的 Text / ProgressView",
            code: """
            Text(start, style: .timer)
            Text(timerInterval: start...end, countsDown: true)
            ProgressView(timerInterval: start...end, countsDown: true)
            """,
            note: """
            只是显示计时、倒计时或相对时间时，用这些系统控件即可：由系统负责更新显示，不会重新计算你的 body，在小组件中也能用。\
            需要根据时间改变布局、颜色、绘制内容时，才用 TimelineView。
            """
        ) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("计时 .timer") { Text(start, style: .timer).monospacedDigit() }
                LabeledContent("相对时间 .relative") { Text(start, style: .relative) }
                LabeledContent("倒计时 30 秒") {
                    Text(timerInterval: start...start.addingTimeInterval(30), countsDown: true).monospacedDigit()
                }
                ProgressView(timerInterval: start...start.addingTimeInterval(30), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                Button("重新开始") { start = .now }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .font(.subheadline)
        }
    }
}

// MARK: - ⑩ 要点

private struct TipsCard: View {
    var body: some View {
        DemoCard(title: "⑩ 使用要点", code: "", note: "") {
            VStack(alignment: .leading, spacing: 8) {
                tip("用 context.date 计算，不要在闭包里调用 Date()：context.date 是这次刷新对应的时间点，同一次刷新中所有子视图看到的是同一个时间。")
                tip("内容闭包要轻：每次刷新都会重新计算。只把需要随时间变化的部分放进 TimelineView，不要包住整个页面。")
                tip("不要在内容闭包里修改 @State，那会引起额外的刷新。需要的状态用「开始时间 + 计算」得出（见 ⑥ 秒表）。")
                tip("调度表的时间点用完后，视图不再刷新（见 ⑦）；需要停止或改变节奏时，换一个调度表或设置 paused。")
                tip("TimelineView 在主线程上刷新：主线程被阻塞时它也会停下（见演示 App 第 2 页旋转的齿轮）。")
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - 辅助

/// 统计内容闭包被重新计算的次数和频率。
/// 它不是 @Observable，在 body 中修改它不会触发新的刷新。同一个时间点被重复计算时不计数。
private final class UpdateMeter {
    private(set) var count = 0
    private(set) var fps: Double = 0
    private var last: Date?

    func tick(_ date: Date) -> Int {
        guard date != last else { return count }
        if let last {
            let interval = date.timeIntervalSince(last)
            if interval > 0 { fps = fps == 0 ? 1 / interval : fps * 0.9 + 0.1 / interval }
        }
        count += 1
        last = date
        return count
    }
}

private extension TimelineViewDefaultContext.Cadence {
    var name: String {
        switch self {
        case .live: "live"
        case .seconds: "seconds"
        case .minutes: "minutes"
        @unknown default: "unknown"
        }
    }
}

private struct DemoCard<Content: View>: View {
    let title: String
    let code: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content.frame(maxWidth: .infinity)
            if !code.isEmpty {
                Text(code)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack { TimelineViewDemo() }
}
