import Foundation
import LocalAuthentication

// Touch ID and password-based unlock.
// Re-entry guard prevents stacked biometric dialogs from rapid shortcut presses.

class UnlockManager {
    var onUnlock: (@Sendable () -> Void)?
    private var isAuthenticating = false

    func requestUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

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
            DispatchQueue.main.async {
                self?.isAuthenticating = false
                if success {
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
            DispatchQueue.main.async {
                self?.isAuthenticating = false
                if success {
                    self?.onUnlock?()
                }
            }
        }
    }
}
