import XCTest
@testable import Guardian

// Note: InputLock, Overlay, and Unlock tests cannot run on CI
// (require Accessibility permission + display).
// Those are tested manually on real hardware.

final class DurationParsingTests: XCTestCase {

    func testParseSeconds() throws {
        // Test via Lock command argument parsing
        // We test the parseDuration logic indirectly
        XCTAssertEqual(parseDurationTestHelper("30s"), 30)
        XCTAssertEqual(parseDurationTestHelper("30"), 30)
    }

    func testParseMinutes() throws {
        XCTAssertEqual(parseDurationTestHelper("5m"), 300)
        XCTAssertEqual(parseDurationTestHelper("30m"), 1800)
    }

    func testParseHours() throws {
        XCTAssertEqual(parseDurationTestHelper("1h"), 3600)
        XCTAssertEqual(parseDurationTestHelper("8h"), 28800)
        XCTAssertEqual(parseDurationTestHelper("2h"), 7200)
    }
}

final class FormattingTests: XCTestCase {

    func testFormatSecondsOnly() {
        XCTAssertEqual(formatDurationTestHelper(45), "45s")
    }

    func testFormatMinutesAndSeconds() {
        XCTAssertEqual(formatDurationTestHelper(125), "2m 5s")
    }

    func testFormatHours() {
        XCTAssertEqual(formatDurationTestHelper(3661), "1h 1m 1s")
    }

    func testFormatZero() {
        XCTAssertEqual(formatDurationTestHelper(0), "0s")
    }
}

final class ProcessMonitorTests: XCTestCase {

    func testLaunchEcho() throws {
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

        waitForExpectations(timeout: 5)

        XCTAssertTrue(monitor.isRunning == false)
        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(receivedOutput.contains("hello guardian"))
    }

    func testLaunchExitCode() throws {
        let monitor = ProcessMonitor()
        let expectation = self.expectation(description: "Process exits")
        var exitCode: Int32 = -1

        monitor.onExit = { code in
            exitCode = code
            expectation.fulfill()
        }

        _ = try monitor.launch(command: ["/bin/bash", "-c", "exit 42"])

        waitForExpectations(timeout: 5)

        XCTAssertEqual(exitCode, 42)
    }

    func testLaunchSleep() throws {
        let monitor = ProcessMonitor()
        let pid = try monitor.launch(command: ["/bin/sleep", "300"])
        XCTAssertGreaterThan(pid, 0)
        XCTAssertTrue(monitor.isRunning)

        monitor.terminate()

        // After termination, process should no longer be running
        sleep(1)
        XCTAssertFalse(monitor.isRunning)
    }
}
