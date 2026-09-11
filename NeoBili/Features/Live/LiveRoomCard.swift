import SwiftUI

struct LiveRoomCard: View {
    let room: LiveRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverThumbnail(url: room.coverURL)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                }
                .overlay(alignment: .topLeading) {
                    Text(room.isLive ? "直播中" : "未开播")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(room.isLive ? Color.red.opacity(0.9) : Color.black.opacity(0.55), in: Capsule())
                        .padding(7)
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
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(room.title.isEmpty ? "直播间 \(room.roomID)" : room.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)

            HStack(spacing: 5) {
                if let face = room.faceURL {
                    BiliImage(url: face)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                }
                Text(room.username.isEmpty ? "房间 \(room.roomID)" : room.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room.username)，\(room.title)，\(room.isLive ? "直播中" : "未开播")")
        .accessibilityHint("打开直播间")
        .videoCardEntrance()
    }
}
