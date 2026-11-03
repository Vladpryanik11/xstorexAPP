import Foundation
import UIKit

/// Открытие `itms-services://`. В тестах подменяется.
@MainActor
protocol URLOpening: AnyObject {
    func open(_ url: URL) async -> Bool
}

@MainActor
final class SystemURLOpener: URLOpening {
    func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url, options: [:])
    }
}

/// Версия iOS и свободное место для проверок до старта.
protocol DeviceCapacityProviding: Sendable {
    var osVersion: String { get }
    func freeDiskBytes() -> Int64?
}

struct SystemDeviceCapacity: DeviceCapacityProviding {
    let osVersion: String

    func freeDiskBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Установка из каталога по OTA: грант → опрос до `ready` → `itms-services://` → события стадий.
@MainActor
final class InstallService {
    struct Activity: Equatable {
        let app: AppSummary
        var state: InstallState
        let startedAt: Date
    }

    enum StartResult: Equatable {
        case started
        case alreadyRunning
        case blocked(InstallPreflight)
    }

    typealias Handler = (_ appId: String, _ state: InstallState) -> Void

    private struct ObserverBox {
        weak var owner: AnyObject?
        let handler: Handler
    }

    private let api: APIClientProtocol
    private let opener: URLOpening
    private let device: DeviceCapacityProviding
    private let telemetry: TelemetryRecording?
    private let pollInterval: TimeInterval
    private let maxPollAttempts: Int
    private let installingResetDelay: TimeInterval

    private var activities: [String: Activity] = [:]
    private var order: [String] = []
    private var observers: [ObserverBox] = []
    private var tasks: [String: Task<Void, Never>] = [:]

    init(
        api: APIClientProtocol,
        opener: URLOpening,
        device: DeviceCapacityProviding,
        telemetry: TelemetryRecording?,
        pollInterval: TimeInterval = 1.5,
        maxPollAttempts: Int = 40,
        installingResetDelay: TimeInterval = 45
    ) {
        self.api = api
        self.opener = opener
        self.device = device
        self.telemetry = telemetry
        self.pollInterval = pollInterval
        self.maxPollAttempts = maxPollAttempts
        self.installingResetDelay = installingResetDelay
    }

    // MARK: - Состояние

    func state(for appId: String) -> InstallState {
        activities[appId]?.state ?? .idle
    }

    /// Установки в порядке запуска (для Менеджера и баннера).
    var activeInstalls: [Activity] {
        order.compactMap { activities[$0] }
    }

    /// Подписка на изменения. Один обработчик на владельца; владелец хранится слабо.
    func addObserver(_ owner: AnyObject, handler: @escaping Handler) {
        observers.removeAll { $0.owner == nil || $0.owner === owner }
        observers.append(ObserverBox(owner: owner, handler: handler))
    }

    func removeObserver(_ owner: AnyObject) {
        observers.removeAll { $0.owner == nil || $0.owner === owner }
    }

    // MARK: - Проверки до старта

    func preflight(for app: AppSummary) -> InstallPreflight {
        guard app.isAvailable else {
            return .unavailable
        }
        if !OSVersion.isSatisfied(current: device.osVersion, required: app.minOs) {
            return .incompatible(requiredOS: app.minOs)
        }
        if app.sizeBytes > 0, let free = device.freeDiskBytes() {
            // IPA и распакованное приложение какое-то время лежат на диске одновременно.
            let required = app.sizeBytes * 2
            if free < required {
                return .lowSpace(requiredBytes: required, freeBytes: free)
            }
        }
        return .ok
    }

    // MARK: - Управление

    @discardableResult
    func start(_ app: AppSummary, allowLowSpace: Bool = false) -> StartResult {
        if state(for: app.id).isActive {
            return .alreadyRunning
        }
        let check = preflight(for: app)
        switch check {
        case .ok:
            break
        case .lowSpace where allowLowSpace:
            break
        default:
            return .blocked(check)
        }
        tasks[app.id]?.cancel()
        update(app, .preparing)
        tasks[app.id] = Task { [weak self] in
            await self?.run(app)
        }
        return .started
    }

    func cancel(appId: String) {
        tasks[appId]?.cancel()
        tasks[appId] = nil
        finish(appId)
    }

    /// Убрать завершённую или упавшую установку из списка.
    func dismiss(appId: String) {
        guard !state(for: appId).isActive else { return }
        finish(appId)
    }

    // MARK: - Машина состояний

    private func run(_ app: AppSummary) async {
        var installId: String?
        var restarts = 0
        while true {
            do {
                try await attempt(app, installId: &installId)
                return
            } catch APIError.grantExpired where restarts < 1 {
                // Грант истёк, пока шла установка: просим новый один раз.
                restarts += 1
                installId = nil
                update(app, .preparing)
            } catch is CancellationError {
                // `cancel(appId:)` уже вернул состояние в `idle`.
                return
            } catch let error as APIError {
                if error != .cancelled {
                    fail(app, installId: installId, code: Self.code(for: error))
                }
                return
            } catch {
                fail(app, installId: installId, code: InstallErrorCode.generic)
                return
            }
        }
    }

    /// Одна попытка: грант → опрос до `ready` → передача в iOS.
    private func attempt(_ app: AppSummary, installId: inout String?) async throws {
        let create = Endpoint<InstallGrant>.json(
            path: "/catalog/installs",
            body: InstallRequestBody(appId: app.id, version: nil)
        )
        try Task.checkCancellation()
        var grant = try await api.send(create)
        try Task.checkCancellation()
        installId = grant.installId
        report(installId: grant.installId, stage: .preparing, errorCode: nil, app: app)

        var attempts = 0
        while grant.status == .preparing || grant.status == .unknown {
            attempts += 1
            if attempts > maxPollAttempts {
                fail(app, installId: grant.installId, code: InstallErrorCode.timedOut)
                return
            }
            try await Task.sleep(nanoseconds: Self.nanoseconds(pollInterval))
            do {
                grant = try await api.send(Endpoint<InstallGrant>(path: "/catalog/installs/\(grant.installId)"))
            } catch APIError.conflict(let code) where code == "not_ready" {
                continue
            }
            try Task.checkCancellation()
        }

        if grant.status == .failed {
            // Истёкший грант опрос возвращает со статусом `failed`, а не ошибкой 401: `run` попросит новый.
            if grant.errorCode == APIError.grantExpired.code {
                throw APIError.grantExpired
            }
            fail(app, installId: grant.installId, code: grant.errorCode ?? "server_job_failed")
            return
        }

        update(app, .ready)
        report(installId: grant.installId, stage: .ready, errorCode: nil, app: app)

        guard let itmsURL = grant.itmsUrl else {
            fail(app, installId: grant.installId, code: InstallErrorCode.installURLMissing)
            return
        }

        update(app, .handingOff)
        report(installId: grant.installId, stage: .handingOff, errorCode: nil, app: app)
        try Task.checkCancellation()
        let opened = await opener.open(itmsURL)
        // Пока iOS открывала ссылку, установку могли отменить: тогда она не должна вернуться в список.
        try Task.checkCancellation()
        guard opened else {
            fail(app, installId: grant.installId, code: InstallErrorCode.launchFailed)
            return
        }

        update(app, .installing)
        report(installId: grant.installId, stage: .installing, errorCode: nil, app: app)

        // iOS не сообщает об окончании установки, поэтому через время кнопка возвращается в исходный вид.
        try await Task.sleep(nanoseconds: Self.nanoseconds(installingResetDelay))
        tasks[app.id] = nil
        finish(app.id)
    }

    static func code(for error: APIError) -> String {
        switch error {
        case .notFound:
            return InstallErrorCode.appNotAvailable
        case .conflict(let code):
            return code == "no_build" ? InstallErrorCode.noBuild : code
        case .accountInactive:
            return InstallErrorCode.accountInactive
        case .grantExpired:
            return "install_token_expired"
        case .offline:
            return InstallErrorCode.offline
        case .timedOut:
            return InstallErrorCode.timedOut
        default:
            return error.code
        }
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    private func update(_ app: AppSummary, _ state: InstallState) {
        if var activity = activities[app.id] {
            activity.state = state
            activities[app.id] = activity
        } else {
            activities[app.id] = Activity(app: app, state: state, startedAt: Date())
            order.append(app.id)
        }
        notify(app.id, state)
    }

    private func fail(_ app: AppSummary, installId: String?, code: String) {
        tasks[app.id] = nil
        update(app, .failed(code: code))
        if let installId = installId {
            report(installId: installId, stage: .failed, errorCode: code, app: app)
        } else {
            recordTelemetry(stage: .failed, errorCode: code, app: app)
        }
    }

    private func finish(_ appId: String) {
        guard activities[appId] != nil else { return }
        activities[appId] = nil
        order.removeAll { $0 == appId }
        notify(appId, .idle)
    }

    private func notify(_ appId: String, _ state: InstallState) {
        observers.removeAll { $0.owner == nil }
        let current = observers
        for box in current {
            box.handler(appId, state)
        }
    }

    private func report(installId: String, stage: InstallStage, errorCode: String?, app: AppSummary) {
        let endpoint = Endpoint<EmptyResponse>.json(
            path: "/catalog/installs/\(installId)/events",
            body: InstallEventBody(stage: stage.rawValue, errorCode: errorCode)
        )
        let api = self.api
        Task {
            _ = try? await api.send(endpoint)
        }
        recordTelemetry(stage: stage, errorCode: errorCode, app: app)
    }

    private func recordTelemetry(stage: InstallStage, errorCode: String?, app: AppSummary) {
        guard let telemetry = telemetry else { return }
        var props = ["stage": stage.rawValue, "app_id": app.id, "version": app.version]
        if let errorCode = errorCode {
            props["error_code"] = errorCode
        }
        Task {
            await telemetry.record(kind: "install.step", props: props)
        }
    }
}
