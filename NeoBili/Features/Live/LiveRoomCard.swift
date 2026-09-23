import SwiftUI

struct LiveRoomCard: View {
    let room: LiveRoom

    var body: some View {
        LiveRoomCardContent(room: room)
            .equatable()
            .videoCardEntrance()
    }
}

private struct LiveRoomCardContent: View, Equatable {
    let room: LiveRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverThumbnail(url: room.coverURL)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 4) {
                        Text(room.areaName).lineLimit(1)
                        Spacer(minLength: 0)
                        if room.online > 0 {
                            Label(room.online.biliCountText, systemImage: "flame.fill")
                                .fixedSize()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(7)
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(room.title.isEmpty ? "直播间 \(room.roomID)" : room.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)

                HStack(spacing: 5) {
                    if let face = room.faceURL {
                        BiliImage(url: face)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 16, height: 16)
                            .clipShape(Circle())
                    }
                    Text(room.username.isEmpty ? "房间 \(room.roomID)" : room.username)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(height: 81, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room.username)，\(room.title)，\(room.isLive ? "直播中" : "未开播")")
        .accessibilityHint("打开直播间")
    }
}
