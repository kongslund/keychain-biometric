import XCTest
@testable import KeychainBiometricLib

final class AppErrorTests: XCTestCase {

    // MARK: - Exit codes

    func testAuthFailedExitCode() {
        XCTAssertEqual(AppError.authFailed("msg").exitCode, 1)
    }

    func testAuthUnavailableExitCode() {
        XCTAssertEqual(AppError.authUnavailable("msg").exitCode, 1)
    }

    func testItemNotFoundExitCode() {
        XCTAssertEqual(AppError.itemNotFound.exitCode, 2)
    }

    func testKeychainErrorExitCode() {
        XCTAssertEqual(AppError.keychainError(-25300).exitCode, 3)
    }

    func testInputErrorExitCode() {
        XCTAssertEqual(AppError.inputError("msg").exitCode, 4)
    }

    // MARK: - Error descriptions

    func testAuthFailedDescription() {
        XCTAssertEqual(
            AppError.authFailed("Authentication cancelled.").errorDescription,
            "Authentication cancelled."
        )
    }

    func testAuthUnavailableDescription() {
        XCTAssertEqual(
            AppError.authUnavailable("No hardware.").errorDescription,
            "No hardware."
        )
    }

    func testItemNotFoundDescription() {
        XCTAssertEqual(AppError.itemNotFound.errorDescription, "Keychain item not found.")
    }

    func testKeychainErrorDescription() {
        XCTAssertEqual(AppError.keychainError(-25300).errorDescription, "Keychain error: -25300.")
    }

    func testInputErrorDescription() {
        XCTAssertEqual(AppError.inputError("Bad input.").errorDescription, "Bad input.")
    }
}
