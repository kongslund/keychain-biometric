import LocalAuthentication

/// Production authentication manager. Evaluates `.deviceOwnerAuthentication`,
/// which tries TouchID/Face ID first and falls back to the macOS login password.
public final class LAAuthManager: Authenticating {

    public init() {}

    public func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        var canEvalError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvalError) else {
            throw AppError.authUnavailable(
                canEvalError?.localizedDescription ?? "Authentication is unavailable."
            )
        }

        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch let laError as LAError {
            throw AppError.authFailed(Self.message(for: laError))
        }

        return context
    }

    private static func message(for error: LAError) -> String {
        switch error.code {
        case .userCancel:
            return "Authentication cancelled."
        case .userFallback, .authenticationFailed:
            return "Authentication failed."
        case .biometryNotEnrolled:
            return "No biometrics enrolled and no password set."
        case .biometryLockout:
            return "Biometry is locked. Authentication failed."
        default:
            return "Authentication error: \(error.localizedDescription)."
        }
    }
}
