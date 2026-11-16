import Foundation
import ImageIO
import NeoBiliDomain

public actor OfflineCacheRepository {
    private struct Manifest: Codable {
        var completed: [String: OfflineCacheEntry] = [:]
        var pending: [String: OfflineCacheEntry] = [:]
        var retired: [UUID] = []
    }
    private let directory: URL
    private let transport: any OfflineCacheTransport
    private let prepare: @Sendable (OfflineCacheEntry) async throws -> OfflinePreparedResources
    private let accountID: @Sendable () async -> String?
    private let capacity: @Sendable () -> Int64
    private let backgroundFinished: @Sendable (String) async -> Void
    private var manifest = Manifest()
    private var loaded = false
    private var started = false
    private var starting = false
    private var startupEvents: [OfflineTransferEvent] = []
    private var available = false
    private var cellular = false
    private var active: Set<String> = []
    private var preparations: [String: Task<Void, Never>] = [:]
    private var preparationIDs: [String: UUID] = [:]
    private var operationIDs: [String: UUID] = [:]
    private var observation: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<OfflineCacheSnapshot>.Continuation] = [:]
    private var leases: [UUID: UUID] = [:]
    private var samples: [String: (bytes: Int64, date: Date, speed: Double)] = [:]
    private var lastPublish = Date.distantPast
    private var storageError: String?

    init(directory: URL, transport: any OfflineCacheTransport,
         prepare: @escaping @Sendable (OfflineCacheEntry) async throws -> OfflinePreparedResources,
         accountID: @escaping @Sendable () async -> String?,
         capacity: @escaping @Sendable () -> Int64 = { Int64.max },
         backgroundFinished: @escaping @Sendable (String) async -> Void = { _ in }) {
        self.directory = directory; self.transport = transport; self.prepare = prepare
        self.accountID = accountID; self.capacity = capacity; self.backgroundFinished = backgroundFinished
    }

    public static func live(client: APIClient, identity: DeviceIdentity,
                            backgroundFinished: @escaping @Sendable (String) async -> Void) -> OfflineCacheRepository {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineVideos", isDirectory: true)
        return OfflineCacheRepository(directory: directory,
            transport: BackgroundCacheTransport(directory: directory, enabled: !AppNetwork.isRegression),
            prepare: { try await OfflineCachePreparation.prepare($0, client: client, identity: identity) },
            accountID: { await identity.appAccount().mid.map(String.init) },
            capacity: {
                (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage ?? Int64.max
            }, backgroundFinished: backgroundFinished)
    }

    public nonisolated var service: OfflineCacheService {
        OfflineCacheService(updates: { await self.updates() },
            enqueue: { try await self.enqueue($0, quality: $1, audioQuality: $2, replace: $3) },
            pause: { _ = try await self.pause($0) }, resume: { try await self.resume($0, allowsCellular: $1) },
            cancel: { try await self.cancel($0) }, delete: { try await self.delete($0) },
            playback: { try await self.playback($0) }, releasePlayback: { await self.release($0) })
    }

    public func start() async {
        guard !started else { return }
        started = true; starting = true
        defer { starting = false; publish(); schedule() }
        do {
            try load()
            observation = Task { [weak self, transport] in
                for await event in transport.events {
                    guard !Task.isCancelled else { break }
                    await self?.receive(event)
                }
            }
            let existing = await transport.existingTokens()
            let account = await accountID()
            var allowed = Set<String>()
            for id in Array(manifest.pending.keys) {
                guard var entry = manifest.pending[id] else { continue }
                if entry.accountID != account { entry.state = .accountPaused }
                if entry.state == .preparing { entry.state = .queued }
                manifest.pending[id] = entry
                if entry.state.canSchedule {
                    for resource in entry.resources where !resource.isComplete {
                        allowed.insert(token(entry, resource))
                    }
                }
            }
            // A finished background task can deliver its file before allTasks returns.
            active = allowed
            for token in existing.subtracting(allowed) { await transport.cancel(token: token) }
            for generation in manifest.retired { try removeFiles(generation) }
            manifest.retired = []
            try persist()
            while !startupEvents.isEmpty {
                let events = startupEvents; startupEvents = []
                for event in events { await process(event) }
            }
            active.formIntersection(existing)
        } catch { storageError = error.localizedDescription }
    }

    private func load() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var root = directory; try root.setResourceValues(values)
        let file = directory.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: file.path) {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
        }
        loaded = true
    }

    private func persist() throws {
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        let removable = manifest.retired.filter { !leases.values.contains($0) }
        if !removable.isEmpty {
            // The new manifest is durable before an older version can be removed.
            for generation in removable {
                if (try? removeFiles(generation)) != nil { manifest.retired.removeAll { $0 == generation } }
            }
            try? JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        }
        storageError = nil
    }

    private func folder(_ generation: UUID) -> URL { directory.appendingPathComponent(generation.uuidString, isDirectory: true) }
    private func token(_ entry: OfflineCacheEntry, _ resource: OfflineResource) -> String {
        entry.generation.uuidString + "/" + resource.transferID.uuidString + "/" + resource.id
    }
    private func resourceLocation(_ token: String) -> (String, Int)? {
        for (id, entry) in manifest.pending {
            if let index = entry.resources.firstIndex(where: { self.token(entry, $0) == token }) { return (id, index) }
        }
        return nil
    }

    func snapshot() -> OfflineCacheSnapshot {
        var value = OfflineCacheSnapshot()
        value.completed = manifest.completed.values.sorted { $0.createdAt > $1.createdAt }
        value.tasks = manifest.pending.values.sorted { $0.createdAt < $1.createdAt }
        value.availableBytes = capacity(); value.error = storageError
        for entry in value.completed + value.tasks {
            if let cover = entry.resources.first(where: { $0.kind == .cover && $0.isComplete }) {
                value.coverURLs[entry.generation] = folder(entry.generation).appendingPathComponent(cover.filename)
            }
        }
        for entry in value.tasks where entry.state == .downloading {
            value.speeds[entry.id] = entry.resources.reduce(0) { $0 + (samples[token(entry, $1)]?.speed ?? 0) }
        }
        return value
    }

    private func publish() {
        let value = snapshot()
        for observer in observers.values { observer.yield(value) }
        lastPublish = Date()
    }

    private func updates() async -> AsyncStream<OfflineCacheSnapshot> {
        await start()
        let id = UUID()
        let stream = AsyncStream<OfflineCacheSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = stream.continuation
        stream.continuation.yield(snapshot())
        stream.continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream.stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }

    func enqueue(_ videos: [OfflineVideo], quality: Int, audioQuality: Int, replace: Bool) async throws {
        await start(); try load()
        let account = await accountID()
        for video in videos {
            guard video.cid > 0, !video.bvid.isEmpty else { throw OfflineCacheError.invalidResource }
            if let existing = manifest.completed[video.id], existing.quality == quality { continue }
            if manifest.completed[video.id] != nil, !replace { continue }
            if let existing = manifest.pending[video.id] {
                if existing.quality == quality { continue }
                guard replace else { continue }
                try await cancel(video.id)
            }
            var entry = OfflineCacheEntry(video: video, quality: quality, accountID: account)
            entry.audioQuality = audioQuality
            manifest.pending[video.id] = entry
        }
        try persist(); publish(); schedule()
    }

    @discardableResult func pause(_ id: String, state: OfflineCacheState = .paused) async throws -> UUID? {
        guard var entry = manifest.pending[id] else { return nil }
        let operation = UUID(); operationIDs[id] = operation
        let oldResources = entry.resources
        for index in entry.resources.indices where !entry.resources[index].isComplete {
            entry.resources[index].transferID = UUID()
        }
        entry.state = state; manifest.pending[id] = entry
        preparations.removeValue(forKey: id)?.cancel()
        preparationIDs[id] = nil
        try persist(); publish()
        for resource in oldResources where !resource.isComplete {
            let key = token(entry, resource)
            active.remove(key); samples[key] = nil
            let data = await transport.pause(token: key)
            guard operationIDs[id] == operation, manifest.pending[id]?.generation == entry.generation,
                  let index = manifest.pending[id]?.resources.firstIndex(where: { $0.id == resource.id }) else { continue }
            if let data { manifest.pending[id]?.resources[index].resumeData = data }
        }
        try persist(); publish(); schedule()
        return operation
    }

    func resume(_ id: String, allowsCellular: Bool) async throws {
        guard let entry = manifest.pending[id] else { return }
        let operation = try await pause(id)
        let account = await accountID()
        guard operationIDs[id] == operation, manifest.pending[id]?.generation == entry.generation else { return }
        manifest.pending[id]?.accountID = account
        manifest.pending[id]?.allowsCellular = allowsCellular || entry.allowsCellular
        manifest.pending[id]?.state = .queued
        manifest.pending[id]?.message = nil
        // Re-resolve expired URLs; completed resources are retained by identity.
        if entry.state == .failed || entry.state == .accountPaused { refreshRequired.insert(id) }
        try persist(); publish(); schedule()
    }

    private var refreshRequired = Set<String>()

    func cancel(_ id: String) async throws {
        guard let entry = manifest.pending.removeValue(forKey: id) else { return }
        preparations.removeValue(forKey: id)?.cancel(); refreshRequired.remove(id)
        preparationIDs[id] = nil; operationIDs[id] = nil
        try persist()
        for resource in entry.resources {
            let key = token(entry, resource); active.remove(key); samples[key] = nil
            await transport.cancel(token: key)
        }
        try removeFiles(entry.generation)
        publish(); schedule()
    }

    func delete(_ ids: [String]) async throws {
        for id in ids {
            try await cancel(id)
            if let entry = manifest.completed.removeValue(forKey: id) { try retire(entry.generation) }
        }
        try persist(); publish()
    }

    public func accountDidChange() async {
        await start()
        let account = await accountID()
        for entry in Array(manifest.pending.values) where entry.accountID != account {
            do { try await pause(entry.id, state: .accountPaused) }
            catch { storageError = error.localizedDescription; publish() }
        }
    }

    private func schedule() {
        guard loaded, !starting, storageError == nil else { return }
        for entry in manifest.pending.values.sorted(by: { $0.createdAt < $1.createdAt }) where entry.state.canSchedule {
            guard available, !cellular || entry.allowsCellular else {
                manifest.pending[entry.id]?.state = .waitingForNetwork
                continue
            }
            guard preparations[entry.id] == nil else { continue }
            if entry.resources.isEmpty || refreshRequired.contains(entry.id) {
                guard preparations.count < 3 else { continue }
                manifest.pending[entry.id]?.state = .preparing
                let preparationID = UUID(); preparationIDs[entry.id] = preparationID
                preparations[entry.id] = Task { [weak self, prepare] in
                    do { let result = try await prepare(entry); try Task.checkCancellation(); await self?.prepared(entry, result, requestID: preparationID) }
                    catch { await self?.preparationFailed(entry, error, requestID: preparationID) }
                }
            } else {
                if entry.resources.allSatisfy(\.isComplete) {
                    do { try completeIfReady(entry.id) }
                    catch { storageError = error.localizedDescription }
                    continue
                }
                manifest.pending[entry.id]?.state = .downloading
                for resource in entry.resources where !resource.isComplete {
                    let key = token(entry, resource)
                    guard !active.contains(key) else { continue }
                    active.insert(key)
                    Task { [weak self, transport] in
                        await self?.beginTransfer(entry, resource, transport: transport)
                    }
                }
            }
        }
        publish()
    }

    private func beginTransfer(_ entry: OfflineCacheEntry, _ resource: OfflineResource, transport: any OfflineCacheTransport) async {
        let key = token(entry, resource)
        guard active.contains(key), manifest.pending[entry.id]?.state.canSchedule == true else { active.remove(key); return }
        do {
            guard capacity() > max(1_048_576, resource.expectedBytes - resource.receivedBytes) else { throw OfflineCacheError.storageFull }
            try await transport.start(token: key, url: resource.url, cellular: entry.allowsCellular, resumeData: resource.resumeData)
            if !active.contains(key) { await transport.cancel(token: key) }
        } catch {
            await receive(.failed(key, error.localizedDescription, nil, error is OfflineCacheError))
        }
    }

    private func prepared(_ original: OfflineCacheEntry, _ result: OfflinePreparedResources, requestID: UUID) async {
        guard var entry = manifest.pending[original.id], entry.generation == original.generation,
              preparationIDs[entry.id] == requestID, !Task.isCancelled, entry.state.canSchedule else { return }
        preparations[entry.id] = nil; refreshRequired.remove(entry.id)
        do {
            let account = await accountID()
            guard entry.accountID == account else { try await pause(entry.id, state: .accountPaused); return }
            let previous = Dictionary(uniqueKeysWithValues: entry.resources.map { ($0.id, $0) })
            entry.resources = result.resources.map { resource in
                guard let old = previous[resource.id], old.isComplete else {
                    var next = resource
                    if let old = previous[resource.id], old.url == resource.url {
                        next.resumeData = old.resumeData; next.receivedBytes = old.receivedBytes
                    }
                    return next
                }
                return old
            }
            entry.audioQuality = result.audioQuality; entry.width = result.width; entry.height = result.height
            entry.state = .queued
            try FileManager.default.createDirectory(at: folder(entry.generation), withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            guard manifest.pending[entry.id]?.generation == entry.generation,
                  preparationIDs[entry.id] == requestID,
                  manifest.pending[entry.id]?.state.canSchedule == true else { return }
            manifest.pending[entry.id] = entry
            try completeIfReady(entry.id)
        } catch { await preparationFailed(original, error, requestID: requestID) }
        if preparationIDs[entry.id] == requestID { preparationIDs[entry.id] = nil }
        publish(); schedule()
    }

    private func preparationFailed(_ entry: OfflineCacheEntry, _ error: Error, requestID: UUID) async {
        guard manifest.pending[entry.id]?.generation == entry.generation, preparationIDs[entry.id] == requestID else { return }
        preparationIDs[entry.id] = nil
        preparations[entry.id] = nil
        guard manifest.pending[entry.id]?.state.canSchedule == true else { return }
        manifest.pending[entry.id]?.state = available ? .failed : .waitingForNetwork
        manifest.pending[entry.id]?.message = error.localizedDescription
        do { try persist() } catch { storageError = error.localizedDescription }
        publish(); schedule()
    }

    private func receive(_ event: OfflineTransferEvent) async {
        if starting { startupEvents.append(event); return }
        await process(event)
    }

    private func process(_ event: OfflineTransferEvent) async {
        switch event {
        case .network(let available, let cellular):
            self.available = available; self.cellular = cellular
            schedule()
        case .progress(let key, let received, let expected):
            guard active.contains(key), let (id, index) = resourceLocation(key) else { return }
            manifest.pending[id]?.resources[index].receivedBytes = received
            if expected > 0 { manifest.pending[id]?.resources[index].expectedBytes = expected }
            let now = Date(), previous = samples[key]
            let elapsed = now.timeIntervalSince(previous?.date ?? now)
            if previous == nil || elapsed >= 0.5 {
                samples[key] = (received, now, elapsed > 0 ? max(0, Double(received - (previous?.bytes ?? received)) / elapsed) : 0)
            }
            if now.timeIntervalSince(lastPublish) >= 0.25 { publish() }
        case .downloaded(let key, let file, let status, let expected):
            defer { try? FileManager.default.removeItem(at: file) }
            active.remove(key)
            guard let (id, index) = resourceLocation(key), let entry = manifest.pending[id],
                  entry.state != .paused, entry.state != .accountPaused,
                  !entry.resources[index].isComplete else { return }
            samples[key] = nil
            do {
                guard (200...299).contains(status) else { throw URLError(.badServerResponse) }
                let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                guard size > 0, expected < 0 || size == expected else { throw OfflineCacheError.invalidResource }
                try Self.validate(file, kind: entry.resources[index].kind)
                let destination = folder(entry.generation).appendingPathComponent(entry.resources[index].filename)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: file, to: destination)
                manifest.pending[id]?.resources[index].isComplete = true
                manifest.pending[id]?.resources[index].receivedBytes = size
                manifest.pending[id]?.resources[index].expectedBytes = size
                manifest.pending[id]?.resources[index].resumeData = nil
                try completeIfReady(id)
            } catch { await fail(key, id: id, message: error.localizedDescription, resumeData: nil) }
            publish(); schedule()
        case .failed(let key, let message, let resume, let diskFull):
            guard active.remove(key) != nil, let (id, index) = resourceLocation(key) else { return }
            if !diskFull, available, manifest.pending[id]?.resources[index].resumeData != nil {
                manifest.pending[id]?.resources[index].resumeData = nil
                manifest.pending[id]?.resources[index].receivedBytes = 0
                manifest.pending[id]?.resources[index].transferID = UUID()
                do { try persist() } catch { storageError = error.localizedDescription }
                schedule()
                return
            }
            await fail(key, id: id, message: diskFull ? OfflineCacheError.storageFull.localizedDescription : message, resumeData: resume)
        case .finishedEvents(let identifier):
            do { try persist() } catch { storageError = error.localizedDescription; publish() }
            await backgroundFinished(identifier)
        }
    }

    private func fail(_ key: String, id: String, message: String, resumeData: Data?) async {
        guard let (_, index) = resourceLocation(key) else { return }
        manifest.pending[id]?.resources[index].resumeData = resumeData
        let waitsForNetwork = !available || (cellular && manifest.pending[id]?.allowsCellular == false)
        manifest.pending[id]?.state = waitsForNetwork ? .waitingForNetwork : .failed
        manifest.pending[id]?.message = message
        // Other resources may finish, but this item remains outside the completed library.
        samples[key] = nil
        do { try persist() } catch { storageError = error.localizedDescription }
        publish(); schedule()
    }

    private func completeIfReady(_ id: String) throws {
        guard var entry = manifest.pending[id], !entry.resources.isEmpty,
              entry.resources.allSatisfy(\.isComplete) else { try persist(); return }
        let previous = manifest
        entry.state = .completed; entry.message = nil
        if let old = manifest.completed[id] { try retire(old.generation) }
        manifest.completed[id] = entry
        manifest.pending[id] = nil
        do { try persist() }
        catch { manifest = previous; throw error }
    }

    private func retire(_ generation: UUID) throws {
        if !manifest.retired.contains(generation) { manifest.retired.append(generation) }
    }
    private func removeFiles(_ generation: UUID) throws {
        let path = folder(generation)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    func playback(_ id: String) async throws -> OfflinePlaybackDescriptor {
        await start(); try load()
        guard let entry = manifest.completed[id] else { throw OfflineCacheError.missingFile }
        let root = folder(entry.generation)
        for resource in entry.resources {
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(resource.filename).path) else {
                throw OfflineCacheError.missingFile
            }
        }
        let videos = entry.resources.filter { $0.kind == .video }.map { root.appendingPathComponent($0.filename) }
        guard !videos.isEmpty else { throw OfflineCacheError.missingFile }
        let audio = entry.resources.first { $0.kind == .audio }.map { root.appendingPathComponent($0.filename) }
        let cover = entry.resources.first { $0.kind == .cover }.map { root.appendingPathComponent($0.filename) }
        let danmaku = try entry.resources.first { $0.kind == .danmaku }.map {
            try DanmakuLoader.parseValidated(Data(contentsOf: root.appendingPathComponent($0.filename)))
        } ?? []
        let subtitles = try entry.resources.filter { $0.kind == .subtitle }.map {
            OfflineSubtitleTrack(id: $0.id, language: $0.language ?? "", title: $0.title ?? "",
                cues: try OfflineSubtitleTrack.decode(Data(contentsOf: root.appendingPathComponent($0.filename))))
        }
        let lease = UUID(); leases[lease] = entry.generation
        return .init(leaseID: lease, entry: entry, videoURLs: videos, audioURL: audio, coverURL: cover,
                     danmaku: danmaku, subtitles: subtitles)
    }

    private func release(_ id: UUID) {
        guard let generation = leases.removeValue(forKey: id), !leases.values.contains(generation),
              manifest.retired.contains(generation) else { return }
        do { try removeFiles(generation); manifest.retired.removeAll { $0 == generation }; try persist() }
        catch { storageError = error.localizedDescription }
        publish()
    }

    private static func validate(_ file: URL, kind: OfflineResource.Kind) throws {
        switch kind {
        case .danmaku: _ = try DanmakuLoader.parseValidated(Data(contentsOf: file))
        case .subtitle: _ = try OfflineSubtitleTrack.decode(Data(contentsOf: file))
        case .cover:
            guard let image = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(image) > 0 else {
                throw OfflineCacheError.invalidResource
            }
        case .video, .audio:
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 32) ?? Data()
            guard ["ftyp", "moov", "moof", "styp", "FLV"].contains(where: { header.range(of: Data($0.utf8)) != nil }) else {
                throw OfflineCacheError.invalidResource
            }
        }
    }
}
