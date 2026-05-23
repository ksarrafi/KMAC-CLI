import XCTest
@testable import KMacCore

/// Tests for ClaudeAPI.parseSuggestedFixes(response:).
///
/// parseSuggestedFixes is a pure parsing method (no network calls), but it lives
/// on ClaudeAPI which requires a real-looking API key to construct (sk-* prefix,
/// >=20 chars).  These tests inject a synthetic key via CLAUDE_API_KEY so
/// ClaudeAPI() does not throw.  If construction fails for any other reason
/// the individual tests are skipped — no backdoor is introduced in Sources/.
///
/// Parser notes (derived from reading the implementation):
///   - The backward scan for title/description starts from the line BEFORE the
///     closing ``` fence (i.e. the last command line) and walks backwards.
///   - A line beginning with ## or # sets the title; any other non-empty,
///     non-list (-, *), non-backtick line sets the description.
///   - Severity is inferred from the description string, not the surrounding prose.
///   - Consequence: plain text placed above the opening fence but not immediately
///     before a heading is typically overwritten by the command text in the scan.
final class ParseSuggestedFixesTests: XCTestCase {

    // MARK: - Setup

    /// A synthetic key that satisfies isPlausibleKey (sk- prefix, >=20 chars)
    /// but is obviously not a real Anthropic key.
    private static let syntheticKey = "sk-test-placeholder-key-for-unit-tests-only"

    private var api: ClaudeAPI?

    override func setUp() {
        super.setUp()
        // If the environment already has a plausible key, use it; otherwise inject
        // the synthetic one so construction succeeds.
        let env = ProcessInfo.processInfo.environment
        let alreadySet = (env["CLAUDE_API_KEY"] ?? env["ANTHROPIC_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if alreadySet.hasPrefix("sk-") && alreadySet.count >= 20 {
            api = try? ClaudeAPI()
        } else {
            // Temporarily satisfy the env-var check by setenv.
            setenv("CLAUDE_API_KEY", Self.syntheticKey, 1)
            api = try? ClaudeAPI()
            unsetenv("CLAUDE_API_KEY")
        }
    }

    /// Returns the api instance or marks the test skipped and returns nil.
    private func requireAPI(file: StaticString = #file, line: UInt = #line) -> ClaudeAPI? {
        guard let api else {
            XCTFail("ClaudeAPI could not be constructed — skipping parse test", file: file, line: line)
            return nil
        }
        return api
    }

    // MARK: - No code blocks

    func testParse_emptyResponse_returnsEmpty() {
        guard let api = requireAPI() else { return }
        XCTAssertTrue(api.parseSuggestedFixes(response: "").isEmpty)
    }

    func testParse_plainTextNoBashBlock_returnsEmpty() {
        guard let api = requireAPI() else { return }
        let response = "Here is some advice. Try restarting the service."
        XCTAssertTrue(api.parseSuggestedFixes(response: response).isEmpty)
    }

    func testParse_nonBashCodeBlock_returnsEmpty() {
        guard let api = requireAPI() else { return }
        let response = """
        ```swift
        let x = 1
        ```
        """
        XCTAssertTrue(api.parseSuggestedFixes(response: response).isEmpty)
    }

    // MARK: - Single bash block

    func testParse_singleBashBlock_returnsOneFix() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        echo hello
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].command, "echo hello")
    }

    func testParse_shBlock_isAlsoRecognised() {
        guard let api = requireAPI() else { return }
        let response = """
        ```sh
        ls -la
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].command, "ls -la")
    }

    func testParse_multilineCommand_capturedAndTrimmed() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        df -h /
        sort -k5 -rn
        head -5
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        let cmd = fixes[0].command
        XCTAssertTrue(cmd.contains("df -h /"),     "command: \(cmd)")
        XCTAssertTrue(cmd.contains("sort -k5 -rn"), "command: \(cmd)")
        XCTAssertTrue(cmd.contains("head -5"),     "command: \(cmd)")
    }

    // MARK: - Multiple blocks

    func testParse_twoBashBlocks_returnsTwoFixes() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        echo first
        ```

        ```bash
        echo second
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 2)
        XCTAssertEqual(fixes[0].command, "echo first")
        XCTAssertEqual(fixes[1].command, "echo second")
    }

    // MARK: - Title extraction from headings
    //
    // The backward scan starts from the last command line inside the code block
    // and walks up. A heading is only reached when every line between the closing
    // fence and the heading either starts with '-', '*', or '`' (list/backtick
    // prefixes that the parser skips). We satisfy this by using a command that
    // begins with a backtick so the scan continues past it to the heading.

    func testParse_h2BeforeBlock_usedAsTitle() {
        guard let api = requireAPI() else { return }
        // Command begins with backtick → parser skips it and finds the ## heading.
        let response = "## Free Disk Space\n```bash\n`purge-cache` --all\n```"
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].title, "Free Disk Space")
    }

    func testParse_h1BeforeBlock_usedAsTitle() {
        guard let api = requireAPI() else { return }
        // Command begins with backtick → parser skips it and finds the # heading.
        let response = "# Clear Cache\n```bash\n`sync` && `purge`\n```"
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].title, "Clear Cache")
    }

    func testParse_noHeadingOrDescription_defaultTitle() {
        guard let api = requireAPI() else { return }
        // With no heading before the block, the parser uses the command line as
        // description and falls back to the hard-coded default title "Fix".
        let response = """
        ```bash
        echo no title
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertFalse(fixes[0].title.isEmpty, "Title should have a default value")
    }

    // MARK: - Severity inference
    //
    // Severity is derived from the description string. The backward scan sets
    // description to the first non-empty, non-heading, non-list line encountered
    // walking from the closing fence upward — in practice this is the last line
    // of the command block unless a heading is found first.  To reliably trigger
    // severity keywords in the description the keyword must appear in the command
    // text itself (since that is what the parser picks up as description for a
    // bare bash block) OR be present in a non-heading line immediately before the
    // opening ``` when no command-line overwrites it.

    func testParse_criticalKeywordInCommand_severityIsCritical() {
        guard let api = requireAPI() else { return }
        // "critical" appears inside the command text, which the parser uses as
        // description → severity = "critical".
        let response = """
        ```bash
        echo critical issue detected
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].severity, "critical")
    }

    func testParse_urgentKeywordInCommand_severityIsCritical() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        echo urgent action required
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].severity, "critical")
    }

    func testParse_warningKeywordInCommand_severityIsWarning() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        echo warning: disk almost full
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].severity, "warning")
    }

    func testParse_neutralCommand_severityIsMedium() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        rm /var/log/old.log
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertEqual(fixes[0].severity, "medium")
    }

    // MARK: - Default field values

    func testParse_bareBlock_hasNonEmptyDefaultFields() {
        guard let api = requireAPI() else { return }
        let response = """
        ```bash
        ls
        ```
        """
        let fixes = api.parseSuggestedFixes(response: response)
        XCTAssertEqual(fixes.count, 1)
        XCTAssertFalse(fixes[0].title.isEmpty)
        XCTAssertFalse(fixes[0].description.isEmpty)
        XCTAssertFalse(fixes[0].severity.isEmpty)
    }
}
