import Foundation

public struct CastService: Sendable {
    public var discoverDevicesOperation: @Sendable (TimeInterval) async throws -> [CastDevice] = { _ in
        throw ServiceError.unconfigured("Cast.discoverDevices")
    }
    public var inspectDeviceOperation: @Sendable (URL) async throws -> CastDevice = { _ in
        throw ServiceError.unconfigured("Cast.inspectDevice")
    }
    public var startCastingOperation: @Sendable (CastDevice, CastMediaRequest) async throws -> Void = { _, _ in
        throw ServiceError.unconfigured("Cast.startCasting")
    }
    public var playOperation: @Sendable (CastDevice) async throws -> Void = { _ in
        throw ServiceError.unconfigured("Cast.play")
    }
    public var pauseOperation: @Sendable (CastDevice) async throws -> Void = { _ in
        throw ServiceError.unconfigured("Cast.pause")
    }
    public var stopOperation: @Sendable (CastDevice) async throws -> Void = { _ in
        throw ServiceError.unconfigured("Cast.stop")
    }
    public var seekOperation: @Sendable (CastDevice, TimeInterval) async throws -> Void = { _, _ in
        throw ServiceError.unconfigured("Cast.seek")
    }
    public var positionInfoOperation: @Sendable (CastDevice) async throws -> CastPlaybackPosition = { _ in
        throw ServiceError.unconfigured("Cast.positionInfo")
    }
    public var transportStateOperation: @Sendable (CastDevice) async throws -> CastTransportState = { _ in
        throw ServiceError.unconfigured("Cast.transportState")
    }
    public var volumeOperation: @Sendable (CastDevice) async throws -> Int = { _ in
        throw ServiceError.unconfigured("Cast.volume")
    }
    public var setVolumeOperation: @Sendable (CastDevice, Int) async throws -> Void = { _, _ in
        throw ServiceError.unconfigured("Cast.setVolume")
    }
    public var stopServerOperation: @Sendable () async -> Void = {}

    public func discoverDevices(timeout: TimeInterval = 3.0) async throws -> [CastDevice] {
        try await discoverDevicesOperation(timeout)
    }

    public func inspectDevice(location: URL) async throws -> CastDevice {
        try await inspectDeviceOperation(location)
    }

    public func startCasting(device: CastDevice, media: CastMediaRequest) async throws {
        try await startCastingOperation(device, media)
    }

    public func play(device: CastDevice) async throws {
        try await playOperation(device)
    }

    public func pause(device: CastDevice) async throws {
        try await pauseOperation(device)
    }

    public func stop(device: CastDevice) async throws {
        try await stopOperation(device)
    }

    public func seek(device: CastDevice, to seconds: TimeInterval) async throws {
        try await seekOperation(device, seconds)
    }

    public func positionInfo(device: CastDevice) async throws -> CastPlaybackPosition {
        try await positionInfoOperation(device)
    }

    public func transportState(device: CastDevice) async throws -> CastTransportState {
        try await transportStateOperation(device)
    }

    public func volume(device: CastDevice) async throws -> Int {
        try await volumeOperation(device)
    }

    public func setVolume(device: CastDevice, to level: Int) async throws {
        try await setVolumeOperation(device, max(0, min(100, level)))
    }

    public func stopServer() async {
        await stopServerOperation()
    }

    public init(
        discoverDevicesOperation: @escaping @Sendable (TimeInterval) async throws -> [CastDevice] = { _ in
            throw ServiceError.unconfigured("Cast.discoverDevices")
        },
        inspectDeviceOperation: @escaping @Sendable (URL) async throws -> CastDevice = { _ in
            throw ServiceError.unconfigured("Cast.inspectDevice")
        },
        startCastingOperation: @escaping @Sendable (CastDevice, CastMediaRequest) async throws -> Void = { _, _ in
            throw ServiceError.unconfigured("Cast.startCasting")
        },
        playOperation: @escaping @Sendable (CastDevice) async throws -> Void = { _ in
            throw ServiceError.unconfigured("Cast.play")
        },
        pauseOperation: @escaping @Sendable (CastDevice) async throws -> Void = { _ in
            throw ServiceError.unconfigured("Cast.pause")
        },
        stopOperation: @escaping @Sendable (CastDevice) async throws -> Void = { _ in
            throw ServiceError.unconfigured("Cast.stop")
        },
        seekOperation: @escaping @Sendable (CastDevice, TimeInterval) async throws -> Void = { _, _ in
            throw ServiceError.unconfigured("Cast.seek")
        },
        positionInfoOperation: @escaping @Sendable (CastDevice) async throws -> CastPlaybackPosition = { _ in
            throw ServiceError.unconfigured("Cast.positionInfo")
        },
        transportStateOperation: @escaping @Sendable (CastDevice) async throws -> CastTransportState = { _ in
            throw ServiceError.unconfigured("Cast.transportState")
        },
        volumeOperation: @escaping @Sendable (CastDevice) async throws -> Int = { _ in
            throw ServiceError.unconfigured("Cast.volume")
        },
        setVolumeOperation: @escaping @Sendable (CastDevice, Int) async throws -> Void = { _, _ in
            throw ServiceError.unconfigured("Cast.setVolume")
        },
        stopServerOperation: @escaping @Sendable () async -> Void = {}
    ) {
        self.discoverDevicesOperation = discoverDevicesOperation
        self.inspectDeviceOperation = inspectDeviceOperation
        self.startCastingOperation = startCastingOperation
        self.playOperation = playOperation
        self.pauseOperation = pauseOperation
        self.stopOperation = stopOperation
        self.seekOperation = seekOperation
        self.positionInfoOperation = positionInfoOperation
        self.transportStateOperation = transportStateOperation
        self.volumeOperation = volumeOperation
        self.setVolumeOperation = setVolumeOperation
        self.stopServerOperation = stopServerOperation
    }
}
