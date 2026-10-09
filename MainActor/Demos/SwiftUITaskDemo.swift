//
//  SwiftUITaskDemo.swift
//  MainActor
//
//  对应文档 §8、§14：.task 与视图生命周期绑定；onAppear { Task {} } 不会自动取消；
//  .task(id:) 防抖 vs DispatchWorkItem 防抖。
//

import SwiftUI

struct SwiftUITaskDemo: View {
    @State private var console = Console()
    @State private var searchText = ""
    @State private var leakedTask: Task<Void, Never>?
    @State private var workItem: DispatchWorkItem?

    var body: some View {
        DemoScreen(
            title: ".task 与生命周期",
            summary: """
            ① 进入子页面，再返回：.task 随视图消失自动取消，onAppear 中创建的 Task 继续运行（泄漏），需要手动取消。
            ② 在搜索框快速输入：.task(id:) 每次输入取消上一次任务，停止输入 400ms 后才搜索；DispatchWorkItem 是 GCD 的等价写法。
            """,
            console: console
        ) {
            NavigationLink {
                TaskLifecycleChild(console: console) { leakedTask = $0 }
            } label: {
                Label("① 进入子页面", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            DemoButton(title: "取消 onAppear 中泄漏的 Task") {
                leakedTask?.cancel()
                leakedTask = nil
            }

            TextField("② 输入搜索关键字", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .task(id: searchText) {
            guard !searchText.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                console.log(".task(id:)：「\(searchText)」的任务被取消")
                return
            }
            console.log("🔍 .task(id:) 防抖后搜索：「\(searchText)」")
        }
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else { return }
            workItem?.cancel()
            let console = console
            let item = DispatchWorkItem { console.log("🔍 DispatchWorkItem 防抖后搜索：「\(newValue)」") }
            workItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
        }
    }
}

private struct TaskLifecycleChild: View {
    let console: Console
    let onLeak: (Task<Void, Never>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("""
            此页面启动了两个每秒打印一次的循环：
            • .task { }
            • .onAppear { Task { } }
            几秒后返回上一页，观察日志。
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()

            Divider()

            ConsoleView(console: console)
        }
        .navigationTitle("子页面")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for i in 1... {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    console.log(".task：视图消失，自动取消 ✅")
                    return
                }
                console.log(".task 循环 \(i)")
            }
        }
        .onAppear {
            let console = console
            let task = Task {
                var i = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    i += 1
                    console.log("onAppear Task 循环 \(i)（视图消失后仍在运行）")
                }
                console.log("onAppear Task：被手动取消")
            }
            onLeak(task)
        }
    }
}

#Preview {
    NavigationStack { SwiftUITaskDemo() }
}
