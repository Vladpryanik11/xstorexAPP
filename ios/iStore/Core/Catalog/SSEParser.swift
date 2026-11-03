import Foundation

/// Событие Server-Sent Events.
struct SSEEvent: Equatable, Sendable {
    var event: String
    var id: String?
    var data: String
}

/// Разбор потока SSE по строкам (WHATWG, «Interpreting an event stream»).
/// Пустая строка завершает событие, строки с `:` — комментарии (`: ping`).
struct SSEParser {
    private var eventName = ""
    private var dataLines: [String] = []
    private var pendingId: String?
    private var hasFields = false

    /// Последний `id:` — его клиент отправляет в `Last-Event-ID` при переподключении.
    private(set) var lastEventId: String?
    /// Значение `retry:` в миллисекундах, если сервер его прислал.
    private(set) var retryMilliseconds: Int?

    init(lastEventId: String? = nil) {
        self.lastEventId = lastEventId
    }

    /// Принимает одну строку без перевода строки. Возвращает событие, если строка его завершила.
    mutating func consume(line rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") {
                value.removeFirst()
            }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event":
            eventName = value
            hasFields = true
        case "data":
            dataLines.append(value)
            hasFields = true
        case "id":
            if !value.contains("\u{0}") {
                pendingId = value
                lastEventId = value
            }
            hasFields = true
        case "retry":
            if let milliseconds = Int(value) {
                retryMilliseconds = milliseconds
            }
        default:
            break
        }
        return nil
    }

    /// Завершает поток: отдаёт недописанное событие, если в нём были данные.
    mutating func finish() -> SSEEvent? {
        dataLines.isEmpty ? nil : dispatch()
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventName = ""
            dataLines = []
            pendingId = nil
            hasFields = false
        }
        guard hasFields, !(dataLines.isEmpty && eventName.isEmpty) else {
            return nil
        }
        return SSEEvent(
            event: eventName.isEmpty ? "message" : eventName,
            id: pendingId ?? lastEventId,
            data: dataLines.joined(separator: "\n")
        )
    }
}

/// Делит поток байтов на строки по `\n`, `\r\n` и `\r`, сохраняя пустые строки.
/// `URLSession.AsyncBytes.lines` пустые строки пропускает, а в SSE они разделяют события.
struct SSELineSplitter {
    private var buffer: [UInt8] = []
    private var lastWasCR = false

    /// Возвращает строку, если байт её завершил.
    mutating func append(_ byte: UInt8) -> String? {
        switch byte {
        case 0x0A: // \n
            if lastWasCR {
                lastWasCR = false
                return nil
            }
            return flush()
        case 0x0D: // \r
            lastWasCR = true
            return flush()
        default:
            lastWasCR = false
            buffer.append(byte)
            return nil
        }
    }

    /// Остаток без завершающего перевода строки.
    mutating func finish() -> String? {
        buffer.isEmpty ? nil : flush()
    }

    private mutating func flush() -> String {
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}
