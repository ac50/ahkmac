import XCTest
@testable import AhkMacCore

final class ScopeTests: XCTestCase {
    func testMatches() {
        XCTAssertTrue(Scope.global.matches(app: "com.apple.safari"))
        XCTAssertTrue(Scope.global.matches(app: nil))
        XCTAssertTrue(Scope.apps(["com.apple.safari"]).matches(app: "com.apple.safari"))
        XCTAssertFalse(Scope.apps(["com.apple.safari"]).matches(app: "com.apple.mail"))
        XCTAssertFalse(Scope.apps(["com.apple.safari"]).matches(app: nil))
        XCTAssertFalse(Scope.exceptApps(["com.apple.safari"]).matches(app: "com.apple.safari"))
        XCTAssertTrue(Scope.exceptApps(["com.apple.safari"]).matches(app: "com.apple.mail"))
        XCTAssertTrue(Scope.exceptApps(["com.apple.safari"]).matches(app: nil))
    }

    func testLevel() {
        XCTAssertEqual(Scope.apps(["a.b"]).level, 2)
        XCTAssertEqual(Scope.exceptApps(["a.b"]).level, 1)
        XCTAssertEqual(Scope.global.level, 0)
    }

    func testMayOverlap() {
        let safari = Scope.apps(["com.apple.safari"])
        let mail = Scope.apps(["com.apple.mail"])
        let both = Scope.apps(["com.apple.safari", "com.apple.mail"])
        XCTAssertTrue(Scope.global.mayOverlap(.global))
        XCTAssertTrue(safari.mayOverlap(both))
        XCTAssertFalse(safari.mayOverlap(mail))
        XCTAssertTrue(Scope.exceptApps(["a.b"]).mayOverlap(.exceptApps(["c.d"])))
        // 不同层级从不算重叠(具体者运行时覆盖,合法)
        XCTAssertFalse(safari.mayOverlap(.global))
        XCTAssertFalse(safari.mayOverlap(.exceptApps(["com.apple.safari"])))
        XCTAssertFalse(Scope.exceptApps(["a.b"]).mayOverlap(.global))
    }
}
