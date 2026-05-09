import XCTest
@testable import Guardian

@MainActor
final class DurationParsingTests: XCTestCase {

    func testParseSeconds() throws {
        XCTAssertEqual(try GuardianCLI.parseDuration("30s"), 30)
        XCTAssertEqual(try GuardianCLI.parseDuration("30"), 30)
    }

    func testParseMinutes() throws {
        XCTAssertEqual(try GuardianCLI.parseDuration("5m"), 300)
        XCTAssertEqual(try GuardianCLI.parseDuration("30m"), 1800)
    }

    func testParseHours() throws {
        XCTAssertEqual(try GuardianCLI.parseDuration("1h"), 3600)
        XCTAssertEqual(try GuardianCLI.parseDuration("8h"), 28800)
        XCTAssertEqual(try GuardianCLI.parseDuration("2h"), 7200)
    }

    func testRejectsNegative() {
        XCTAssertThrowsError(try GuardianCLI.parseDuration("-1h")) { error in
            XCTAssertTrue(error.localizedDescription.contains("positive"))
        }
    }

    func testRejectsZero() {
        XCTAssertThrowsError(try GuardianCLI.parseDuration("0h")) { error in
            XCTAssertTrue(error.localizedDescription.contains("positive"))
        }
    }

    func testRejectsExceedsMax() {
        XCTAssertThrowsError(try GuardianCLI.parseDuration("25h")) { error in
            XCTAssertTrue(error.localizedDescription.contains("24h"))
        }
    }

    func testRejectsUnknownUnit() {
        XCTAssertThrowsError(try GuardianCLI.parseDuration("5d"))
    }
}

@MainActor
final class FormattingTests: XCTestCase {

    func testFormatSecondsOnly() {
        XCTAssertEqual(GuardianCLI.formatDuration(45), "45s")
    }

    func testFormatMinutesAndSeconds() {
        XCTAssertEqual(GuardianCLI.formatDuration(125), "2m 5s")
    }

    func testFormatHours() {
        XCTAssertEqual(GuardianCLI.formatDuration(3661), "1h 1m 1s")
    }

    func testFormatZero() {
        XCTAssertEqual(GuardianCLI.formatDuration(0), "0s")
    }
}

// Thread-safe result collector for @Sendable callbacks
private final class TestResult: @unchecked Sendable {
    let lock = NSLock()
    private var _output = ""
    private var _exitCode: Int32 = -1
    private var _fulfilled = false
    let expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    var output: String {
        lock.withLock { _output }
    }

    var exitCode: Int32 {
        lock.withLock { _exitCode }
    }

    func appendOutput(_ text: String) {
        lock.withLock { _output += text }
    }

    func setExitCode(_ code: Int32) {
        lock.withLock {
            _exitCode = code
            if !_fulfilled {
                _fulfilled = true
                expectation.fulfill()
            }
        }
    }
}

@MainActor
final class ProcessMonitorTests: XCTestCase {

    func testLaunchEcho() async throws {
        let expectation = self.expectation(description: "Process exits")
        let result = TestResult(expectation: expectation)

        let monitor = ProcessMonitor()
        monitor.onOutput = { output in
            result.appendOutput(output)
        }
        monitor.onExit = { code in
            result.setExitCode(code)
        }

        let pid = try monitor.launch(command: ["/bin/echo", "hello guardian"])
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("hello guardian"))
    }

    func testLaunchExitCode() async throws {
        let expectation = self.expectation(description: "Process exits")
        let result = TestResult(expectation: expectation)

        let monitor = ProcessMonitor()
        monitor.onExit = { code in
            result.setExitCode(code)
        }

        _ = try monitor.launch(command: ["/bin/bash", "-c", "exit 42"])

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(result.exitCode, 42)
    }

    func testLaunchSleep() throws {
        let monitor = ProcessMonitor()
        let pid = try monitor.launch(command: ["/bin/sleep", "300"])
        XCTAssertGreaterThan(pid, 0)
        XCTAssertTrue(monitor.isRunning)

        monitor.terminate()
        XCTAssertFalse(monitor.isRunning)
    }

    func testDoubleTerminate() throws {
        let monitor = ProcessMonitor()
        _ = try monitor.launch(command: ["/bin/sleep", "300"])

        monitor.terminate()
        monitor.terminate()  // Should not crash
    }
}
