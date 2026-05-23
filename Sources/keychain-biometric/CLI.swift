import ArgumentParser
import Darwin
import Foundation
import LocalAuthentication
import KeychainBiometricLib

// MARK: - Root command

@main
struct KeychainBiometric: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keychain-biometric",
        abstract: "Read, write, delete, and list Keychain passwords — authenticated by TouchID.",
        version: "1.0.0",
        subcommands: [ReadCmd.self, WriteCmd.self, DeleteCmd.self, ListCmd.self]
    )

    /// Custom entry point so `AppError` exit codes (1–4) reach the shell.
    /// Without this override, ArgumentParser would always exit with 1 on error.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCmd = command as? AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try command.run()
            }
        } catch {
            if let appError = error as? AppError {
                fputs("Error: \(appError.localizedDescription)\n", stderr)
                Darwin.exit(appError.exitCode)
            }
            KeychainBiometric.exit(withError: error)
        }
    }
}

// MARK: - PreAuthenticated

/// Wraps an already-evaluated LAContext so KeychainManager can be called
/// with a context that was obtained before the password was read from stdin/TTY.
private struct PreAuthenticated: Authenticating {
    let context: LAContext
    func authenticate(reason: String) async throws -> LAContext { context }
}

// MARK: - Password input helper

/// Reads a password from stdin (piped) or an interactive hidden TTY prompt.
/// Must be called only after authentication has already succeeded.
private func readPassword() throws -> String {
    if isatty(STDIN_FILENO) == 0 {
        // Stdin is a pipe — consume one line from the buffer.
        guard let line = readLine(strippingNewline: true), !line.isEmpty else {
            throw AppError.inputError("No password provided on stdin.")
        }
        return line
    } else {
        // Interactive TTY — hidden prompt via readpassphrase(3).
        var buf = [CChar](repeating: 0, count: 1024)
        guard readpassphrase("Password: ", &buf, buf.count, 0) != nil else {
            throw AppError.inputError("Could not read password from terminal.")
        }
        let password = String(cString: buf)
        for i in buf.indices { buf[i] = 0 }   // zero the C buffer
        return password
    }
}

// MARK: - read

extension KeychainBiometric {
    struct ReadCmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Read a password from the Keychain and print it to stdout."
        )

        @Option(help: "The Keychain service name.") var service: String
        @Option(help: "The Keychain account name.") var account: String

        func run() async throws {
            let manager = KeychainManager.production(auth: LAAuthManager())
            let password = try await manager.read(service: service, account: account)
            // No trailing newline — callers like offlineimap read the raw bytes.
            print(password, terminator: "")
        }
    }
}

// MARK: - write

extension KeychainBiometric {
    struct WriteCmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "write",
            abstract: "Write (or update) a password in the Keychain."
        )

        @Option(help: "The Keychain service name.") var service: String
        @Option(help: "The Keychain account name.") var account: String
        @Option(
            help: "Human-readable label shown in Keychain Access.app (default: \"<service>: <account>\")."
        ) var label: String?

        func run() async throws {
            let resolvedLabel = label ?? "\(service): \(account)"
            // Authenticate first — password is read only after TouchID succeeds,
            // minimising the window it is held in process memory.
            let context = try await LAAuthManager().authenticate(
                reason: "write password for '\(service)' (\(account))"
            )
            let password = try readPassword()
            let manager = KeychainManager.production(auth: PreAuthenticated(context: context))
            try await manager.write(service: service, account: account,
                                    password: password, label: resolvedLabel)
            fputs("Password saved to keychain.\n", stderr)
        }
    }
}

// MARK: - delete

extension KeychainBiometric {
    struct DeleteCmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a password from the Keychain."
        )

        @Option(help: "The Keychain service name.") var service: String
        @Option(help: "The Keychain account name.") var account: String

        func run() async throws {
            let manager = KeychainManager.production(auth: LAAuthManager())
            try await manager.delete(service: service, account: account)
            fputs("Password deleted from keychain.\n", stderr)
        }
    }
}

// MARK: - list

extension KeychainBiometric {
    struct ListCmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List Keychain entries (service and account names only, no passwords)."
        )

        @Option(help: "Filter results by service name.") var service: String?

        func run() async throws {
            let manager = KeychainManager.production(auth: LAAuthManager())
            let entries = try await manager.list(service: service)
            for entry in entries {
                print("\(entry.service)\t\(entry.account)")
            }
        }
    }
}
