import XCTest
@testable import KMacCore

final class SystemStatusTests: XCTestCase {
    func testSystemStatusInit() {
        let status = SystemStatus()
        XCTAssertNotNil(status)
    }
    
    func testSystemStatusPrinting() {
        let status = SystemStatus()
        // This test verifies the method doesn't crash
        status.printStatus()
    }
}
