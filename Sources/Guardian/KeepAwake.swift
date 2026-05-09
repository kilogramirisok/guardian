import Foundation
import IOKit
import IOKit.pwr_mgmt

// Prevents system and display sleep using IOKit power assertions.
// Same mechanism as `caffeinate -d -i -s`.

class KeepAwake {
    private var sleepAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var idleAssertionID: IOPMAssertionID = 0
    private var isAssertionActive = false

    func activate() -> Bool {
        // Prevent system sleep
        let sleepReason = "Guardian: prevent system sleep" as CFString
        let sleepResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            .default,
            sleepReason,
            &sleepAssertionID
        )

        // Prevent display sleep
        let displayReason = "Guardian: prevent display sleep" as CFString
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            .default,
            displayReason,
            &displayAssertionID
        )

        // Prevent idle sleep
        let idleReason = "Guardian: prevent idle sleep" as CFString
        let idleResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            .default,
            idleReason,
            &idleAssertionID
        )

        let success = sleepResult == kIOReturnSuccess
            && displayResult == kIOReturnSuccess
            && idleResult == kIOReturnSuccess

        isAssertionActive = success
        return success
    }

    func deactivate() {
        guard isAssertionActive else { return }

        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if idleAssertionID != 0 {
            IOPMAssertionRelease(idleAssertionID)
            idleAssertionID = 0
        }
        isAssertionActive = false
    }

    deinit {
        deactivate()
    }
}
