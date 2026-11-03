import Foundation

/// Форматирование размеров, дат и чисел для UI.
enum Formatters {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Компактное число: 1280 → «1,3 тыс.» / «1.3K».
    static func compactNumber(_ value: Int) -> String {
        if value < 1000 {
            return String(value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if value < 1_000_000 {
            let short = formatter.string(from: NSNumber(value: Double(value) / 1000)) ?? String(value / 1000)
            return L10n.tr("format.thousands", short)
        }
        let short = formatter.string(from: NSNumber(value: Double(value) / 1_000_000)) ?? String(value / 1_000_000)
        return L10n.tr("format.millions", short)
    }

    static func rating(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Звёзды рейтинга: ★★★★☆.
    static func stars(_ value: Double) -> String {
        let full = Int(value.rounded())
        let clamped = max(0, min(5, full))
        return String(repeating: "★", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    /// «2 ч 15 мин» до даты; `nil`, если дата уже прошла.
    static func countdown(to date: Date, now: Date = Date()) -> String? {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = interval >= 3600 ? [.day, .hour, .minute] : [.minute, .second]
        return formatter.string(from: interval)
    }
}
