import SwiftUI

@main
struct CommentLabApp: App {
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup {
            LabRootView()
                .environment(model)
                .tint(LabModel.tint)
                .preferredColorScheme(model.dark ? .dark : .light)
                .environment(\.dynamicTypeSize, model.largeText ? .xxxLarge : .large)
        }
    }
}

struct LabRootView: View {
    @Environment(LabModel.self) private var model
    @State private var deletionAfterSheet: CommentActionTarget?

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            LabCommentList()
                .navigationTitle(model.scene.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(LabVariant.allCases) { variant in
                                Button {
                                    model.variant = variant
                                } label: {
                                    Label("\(variant.rawValue) · \(variant.title)", systemImage: model.variant == variant ? "checkmark" : "circle")
                                }
                                .accessibilityIdentifier("variant.\(variant.rawValue)")
                            }
                        } label: {
                            Text("\(model.variant.rawValue) · \(model.variant.title)").font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("切换方案")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("对比设置", systemImage: "slider.horizontal.3") { model.showComparison = true }
                            .accessibilityIdentifier("lab.settings")
                    }
                }
                .navigationDestination(for: LabRoute.self) { route in
                    switch route {
                    case .author(let author): LabProfileView(author: author)
                    case .thread(let id): LabThreadView(rootID: id)
                    }
                }
        }
        .sheet(isPresented: $model.showComparison) { LabComparisonSheet() }
        .sheet(isPresented: $model.showImage) { LabPhotoViewer() }
        .sheet(item: $model.actionSheet, onDismiss: {
            model.pendingDeletion = deletionAfterSheet
            deletionAfterSheet = nil
        }) { target in
            NavigationStack {
                List {
                    Button("复制全文", systemImage: "doc.on.doc") {
                        model.copy(target.comment)
                        model.actionSheet = nil
                    }
                    if target.comment.isMine {
                        Button("删除评论", systemImage: "trash", role: .destructive) {
                            deletionAfterSheet = target
                            model.actionSheet = nil
                        }
                    }
                }
                .scrollDisabled(true)
                .navigationTitle("评论操作")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { model.actionSheet = nil }
                    }
                }
            }
            .presentationDetents([.height(model.largeText ? 290 : 230)])
            .presentationDragIndicator(.visible)
        }
        .alert("删除这条评论？", isPresented: Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } }),
               presenting: model.pendingDeletion) { target in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { Task { await model.delete(target) } }
        } message: { _ in
            Text("删除后无法恢复。")
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .padding(.top, 58)
                    .accessibilityIdentifier("lab.notice")
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct LabCommentList: View {
    @Environment(LabModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LabContentHeader()
                    LabSortHeader().id("comments-top")
                    ForEach(model.orderedComments) { comment in
                        LabCommentRow(comment: comment)
                    }
                    Text("没有更多评论了")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            }
            .accessibilityIdentifier("comments.list")
            .accessibilityValue(model.hasRefreshed ? "评论已刷新" : "")
            .refreshable { await model.refresh() }
            .onChange(of: model.sort) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("comments-top", anchor: .top) }
            }
            .onChange(of: model.revision) { _, _ in proxy.scrollTo("comments-top", anchor: .top) }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { LabComposer(rootID: nil) }
    }
}

struct LabThreadView: View {
    let rootID: Int
    @Environment(LabModel.self) private var model

    var body: some View {
        ScrollView {
            if let root = model.comment(rootID) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LabCommentRow(comment: root, showsReplies: false)
                    Divider().padding(.horizontal, 16)
                    Text("全部回复 \(root.replies.count)")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 4)
                    ForEach(root.replies) { reply in
                        LabCommentRow(comment: reply, rootID: rootID, showsReplies: false)
                    }
                }
            }
        }
        .accessibilityIdentifier("thread.list")
        .accessibilityValue(model.hasRefreshed ? "评论已刷新" : "")
        .refreshable { await model.refresh() }
        .navigationTitle("回复")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { LabComposer(rootID: rootID) }
    }
}

private struct LabSortHeader: View {
    @Environment(LabModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("评论 \(model.comments.count)").font(.headline)
                Spacer(minLength: 8)
                if model.variant == .a {
                    Menu {
                        Picker("评论排序", selection: $model.sort) {
                            ForEach(LabSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.sort.rawValue)
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }.font(.subheadline).foregroundStyle(Color.secondary)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("评论排序，\(model.sort.rawValue)")
                    .accessibilityIdentifier("sort.menu")
                } else if model.variant == .b {
                    HStack(spacing: 18) {
                        ForEach(LabSort.allCases) { sort in
                            Button { model.sort = sort } label: {
                                VStack(spacing: 5) {
                                    Text(sort.rawValue).font(.subheadline.weight(model.sort == sort ? .semibold : .regular))
                                    Capsule().fill(model.sort == sort ? LabModel.tint : .clear).frame(height: 2)
                                }.fixedSize(horizontal: true, vertical: false).padding(.top, 7)
                                    .frame(minHeight: 44)
                            }
                            .foregroundStyle(model.sort == sort ? .primary : .secondary)
                            .accessibilityAddTraits(model.sort == sort ? .isSelected : [])
                            .accessibilityIdentifier("sort.\(sort.id)")
                        }
                    }
                }
            }
            if model.variant == .c {
                Picker("评论排序", selection: $model.sort) {
                    ForEach(LabSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sort.segmented")
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }
}

struct LabComposer: View {
    let rootID: Int?
    @Environment(LabModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if let target = model.replyTarget {
                    HStack {
                        Text("回复 @\(target.comment.author.name)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("取消") { model.replyTarget = nil }.font(.caption)
                    }
                }
                TextField("写下你的评论…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4).font(.body).focused($focused)
                    .accessibilityIdentifier("comment.draft")
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
            if focused || !model.draft.isEmpty {
                Button {
                    model.submit(in: rootID)
                    focused = false
                } label: {
                    Image(systemName: "arrow.up").font(.headline)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white).background(LabModel.tint, in: Circle())
                }
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送示例评论")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.bar)
        .onChange(of: model.replyTarget?.id) { _, id in if id != nil { focused = true } }
    }
}

private struct LabComparisonSheet: View {
    @Environment(LabModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("视觉方案") {
                    ForEach(LabVariant.allCases) { variant in
                        Button { model.variant = variant } label: {
                            HStack(spacing: 12) {
                                Text(variant.rawValue).font(.title3.weight(.semibold))
                                    .frame(width: 38, height: 38)
                                    .background(LabModel.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variant.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(variant.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if model.variant == variant { Image(systemName: "checkmark") }
                            }.padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("settings.variant.\(variant.rawValue)")
                    }
                }
                Section("查看效果") {
                    Picker("评论场景", selection: $model.scene) {
                        ForEach(LabScene.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("深色外观", isOn: $model.dark)
                    Toggle("大字号", isOn: $model.largeText)
                }
                Section {
                    Toggle("模拟删除失败", isOn: $model.failDeletion)
                    Button("恢复全部示例") { model.reset(); dismiss() }
                } header: { Text("交互演示") } footer: {
                    Text("所有评论、主页和画面均为本地示例。删除仅修改这份交互稿；复制会写入系统剪贴板。")
                }
            }
            .navigationTitle("对比设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
