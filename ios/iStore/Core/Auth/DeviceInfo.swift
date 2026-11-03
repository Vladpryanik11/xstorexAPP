import Foundation

/// Снимок данных устройства для активации и проверки совместимости.
struct DeviceInfo: Sendable, Equatable {
    let installId: String
    /// Идентификатор модели, например `iPhone16,2`.
    let model: String
    /// Версия iOS, например `18.1`.
    let osVersion: String
    /// Локаль, например `ru_RU`.
    let locale: String

    static func current(installId: String) -> DeviceInfo {
        DeviceInfo(
            installId: installId,
            model: modelIdentifier(),
            osVersion: currentOSVersion(),
            locale: Locale.current.identifier
        )
    }

    static func currentOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion > 0 {
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}

/// Сравнение версий вида `15.0`, `17.4.1`.
enum OSVersion {
    /// `true`, если `current` не ниже `required`.
    static func isSatisfied(current: String, required: String) -> Bool {
        compare(current, required) != .orderedAscending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}
