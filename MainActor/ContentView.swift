//
//  ContentView.swift
//  MainActor
//
//  Created by Zhihui Tang on 2026-10-02.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("主线程调度") {
                    DemoLink(title: "1. 执行时机", subtitle: "MainActor / DispatchQueue.main / RunLoop.main / Task 的执行顺序", icon: "list.number") {
                        OrderingDemo()
                    }
                    DemoLink(title: "2. 阻塞 vs 挂起", subtitle: "Task {} / detached / global / nonsending / @concurrent 谁会卡 UI", icon: "tortoise") {
                        BlockingDemo()
                    }
                    DemoLink(title: "3. RunLoop Mode 与滚动", subtitle: "滚动时哪些定时器 / 调度方式会暂停", icon: "scroll") {
                        RunLoopModeDemo()
                    }
                }

                Section("Swift Concurrency") {
                    DemoLink(title: "4. Task 继承了什么", subtitle: "Task / Task.detached / GCD / async let / TaskGroup：隔离、优先级、TaskLocal、取消", icon: "arrow.triangle.branch") {
                        TaskInheritanceDemo()
                    }
                    DemoLink(title: "5. 结构化并发", subtitle: "顺序 await vs async let vs TaskGroup，限流与错误取消", icon: "square.stack.3d.up") {
                        StructuredConcurrencyDemo()
                    }
                    DemoLink(title: "6. actor 串行与重入", subtitle: "actor 保证串行，但 await 处可重入", icon: "person.2.badge.gearshape") {
                        ActorReentrancyDemo()
                    }
                    DemoLink(title: "7. 桥接旧 API", subtitle: "Continuation / AsyncStream / MainActor.assumeIsolated", icon: "arrow.left.arrow.right") {
                        BridgingDemo()
                    }
                }

                Section("GCD / OperationQueue") {
                    DemoLink(title: "8. GCD 工具箱", subtitle: "Group / Semaphore / 串行 vs 并发 / barrier / concurrentPerform / 线程爆炸", icon: "square.grid.3x3") {
                        GCDToolsDemo()
                    }
                    DemoLink(title: "9. OperationQueue", subtitle: "依赖、最大并发数、取消、暂停", icon: "point.3.connected.trianglepath.dotted") {
                        OperationQueueDemo()
                    }
                }

                Section("线程安全") {
                    DemoLink(title: "10. 数据竞争与锁", subtitle: "无保护 vs NSLock / Mutex / Atomic / 串行队列 / actor", icon: "lock") {
                        DataRaceDemo()
                    }
                }

                Section("SwiftUI") {
                    DemoLink(title: "11. .task 与生命周期", subtitle: ".task 自动取消 vs onAppear { Task {} }，.task(id:) 防抖", icon: "swift") {
                        SwiftUITaskDemo()
                    }
                }
            }
            .navigationTitle("Swift 并发演示")
        }
    }
}

private struct DemoLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }
}

#Preview {
    ContentView()
}
