import XCTest
@testable import iStore

final class SSEParserTests: XCTestCase {
    private func parse(_ text: String, parser: inout SSEParser) -> [SSEEvent] {
        var splitter = SSELineSplitter()
        var events: [SSEEvent] = []
        for byte in Array(text.utf8) {
            if let line = splitter.append(byte), let event = parser.consume(line: line) {
                events.append(event)
            }
        }
        if let line = splitter.finish(), let event = parser.consume(line: line) {
            events.append(event)
        }
        if let event = parser.finish() {
            events.append(event)
        }
        return events
    }

    func testHelloChangeAndPing() {
        let stream = """
        event: hello
        id: 40
        data: {"revision": 45}

        : ping

        event: change
        id: 44
        data: {"revision": 44, "kind": "app_removed", "app_id": "app_b", "app": null}


        """
        var parser = SSEParser()
        let events = parse(stream, parser: &parser)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], SSEEvent(event: "hello", id: "40", data: #"{"revision": 45}"#))
        XCTAssertEqual(events[1].event, "change")
        XCTAssertEqual(events[1].id, "44")
        XCTAssertEqual(parser.lastEventId, "44")

        let change = try? JSONCoding.makeDecoder().decode(CatalogChange.self, from: events[1].data.data)
        XCTAssertEqual(change?.kind, .appRemoved)
        XCTAssertEqual(change?.appId, "app_b")
    }

    func testMultilineDataAndDefaultEventName() {
        var parser = SSEParser()
        let events = parse("data: first\ndata: second\n\n", parser: &parser)
        XCTAssertEqual(events, [SSEEvent(event: "message", id: nil, data: "first\nsecond")])
    }

    func testCRLFLineEndings() {
        var parser = SSEParser()
        let events = parse("event: reset\r\nid: 50\r\ndata: {\"revision\": 50}\r\n\r\n", parser: &parser)
        XCTAssertEqual(events, [SSEEvent(event: "reset", id: "50", data: #"{"revision": 50}"#)])
    }

    func testFieldWithoutSpaceAndRetry() {
        var parser = SSEParser()
        let events = parse("retry: 3000\nevent:change\ndata:{}\n\n", parser: &parser)
        XCTAssertEqual(parser.retryMilliseconds, 3000)
        XCTAssertEqual(events, [SSEEvent(event: "change", id: nil, data: "{}")])
    }

    func testCommentsAndEmptyBlocksDoNotProduceEvents() {
        var parser = SSEParser()
        let events = parse(": ping\n\n\n: ping\n\n", parser: &parser)
        XCTAssertTrue(events.isEmpty)
    }

    func testIdPersistsAcrossEvents() {
        var parser = SSEParser(lastEventId: "10")
        let events = parse("event: change\ndata: {}\n\n", parser: &parser)
        XCTAssertEqual(events.first?.id, "10", "Без нового id событие несёт последний известный")
    }

    func testUnterminatedEventIsFlushedOnFinish() {
        var parser = SSEParser()
        let events = parse("event: change\ndata: {}", parser: &parser)
        XCTAssertEqual(events, [SSEEvent(event: "change", id: nil, data: "{}")])
    }

    func testLineSplitterKeepsEmptyLines() {
        var splitter = SSELineSplitter()
        var lines: [String] = []
        for byte in Array("a\n\nb\r\n\r\nc".utf8) {
            if let line = splitter.append(byte) {
                lines.append(line)
            }
        }
        if let rest = splitter.finish() {
            lines.append(rest)
        }
        XCTAssertEqual(lines, ["a", "", "b", "", "c"])
    }

    func testBackoffGrowsAndIsCapped() {
        XCTAssertLessThanOrEqual(CatalogLiveSync.backoffDelay(attempt: 1), 1.3)
        XCTAssertGreaterThanOrEqual(CatalogLiveSync.backoffDelay(attempt: 4), 8)
        XCTAssertLessThanOrEqual(CatalogLiveSync.backoffDelay(attempt: 20), 78)
    }
}
