import SwiftUI

/// A deliberately small control set: tap to show/hide a bottom scrubber with
/// time labels and a fullscreen toggle. The video itself stays unobscured;
/// only the area behind the bottom controls receives a local dark gradient.
struct PlayerControlsOverlay: View {
    let viewModel: PlayerViewModel
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    // 进入视频页时控件默认不显示，画面不被任何东西挡住；轻点一下才唤出。
    @State private var controlsVisible = false
    /// 为 true 时，进度条和时间显示的是手指选中的位置，而不是播放器的位置。
    /// 手指抬起后它不会立刻变回 false，要等跳转真正完成，详见 `endScrub`。
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var seekTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // 这是覆盖整个视频的透明点击区域，只用来接收轻点操作。
            // Color.clear 不会改变画面亮度，所以显示控件时不再整体变暗。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            // 播放时不显示“暂停”图标和圆形底色，但保留原位置的点击热区。
            // 点击后视频会暂停，此时只显示“播放”图标，方便恢复播放。
            centerPlaybackControl
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)

            // 右上角的定时休眠按钮，跟着控件一起显隐。
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)

                    if let remaining = viewModel.sleepRemainingMinutes {
                        Text("\(remaining) 分")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: Capsule())
                    }

                    sleepTimerMenu
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            // 只让底部进度条所在的小片区域渐变变暗。
            // 这层始终存在，只改透明度，避免进度条重新插入时引起画面抖动。
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.12), location: 0.45),
                            .init(color: .black.opacity(0.62), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    bottomBar
                }
                // 这个数字是底部渐变区域的高度：越大，暗色向上延伸得越多。
                .frame(height: 90)
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        // 进出全屏同样从干净画面开始，不把上一个状态的控件带过去。
        .onChange(of: isFullScreen) {
            hideTask?.cancel()
            controlsVisible = false
        }
        .onDisappear {
            seekTask?.cancel()
            hideTask?.cancel()
        }
    }

    /// 拖动期间显示手指的位置；跳转完成前也继续显示目标位置。
    private var displayTime: Double {
        isScrubbing ? scrubTime : viewModel.currentTime
    }

    private var centerPlaybackControl: some View {
        Button {
            viewModel.togglePlayPause()
            scheduleAutoHide()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(viewModel.isPlaying ? 0 : 0.4))

                Image(systemName: "play.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .opacity(viewModel.isPlaying ? 0 : 1)
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .accessibilityLabel(viewModel.isPlaying ? "暂停" : "播放")
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(PlayerViewModel.sleepOptions, id: \.self) { option in
                sleepMenuButton(option)
            }

            sleepMenuButton(.afterVideoEnd)

            if viewModel.isSleepTimerActive {
                Divider()
                Button("取消定时", role: .destructive) {
                    viewModel.cancelSleepTimer()
                }
            }
        } label: {
            Image(systemName: viewModel.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("定时休眠")
        .accessibilityValue(viewModel.isSleepTimerActive ? "已开启" : "未开启")
    }

    private func sleepMenuButton(_ option: PlayerViewModel.SleepOption) -> some View {
        Button {
            viewModel.setSleepTimer(option)
        } label: {
            if viewModel.selectedSleepOption == option {
                Label(title(for: option), systemImage: "checkmark")
            } else {
                Text(title(for: option))
            }
        }
    }

    private func title(for option: PlayerViewModel.SleepOption) -> String {
        switch option {
        case .afterVideoEnd: return "本视频播完"
        case .minutes(let minutes):
            return minutes >= 60 && minutes % 60 == 0
                ? "\(minutes / 60) 小时"
                : "\(minutes) 分钟"
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(PlaybackTime.text(displayTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            VideoScrubber(
                position: displayTime,
                buffered: viewModel.bufferedTime,
                duration: viewModel.duration,
                onScrub: scrub(to:),
                onScrubEnd: endScrub(at:)
            )

            Text(PlaybackTime.text(viewModel.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Button {
                onToggleFullScreen()
                scheduleAutoHide()
            } label: {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// 手指按下和移动：只更新界面，视频继续按原来的位置播放。
    private func scrub(to time: Double) {
        // 正在操作进度条时不能把控件收起来。
        hideTask?.cancel()
        isScrubbing = true
        scrubTime = time
    }

    /// 手指抬起：执行唯一一次跳转。
    ///
    /// 关键在于这里不立刻把 `isScrubbing` 设回 false。播放器要过一会儿才走到新位置，
    /// 提前交还控制权，界面就会先显示跳转前的旧时间，再跳到目标位置——也就是松手时看到的那一下回跳。
    private func endScrub(at time: Double) {
        isScrubbing = true
        scrubTime = time
        seekTask?.cancel()
        seekTask = Task {
            await viewModel.seek(to: time)
            // 已经开始下一次拖动时，位置由那一次接管，这里不要抢回来。
            guard !Task.isCancelled else { return }
            isScrubbing = false
            scheduleAutoHide()
        }
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { scheduleAutoHide() }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard viewModel.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}
