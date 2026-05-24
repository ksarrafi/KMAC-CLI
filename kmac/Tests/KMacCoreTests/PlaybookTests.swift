import XCTest
@testable import KMacCore

final class PlaybookTests: XCTestCase {

    func testRegistryIntegrity() {
        XCTAssertFalse(Playbooks.all.isEmpty)
        // Unique ids.
        let ids = Playbooks.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "playbook ids must be unique")
        // Every playbook has non-empty fields.
        for p in Playbooks.all {
            XCTAssertFalse(p.id.isEmpty)
            XCTAssertFalse(p.title.isEmpty)
            XCTAssertFalse(p.summary.isEmpty)
            XCTAssertFalse(p.inspect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(p.apply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testExpectedPlaybooksExist() {
        XCTAssertNotNil(Playbooks.find("disk-cleanup"))
        XCTAssertNotNil(Playbooks.find("docker-restart"))
    }

    func testResolveExact() {
        XCTAssertEqual(Playbooks.resolve("disk-cleanup")?.id, "disk-cleanup")
        XCTAssertEqual(Playbooks.resolve("docker-restart")?.id, "docker-restart")
    }

    func testResolvePrefix() {
        XCTAssertEqual(Playbooks.resolve("disk")?.id, "disk-cleanup")
        XCTAssertEqual(Playbooks.resolve("docker")?.id, "docker-restart")
    }

    func testResolveContains() {
        // "restart" isn't a prefix of any id but is contained in docker-restart.
        XCTAssertEqual(Playbooks.resolve("restart")?.id, "docker-restart")
        XCTAssertEqual(Playbooks.resolve("cleanup")?.id, "disk-cleanup")
    }

    func testResolveCaseInsensitive() {
        XCTAssertEqual(Playbooks.resolve("DOCKER")?.id, "docker-restart")
    }

    func testResolveUnknownReturnsNil() {
        XCTAssertNil(Playbooks.resolve("definitely-not-a-playbook"))
        XCTAssertNil(Playbooks.find("nope"))
    }

    func testDiskCleanupIsDestructiveDockerIsNot() {
        XCTAssertEqual(Playbooks.find("disk-cleanup")?.destructive, true)
        XCTAssertEqual(Playbooks.find("docker-restart")?.destructive, false)
    }
}
