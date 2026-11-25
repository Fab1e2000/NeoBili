import NeoBiliDomain
import SwiftUI

struct CastDevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let castSession: CastSessionModel
    let mediaTitle: String
    let onSelectDevice: (CastDevice) -> Void

    @State private var manualAddress = ""
    @State private var isAddingManual = false
    @State private var manualError: String?
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            List {
                if !mediaTitle.isEmpty {
                    Section {
                        Label {
                            Text(mediaTitle)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: "tv.badge.wifi")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                if !castSession.recentDevices.isEmpty {
                    Section("最近使用") {
                        ForEach(castSession.recentDevices) { device in
                            deviceRow(device)
                                .swipeActions(edge: .trailing) {
                                    Button("移除", role: .destructive) {
                                        castSession.removeRecentDevice(device)
                                    }
                                }
                        }
                    }
                }

                Section {
                    if castSession.devices.isEmpty {
                        if castSession.isDiscovering {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("正在搜索局域网内的投屏设备…")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("暂未发现 DLNA 投屏设备")
                                    .font(.app(.headline))
                                Text("请确认手机与电视/接收端处于同一 Wi-Fi，并已授予本地网络权限。")
                                    .font(.app(.footnote))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    } else {
                        ForEach(castSession.devices) { device in
                            deviceRow(device)
                        }
                    }
                } header: {
                    HStack {
                        Text("局域网设备")
                        Spacer()
                        if castSession.isDiscovering {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                } footer: {
                    if let error = castSession.discoveryError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    DisclosureGroup("手动添加设备地址", isExpanded: $showManualEntry) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("http://192.168.x.x:port/description.xml", text: $manualAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.go)
                                .onSubmit { addManual() }

                            if let manualError {
                                Text(manualError)
                                    .font(.app(.caption))
                                    .foregroundStyle(.red)
                            }

                            Button {
                                addManual()
                            } label: {
                                HStack {
                                    if isAddingManual {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(isAddingManual ? "正在连接…" : "连接并投屏")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAddingManual || manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("若系统未发现设备（例如跨网段或未启用多播），可直接输入电视或 Macast/Kodi 的 UPnP 描述地址。")
                }
            }
            .navigationTitle("投屏到设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        castSession.discover()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(castSession.isDiscovering)
                    .accessibilityLabel("重新搜索设备")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            castSession.discover()
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: CastDevice) -> some View {
        Button {
            dismiss()
            onSelectDevice(device)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.app(.body))
                        .foregroundStyle(.primary)
                    Text(device.subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if castSession.activeDevice?.id == device.id, castSession.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addManual() {
        guard !isAddingManual else { return }
        manualError = nil
        isAddingManual = true
        let address = manualAddress
        Task {
            defer { isAddingManual = false }
            do {
                let device = try await castSession.addManualDevice(address: address)
                dismiss()
                onSelectDevice(device)
            } catch {
                manualError = error.localizedDescription
            }
        }
    }
}
