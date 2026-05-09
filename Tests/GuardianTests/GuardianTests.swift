import XCTest
@testable import Guardian

// InputLock, Overlay, and Unlock tests cannot run on CI
// (require Accessibility permission + display).
// Those are tested manually on real hardware.

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

@MainActor
final class ProcessMonitorTests: XCTestCase {

    func testLaunchEcho() async throws {
        let monitor = ProcessMonitor()
        let expectation = self.expectation(description: "Process exits")
        var receivedOutput = ""
        var exitCode: Int32 = -1

        monitor.onOutput = { output in
            receivedOutput += output
        }

        monitor.onExit = { code in
            exitCode = code
            expectation.fulfill()
        }

        let pid = try monitor.launch(command: ["/bin/echo", "hello guardian"])
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(receivedOutput.contains("hello guardian"))
    }

    func testLaunchExitCode() async throws {
        let monitor = ProcessMonitor()
        let expectation = self.expectation(description: "Process exits")
        var exitCode: Int32 = -1

        monitor.onExit = { code in
            exitCode = code
            expectation.fulfill()
        }

        _ = try monitor.launch(command: ["/bin/bash", "-c", "exit 42"])

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(exitCode, 42)
    }

    func testLaunchSleep() throws {
        let monitor = ProcessMonitor()
        let pid = try monitor.launch(command: ["/bin/sleep", "300"])
        XCTAssertGreaterThan(pid, 0)
        XCTAssertTrue(monitor.isRunning)

        monitor.terminate()
    }
}
