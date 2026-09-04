import CoreImage
import SwiftUI

/// 扫码登录页：生成二维码并每 2 秒轮询一次，直到手机确认或二维码过期。
/// 同一台设备上登录时，先「保存二维码」，再在哔哩哔哩 App 的「扫一扫 → 相册」
/// 里选这张图完成确认。
struct QRLoginSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case generating
        case waiting
        case scanned
        case expired
        case succeeded
        case failed(String)
    }

    @State private var phase: Phase = .generating
    @State private var qrImage: UIImage?
    /// 「刷新二维码」按钮改这个计数器，.task(id:) 会重新跑整个生成-轮询循环。
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                codeArea
                    .frame(width: 232, height: 232)

                statusLabel
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40)

                Spacer()

                Text("用「哔哩哔哩」App 扫一扫登录。同一台手机：先保存二维码，再在 B 站 App 扫一扫里从相册选择。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let qrImage, phase != .succeeded {
                        Button("保存二维码") {
                            UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .task(id: attempt) { await runLoginLoop() }
        }
    }

    // MARK: - 区域

    @ViewBuilder
    private var codeArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                )

            switch phase {
            case .generating:
                ProgressView()
            case .expired:
                expiredPrompt
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(16)
            case .waiting, .scanned:
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .overlay {
                            // 已扫码后盖一层提示，避免用户继续对着旧码等结果。
                            if phase == .scanned {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.thinMaterial)
                                VStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.title2)
                                    Text("已扫码，请在手机上确认")
                                        .font(.caption.weight(.medium))
                                }
                                .padding(12)
                            }
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var expiredPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("二维码已过期")
                .font(.subheadline)
            Button("刷新二维码") { attempt += 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var statusLabel: some View {
        switch phase {
        case .generating: Text("正在生成二维码…")
        case .waiting: Text("打开「哔哩哔哩」App 扫一扫")
        case .scanned: Text("已扫码，请在手机上确认登录")
        case .expired: Text("二维码有效期约 3 分钟")
        case .succeeded: Text("登录成功")
        case .failed(let message): Text(message)
        }
    }

    // MARK: - 登录循环

    private func runLoginLoop() async {
        phase = .generating
        qrImage = nil
        do {
            let info = try await BiliPassport.generateQRCode()
            guard !Task.isCancelled else { return }
            qrImage = Self.makeQRCodeImage(info.url)
            phase = .waiting

            while !Task.isCancelled {
                switch try await BiliPassport.pollQRCode(info.qrcodeKey) {
                case .waiting:
                    phase = .waiting
                case .scanned:
                    phase = .scanned
                case .expired:
                    phase = .expired
                    return
                case .confirmed(let cookies):
                    phase = .succeeded
                    await account.completeLogin(cookies)
                    try? await Task.sleep(for: .seconds(0.8))
                    dismiss()
                    return
                }
                try await Task.sleep(for: .seconds(2))
            }
        } catch is CancellationError {
            // 页面关闭属于正常取消。
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func makeQRCodeImage(_ content: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
