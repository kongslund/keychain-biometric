import LocalAuthentication
@testable import KeychainBiometricLib

/// Test double for `Authenticating`. Returns a pre-configured result without
/// touching biometrics hardware.
final class MockAuthManager: Authenticating {
    var result: Result<LAContext, Error>

    /// Convenience: succeeds with a fresh unevaluated context by default.
    init(succeeds: Bool = true) {
        self.result = succeeds
            ? .success(LAContext())
            : .failure(AppError.authFailed("Authentication failed."))
    }

    init(result: Result<LAContext, Error>) {
        self.result = result
    }

    func authenticate(reason: String) async throws -> LAContext {
        try result.get()
    }
}
