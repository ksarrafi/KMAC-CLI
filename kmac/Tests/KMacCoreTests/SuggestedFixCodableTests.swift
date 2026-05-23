import XCTest
@testable import KMacCore

/// Tests for SuggestedFix Codable conformance (JSON encode/decode round-trips).
final class SuggestedFixCodableTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip(_ fix: SuggestedFix) throws -> SuggestedFix {
        let data = try JSONEncoder().encode(fix)
        return try JSONDecoder().decode(SuggestedFix.self, from: data)
    }

    private func makeFix(
        title: String = "My Fix",
        description: String = "Does something useful",
        command: String = "echo done",
        severity: String = "medium"
    ) -> SuggestedFix {
        SuggestedFix(title: title, description: description, command: command, severity: severity)
    }

    // MARK: - Round-trip tests

    func testRoundTrip_typicalFix_allFieldsPreserved() throws {
        let original = makeFix(title: "Kill Hung Process",
                               description: "Force-quits a hung process",
                               command: "kill -9 1234",
                               severity: "critical")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.title,       original.title)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.command,     original.command)
        XCTAssertEqual(decoded.severity,    original.severity)
    }

    func testRoundTrip_emptyStrings_preserved() throws {
        let original = makeFix(title: "", description: "", command: "", severity: "")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.title,       "")
        XCTAssertEqual(decoded.description, "")
        XCTAssertEqual(decoded.command,     "")
        XCTAssertEqual(decoded.severity,    "")
    }

    func testRoundTrip_multilineCommand_preserved() throws {
        let cmd = "df -h /\nsort -k5 -rn\nhead -5"
        let original = makeFix(command: cmd)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.command, cmd)
    }

    func testRoundTrip_unicodeContent_preserved() throws {
        let original = makeFix(title: "修复 – Fix Ñoño",
                               description: "Ré-indexer les données ™",
                               command: "echo '日本語'",
                               severity: "low")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.title,       original.title)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.command,     original.command)
        XCTAssertEqual(decoded.severity,    original.severity)
    }

    // MARK: - JSON key names

    func testEncoding_usesExpectedJSONKeys() throws {
        let fix = makeFix(title: "T", description: "D", command: "C", severity: "S")
        let data = try JSONEncoder().encode(fix)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(dict["title"],       "Missing JSON key 'title'")
        XCTAssertNotNil(dict["description"], "Missing JSON key 'description'")
        XCTAssertNotNil(dict["command"],     "Missing JSON key 'command'")
        XCTAssertNotNil(dict["severity"],    "Missing JSON key 'severity'")
        XCTAssertEqual(dict.keys.count, 4,   "Unexpected extra keys: \(dict.keys.sorted())")
    }

    func testDecoding_fromRawJSON_succeeds() throws {
        let json = """
        {
            "title": "Free Disk Space",
            "description": "Removes temporary files",
            "command": "rm -rf /tmp/*",
            "severity": "warning"
        }
        """.data(using: .utf8)!
        let fix = try JSONDecoder().decode(SuggestedFix.self, from: json)
        XCTAssertEqual(fix.title,       "Free Disk Space")
        XCTAssertEqual(fix.description, "Removes temporary files")
        XCTAssertEqual(fix.command,     "rm -rf /tmp/*")
        XCTAssertEqual(fix.severity,    "warning")
    }

    func testDecoding_missingField_throws() {
        // SuggestedFix has no optional fields — missing any key must throw
        let json = """
        {
            "title": "Incomplete Fix",
            "description": "No command or severity"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SuggestedFix.self, from: json),
                             "Decoding an incomplete JSON object should throw")
    }

    // MARK: - Array round-trip

    func testArrayRoundTrip_threeFixes_allPreserved() throws {
        let fixes = [
            makeFix(title: "A", severity: "low"),
            makeFix(title: "B", severity: "medium"),
            makeFix(title: "C", severity: "critical"),
        ]
        let data = try JSONEncoder().encode(fixes)
        let decoded = try JSONDecoder().decode([SuggestedFix].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        for (orig, dec) in zip(fixes, decoded) {
            XCTAssertEqual(dec.title,    orig.title)
            XCTAssertEqual(dec.severity, orig.severity)
        }
    }
}
