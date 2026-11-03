import Foundation

protocol TelemetryRecording: Sendable {
    func record(kind: String, props: [String: String]) async
}

/// Батч-рекордер `/client/events`: копит события и отправляет пачками до 100 штук
/// раз в 30 секунд и при уходе приложения в фон.
actor TelemetryRecorder: TelemetryRecording {
    static let flushInterval: TimeInterval = 30
    static let batchLimit = 100
    static let bufferLimit = 500

    private let api: APIClientProtocol
    private let tokenStore: TokenStoring
    private var buffer: [TelemetryEvent] = []
    private var timerTask: Task<Void, Never>?
    private var isFlushing = false

    init(api: APIClientProtocol, tokenStore: TokenStoring) {
        self.api = api
        self.tokenStore = tokenStore
    }

    func record(kind: String, props: [String: String]) {
        let event = TelemetryEvent(kind: kind, ts: JSONCoding.formatISODate(Date()), props: props)
        buffer.append(event)
        if buffer.count > Self.bufferLimit {
            buffer.removeFirst(buffer.count - Self.bufferLimit)
        }
    }

    var pendingCount: Int { buffer.count }

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(TelemetryRecorder.flushInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.flush()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Отправляет накопленное. Без токена события ждут входа: `/client/events` защищён.
    func flush() async {
        guard !isFlushing, !buffer.isEmpty else { return }
        guard await tokenStore.token() != nil else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !buffer.isEmpty {
            let batch = Array(buffer.prefix(Self.batchLimit))
            let endpoint = Endpoint<EmptyResponse>.json(path: "/client/events", body: TelemetryBatch(events: batch))
            do {
                _ = try await api.send(endpoint)
                buffer.removeFirst(min(batch.count, buffer.count))
            } catch {
                return
            }
        }
    }
}
