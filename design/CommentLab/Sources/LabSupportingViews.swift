import SwiftUI

struct LabAvatar: View {
    let author: LabAuthor
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(author.color.gradient)
            Image(systemName: author.symbol)
                .font(.system(size: size * 0.43, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct LabContentHeader: View {
    @Environment(LabModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.scene == .video {
                ZStack(alignment: .bottomLeading) {
                    LabLandscape()
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("去山里，找一个没有信号的下午")
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(model.playbackTime) / 08:42")
                                .font(.caption.monospacedDigit()).opacity(0.8)
                        }
                        Spacer(minLength: 8)
                        Button { model.isPlaying.toggle() } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3).frame(width: 44, height: 44)
                                .background(.white.opacity(0.16), in: Circle())
                        }
                        .accessibilityLabel(model.isPlaying ? "暂停示例播放" : "继续示例播放")
                    }
                    .foregroundStyle(.white).padding(16)
                }
                .frame(height: 130).clipped()
                HStack(spacing: 28) {
                    Text("简介").foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Text("评论").fontWeight(.semibold)
                        Capsule().fill(LabModel.tint).frame(width: 20, height: 3)
                    }.padding(.top, 11)
                    Text("合集").foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.subheadline).padding(.horizontal, 20).frame(height: 42)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        LabAvatar(author: .uploader, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LabAuthor.uploader.name).font(.subheadline.weight(.semibold))
                            Text("3小时前").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("山里的风，和一个不赶时间的下午。🌿").font(.body)
                    LabLandscape().frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
            Divider()
        }
    }
}

/// Local vector fixture: the lab has no images, playback streams or API traffic to fetch.
struct LabLandscape: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.64, green: 0.77, blue: 0.76), Color(red: 0.88, green: 0.90, blue: 0.78)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 0.98, green: 0.90, blue: 0.66)).frame(width: 40, height: 40)
                    .position(x: geometry.size.width * 0.77, y: geometry.size.height * 0.23)
                MountainRidge(crest: 0.20, offset: 0.15).fill(Color(red: 0.44, green: 0.61, blue: 0.54))
                MountainRidge(crest: 0.39, offset: 0.47).fill(Color(red: 0.25, green: 0.45, blue: 0.39))
                MountainRidge(crest: 0.68, offset: 0.08).fill(Color(red: 0.16, green: 0.33, blue: 0.28))
                Image(systemName: "house.fill").font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.93, green: 0.84, blue: 0.65))
                    .position(x: geometry.size.width * 0.63, y: geometry.size.height * 0.71)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MountainRidge: Shape {
    let crest: CGFloat
    let offset: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.height * (crest + 0.28)))
            p.addCurve(to: CGPoint(x: rect.width, y: rect.height * (crest + 0.13)),
                       control1: CGPoint(x: rect.width * offset, y: rect.height * (crest - 0.22)),
                       control2: CGPoint(x: rect.width * (offset + 0.5), y: rect.height * (crest + 0.25)))
            p.addLine(to: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            p.closeSubpath()
        }
    }
}

struct LabProfileView: View {
    let author: LabAuthor
    @State private var followed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LabLandscape().frame(height: 145)
                    .overlay(alignment: .bottomLeading) {
                        LabAvatar(author: author, size: 72)
                            .padding(4).background(.background, in: Circle())
                            .offset(y: 25).padding(.leading, 20)
                    }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(author.name).font(.title3.weight(.semibold))
                            Text("把日常过成喜欢的样子。").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if author != .me {
                            Button(followed ? "已关注" : "关注") { followed.toggle() }.buttonStyle(.bordered)
                        }
                    }
                    Text("\(author == .uploader ? "12.8万" : "128") 粉丝   ·   86 关注")
                        .font(.footnote).foregroundStyle(.secondary)
                    Divider()
                    Text("投稿").font(.headline)
                    LabLandscape().frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("去山里，找一个没有信号的下午").font(.body)
                }.padding(.horizontal, 20).padding(.top, 22)
            }
        }
        .navigationTitle("个人主页")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("author.profile")
    }
}

struct LabPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    var body: some View {
        NavigationStack {
            LabLandscape()
                .aspectRatio(1.45, contentMode: .fit)
                .scaleEffect(scale * magnification)
                .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { scale = min(4, max(1, scale * $0.magnification)) })
                .onTapGesture(count: 2) { withAnimation { scale = scale == 1 ? 2 : 1 } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationTitle("1 / 1")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
