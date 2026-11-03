import Foundation

/// Правила кода активации: верхний регистр, без пробелов и дефисов (API.md, «Auth»).
/// На экране код показывается группами по 4: `XXXX-XXXX-XXXX`.
enum ActivationCode {
    static let length = 12
    static let groupSize = 4

    /// Нормализация для сравнения и отправки: только латинские буквы и цифры, верхний регистр.
    static func normalize(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let upper = raw.uppercased()
        return String(upper.filter { allowed.contains($0) })
    }

    /// Формат для показа и отправки: `XXXX-XXXX-XXXX`, лишние символы отбрасываются.
    static func format(_ raw: String) -> String {
        let normalized = String(normalize(raw).prefix(length))
        var groups: [String] = []
        var current = ""
        for character in normalized {
            current.append(character)
            if current.count == groupSize {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups.joined(separator: "-")
    }

    static func isComplete(_ raw: String) -> Bool {
        normalize(raw).count == length
    }
}
