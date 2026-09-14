import SwiftUI

/// 全屏时铺在直播画面上的实时飘幕层。引擎挂在模型上，
/// 新弹幕到达即从右缘进入，不依赖任何播放时间轴。
struct LiveDanmakuFlowView: UIViewRepresentable {
    @AppStorage(DanmakuSettings.coloredEnabledKey) private var coloredEnabled = true
    let model: LiveDanmakuModel

    func makeUIView(context: Context) -> DanmakuEngine {
        let engine = DanmakuEngine()
        engine.mode = .live
        model.attach(flowEngine: engine)
        return engine
    }

    func updateUIView(_ engine: DanmakuEngine, context: Context) {
        engine.coloredEnabled = coloredEnabled
        engine.fontSize = 18
        engine.area = 0.5
    }

    static func dismantleUIView(_ engine: DanmakuEngine, coordinator: ()) {
        engine.removeFromSuperview()
    }
}

/// 非全屏时位于播放器下方的独立弹幕容器：SC 置顶 + 实时弹幕列表。
struct LiveDanmakuPanel: View {
    @Bindable var model: LiveDanmakuModel
    @AppStorage(DanmakuSettings.liveEnabledKey) private var flowEnabled = DanmakuSettings.defaultValue

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var lastScrollAt = Date.distantPast
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.superChats.isEmpty {
                superChatStrip
            }
            messageList
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("直播间弹幕")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.connection == .connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
            Text("弹幕")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            if let popularity = model.popularity {
                Text(Self.popularityText(popularity))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                flowEnabled.toggle()
            } label: {
                DanmakuBadge(isEnabled: flowEnabled)
                    .font(.system(size: 11, weight: .bold))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(flowEnabled ? "关闭飘幕" : "开启飘幕")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var superChatStrip: some View {
        // TimelineView 每秒重算倒计时，过期卡片就地消失；模型在下次 SC 到达时清理。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.superChats.filter { $0.remaining(at: context.date.timeIntervalSince1970) > 0 }) { item in
                        SuperChatCard(item: item, now: context.date.timeIntervalSince1970, isCompact: true) {
                            model.hideSuperChat(item.id)
                        }
                        .frame(width: 240)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private var messageList: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(model.messages) { message in
                        DanmakuMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            .onChange(of: model.messages.last?.id) { _, _ in
                scrollToLatest()
            }
            .onAppear { scrollToLatest() }
            .onDisappear { scrollTask?.cancel(); scrollTask = nil }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    /// 新消息始终跟随到底部；布局完成后执行，不因内容增长误判为用户离底。
    private func scrollToLatest() {
        guard scrollTask == nil else { return }
        let delay = max(0, 0.15 - Date().timeIntervalSince(lastScrollAt))
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            await Task.yield()
            guard !Task.isCancelled else { return }
            lastScrollAt = Date()
            // No trailing animation to compete with a continuous message burst.
            position.scrollTo(edge: .bottom)
            scrollTask = nil
        }
    }

    private static func popularityText(_ value: Int) -> String {
        value >= 10_000 ? String(format: "%.1f万人气", Double(value) / 10_000) : "\(value) 人气"
    }
}

/// 单条弹幕：[粉丝牌] 名字：内容；表情弹幕（dm_type=1）整条渲染成图片。
struct DanmakuMessageRow: View {
    @AppStorage(DanmakuSettings.coloredEnabledKey) private var coloredEnabled = true
    let message: LiveDanmakuModel.Message

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let emoteURL = message.emoteURL {
                emoteRow(emoteURL)
            } else {
                textRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 表情行：基线对齐下图片行高单独算，不再和文字混排。
    private func emoteRow(_ url: URL) -> some View {
        HStack(alignment: .center, spacing: 4) {
            if let medal = message.medal { medalBadge(medal) }
            Text(message.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            BiliImage(url: url)
                .aspectRatio(contentMode: .fit)
                .frame(height: emoteHeight)
        }
    }

    private var textRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let medal = message.medal { medalBadge(medal) }
            Text(message.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(textColor)
                .lineLimit(3)
        }
    }

    private func medalBadge(_ medal: LiveDanmakuModel.Medal) -> some View {
        Text("\(medal.name) \(medal.level)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    /// 表情显示高度：用服务端下发的原始宽高比，无尺寸信息时按 32pt。
    private var emoteHeight: CGFloat {
        guard let size = message.emoteSize, size.height > 0 else { return 32 }
        return min(40, max(20, size.height == size.width ? 32 : 32))
    }

    private var textColor: Color {
        guard coloredEnabled, let color = message.color, color != 0xFF_FFFF, color != 0 else {
            return Color.primary
        }
        return Color(red: Double((color >> 16) & 0xFF) / 255,
                     green: Double((color >> 8) & 0xFF) / 255,
                     blue: Double(color & 0xFF) / 255)
    }
}

/// SC 卡片：上半（底色区）头像+名字+价格，下半（深色区）留言；右上角倒计时。
/// 容器置顶与全屏横幅共用，`isCompact` 只调文字与间距。
struct SuperChatCard: View {
    let item: LiveDanmakuModel.SuperChat
    let now: TimeInterval
    var isCompact = false
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BiliImage(url: item.faceURL)
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.userName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                    Text("¥\(item.price)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(item.priceColor)
                }
                Spacer(minLength: 0)
                countdown
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭这条醒目留言")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(item.backgroundColor)
            Text(item.message)
                .font(isCompact ? .caption : .callout)
                .foregroundStyle(item.fontColor)
                .lineLimit(isCompact ? 2 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.bottomColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.userName)的\(item.price)元醒目留言：\(item.message)")
    }

    private var avatarSize: CGFloat { isCompact ? 26 : 34 }

    private var countdown: some View {
        let remaining = max(0, Int(item.remaining(at: now)))
        return Text(remaining > 0 ? "\(remaining)s" : "")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(item.priceColor)
    }
}

/// 全屏时盖在直播画面左下角的最新 SC 横幅（PiliPlus 同位置：宽 255、
/// 有效展示时间压到最多 10 秒）。
struct SuperChatBanner: View {
    let item: LiveDanmakuModel.SuperChat
    var onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970
            let displayEnd = min(item.end, now + 10)
            guard displayEnd > now else { return AnyView(EmptyView()) }
            return AnyView(
                SuperChatCard(item: item, now: now, isCompact: false, onClose: onClose)
                    .frame(width: 255)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
            )
        }
    }
}
