import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Network Device metadata, distinct from the Neuron AppInfo and fingerprint material.
/// Field numbers/types: 8.89 BAPIMetadataDeviceDevice descriptor (0x116225ebc,
/// fields 0x12086c038); value providers: 0x115e0d26c–0x115e0d5d4.
/// Build/version follow NeoBili's declared compatibility identity; physical facts
/// come from this installation, never from a captured official-device snapshot.
enum AppDeviceMetadata {
    struct LocalSnapshot: Sendable {
        var device: String
        var model: String
        var osVersion: String
    }

    static func localSnapshot() async -> LocalSnapshot {
        #if canImport(UIKit)
        return await MainActor.run {
            LocalSnapshot(device: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
                          model: AppClientIdentity.deviceName, osVersion: UIDevice.current.systemVersion)
        }
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return LocalSnapshot(device: "phone", model: AppClientIdentity.deviceName,
                             osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        #endif
    }

    static func build(buvid: String, guestID: Int64?, fingerprint: String?,
                      firstTrackTime: Int? = nil) async -> Data {
        encode(local: await localSnapshot(), buvid: buvid, guestID: guestID,
               fingerprint: fingerprint, firstTrackTime: firstTrackTime)
    }

    static func encode(local: LocalSnapshot, buvid: String, guestID: Int64?, fingerprint: String?,
                       firstTrackTime: Int? = nil) -> Data {
        // GPB setters explicitly assign these strings, including empty fpLocal/fpRemote.
        func string(_ field: Int, _ value: String) -> Data { AppProto.bytes(field, Data(value.utf8)) }
        var data = AppProto.integer(1, 1) + AppProto.integer(2, Int(AppClientIdentity.build) ?? 0)
        data += string(3, buvid) + string(4, AppClientIdentity.mobiApp) + string(5, "ios")
        data += string(6, local.device) + string(7, "pink_overseas") + string(8, "Apple")
        data += string(9, local.model) + string(10, local.osVersion)
        data += string(11, "") + string(12, "") + string(13, AppClientIdentity.version)
        data += string(14, fingerprint ?? "")
        // Do not replace the installation's first-track timestamp with request time.
        if let firstTrackTime, firstTrackTime > 0 { data += AppProto.integer(15, firstTrackTime) }
        if let guestID { data += string(16, String(guestID)) }
        return data
    }
}
