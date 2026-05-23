import XCTest
@testable import KMacCore

/// Tests for FixStore.save(_:) and FixStore.load().
///
/// FixStore writes to ~/Library/Application Support/KMac/last-fixes.json.
/// setUp backs the file up; tearDown restores it so we never clobber real saved fixes.
final class FixStoreTests: XCTestCase {

    // MARK: - Backup / Restore

    private var storeURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KMac/last-fixes.json")
    }

    private var backupURL: URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("last-fixes.json.test-backup")
    }

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        // Back up the real file if it exists.
        if fm.fileExists(atPath: storeURL.path) {
            try? fm.copyItem(at: storeURL, to: backupURL)
            try? fm.removeItem(at: storeURL)
        }
    }

    override func tearDown() {
        super.tearDown()
        let fm = FileManager.default
        // Remove whatever the test wrote.
        try? fm.removeItem(at: storeURL)
        // Restore the original file if we had one.
        if fm.fileExists(atPath: backupURL.path) {
            try? fm.moveItem(at: backupURL, to: storeURL)
        }
    }

    // MARK: - Helpers

    private func makeFix(
        title: String = "Test Fix",
        description: String = "A test fix",
        command: String = "echo hello",
        severity: String = "medium"
    ) -> SuggestedFix {
        SuggestedFix(title: title, description: description, command: command, severity: severity)
    }

    // MARK: - Tests: load with no file

    func testLoad_noFile_returnsEmptyArray() {
        // setUp removed the file, so load should return []
        let fixes = FixStore.load()
        XCTAssertTrue(fixes.isEmpty, "Expected [] when no file exists, got \(fixes.count) fixes")
    }

    // MARK: - Tests: save then load round-trip

    func testRoundTrip_singleFix_allFieldsPreserved() throws {
        let fix = makeFix(title: "Purge Cache", description: "Clears system cache", command: "sudo purge", severity: "warning")
        try FixStore.save([fix])
        let loaded = FixStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, fix.title)
        XCTAssertEqual(loaded[0].description, fix.description)
        XCTAssertEqual(loaded[0].command, fix.command)
        XCTAssertEqual(loaded[0].severity, fix.severity)
    }

    func testRoundTrip_emptyArray_savesAndLoadsEmpty() throws {
        try FixStore.save([])
        let loaded = FixStore.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testRoundTrip_multipleFixes_preservesOrderAndFields() throws {
        let fixes = [
            makeFix(title: "Fix A", description: "First fix", command: "cmd_a", severity: "low"),
            makeFix(title: "Fix B", description: "Second fix", command: "cmd_b", severity: "critical"),
            makeFix(title: "Fix C", description: "Third fix",  command: "cmd_c", severity: "medium"),
        ]
        try FixStore.save(fixes)
        let loaded = FixStore.load()
        XCTAssertEqual(loaded.count, fixes.count)
        for (original, roundTripped) in zip(fixes, loaded) {
            XCTAssertEqual(roundTripped.title,       original.title)
            XCTAssertEqual(roundTripped.description, original.description)
            XCTAssertEqual(roundTripped.command,     original.command)
            XCTAssertEqual(roundTripped.severity,    original.severity)
        }
    }

    func testRoundTrip_specialCharacters_preservedExactly() throws {
        let fix = makeFix(
            title: "Fix with \"quotes\" & <special>",
            description: "Line1\nLine2",
            command: "awk '{print $1}' /tmp/foo | sort -u",
            severity: "high"
        )
        try FixStore.save([fix])
        let loaded = FixStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title,       fix.title)
        XCTAssertEqual(loaded[0].description, fix.description)
        XCTAssertEqual(loaded[0].command,     fix.command)
        XCTAssertEqual(loaded[0].severity,    fix.severity)
    }

    // MARK: - Tests: overwrite semantics

    func testSave_overwritesPreviousData() throws {
        let firstFix = makeFix(title: "First", command: "echo first")
        try FixStore.save([firstFix])

        let secondFix = makeFix(title: "Second", command: "echo second")
        try FixStore.save([secondFix])

        let loaded = FixStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Second")
    }

    // MARK: - Tests: file is created in the correct location

    func testSave_createsFileAtExpectedPath() throws {
        try FixStore.save([makeFix()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path),
                      "Expected file at \(storeURL.path)")
    }

    // MARK: - Tests: saved data is valid JSON

    func testSave_writesValidJSON() throws {
        let fix = makeFix(title: "JSON Fix", command: "ls -la")
        try FixStore.save([fix])
        let data = try Data(contentsOf: storeURL)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                         "File should contain valid JSON")
    }
}
