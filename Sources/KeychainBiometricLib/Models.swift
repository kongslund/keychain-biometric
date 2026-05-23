import LocalAuthentication

// MARK: - ExitCodeProviding

public protocol ExitCodeProviding {
    var exitCode: Int32 { get }
}

// MARK: - AppError

public enum AppError: Error, LocalizedError, ExitCodeProviding {
    case authFailed(String)
    case authUnavailable(String)
    case itemNotFound
    case keychainError(OSStatus)
    case inputError(String)

    public var exitCode: Int32 {
        switch self {
        case .authFailed, .authUnavailable: return 1
        case .itemNotFound:                 return 2
        case .keychainError:                return 3
        case .inputError:                   return 4
        }
    }

    public var errorDescription: String? {
        switch self {
        case .authFailed(let msg):       return msg
        case .authUnavailable(let msg):  return msg
        case .itemNotFound:              return "Keychain item not found."
        case .keychainError(let status): return "Keychain error: \(status)."
        case .inputError(let msg):       return msg
        }
    }
}

// MARK: - KeychainEntry

public struct KeychainEntry: Equatable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

// MARK: - Authenticating

/// Abstraction over LocalAuthentication. Production code uses `LAAuthManager`;
/// tests inject `MockAuthManager` to avoid biometrics hardware.
public protocol Authenticating {
    func authenticate(reason: String) async throws -> LAContext
}
