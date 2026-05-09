import Foundation
import LocalAuthentication

// Touch ID and password-based unlock.

class UnlockManager {
    var onUnlock: (() -> Void)?

    func requestUnlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
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
