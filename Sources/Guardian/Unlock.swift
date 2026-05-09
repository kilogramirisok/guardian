import Foundation
import LocalAuthentication

// Touch ID and password-based unlock.
// LocalAuthentication provides biometric auth via LAContext.

class UnlockManager {
    var onUnlock: (() -> Void)?

    func requestUnlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback to password if Touch ID not available
            requestPasswordUnlock()
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Guardian"
        ) { [weak self] success, _ in
            if success {
                DispatchQueue.main.async {
                    self?.onUnlock?()
                }
            }
            // Failed auth — stay locked, user can try again
        }
    }

    func requestPasswordUnlock() {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Enter password to unlock Guardian"
        ) { [weak self] success, _ in
            if success {
                DispatchQueue.main.async {
                    self?.onUnlock?()
                }
            }
        }
    }
}
