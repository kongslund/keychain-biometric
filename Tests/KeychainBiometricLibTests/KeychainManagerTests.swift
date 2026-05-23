import XCTest
import Security
@testable import KeychainBiometricLib

final class KeychainManagerTests: XCTestCase {
    // UUID-namespaced service keeps test items isolated from each other
    // and from any real keychain data.
    private var testService: String!
    private var manager: KeychainManager!

    override func setUp() async throws {
        try await super.setUp()
        testService = "test.keychain-biometric.\(UUID().uuidString)"
        // No access control: tests must not require biometric hardware.
        manager = KeychainManager(auth: MockAuthManager())
    }

    override func tearDown() async throws {
        // Delete all items written under testService, regardless of test outcome.
        SecItemDelete([
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: testService!,
        ] as CFDictionary)
        try await super.tearDown()
    }

    // MARK: - Read

    func testReadReturnsStoredPassword() async throws {
        // Seed item directly via Security framework (bypasses our manager)
        let seed: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: testService!,
            kSecAttrAccount: "user@example.org",
            kSecValueData:   "hunter2".data(using: .utf8)!,
        ]
        XCTAssertEqual(SecItemAdd(seed as CFDictionary, nil), errSecSuccess)

        let password = try await manager.read(service: testService, account: "user@example.org")
        XCTAssertEqual(password, "hunter2")
    }

    func testReadNotFoundThrowsItemNotFound() async throws {
        do {
            _ = try await manager.read(service: testService, account: "nobody@example.org")
            XCTFail("Expected AppError.itemNotFound")
        } catch AppError.itemNotFound {
            // ✓
        }
    }

    func testReadPropagatesAuthFailure() async throws {
        let failing = KeychainManager(
            auth: MockAuthManager(result: .failure(AppError.authFailed("Authentication failed.")))
        )
        do {
            _ = try await failing.read(service: testService, account: "user@example.org")
            XCTFail("Expected auth failure")
        } catch AppError.authFailed(let msg) {
            XCTAssertEqual(msg, "Authentication failed.")
        }
    }

    // MARK: - Write

    func testWriteCreatesNewItem() async throws {
        try await manager.write(
            service: testService,
            account: "user@example.org",
            password: "secret",
            label: "Test label"
        )
        let password = try await manager.read(service: testService, account: "user@example.org")
        XCTAssertEqual(password, "secret")
    }

    func testWriteOverwritesExistingItem() async throws {
        try await manager.write(service: testService, account: "user@example.org",
                                password: "v1", label: "Test")
        try await manager.write(service: testService, account: "user@example.org",
                                password: "v2", label: "Test")
        let password = try await manager.read(service: testService, account: "user@example.org")
        XCTAssertEqual(password, "v2")
    }

    func testWritePropagatesAuthFailure() async throws {
        let failing = KeychainManager(
            auth: MockAuthManager(result: .failure(AppError.authFailed("Authentication failed.")))
        )
        do {
            try await failing.write(service: testService, account: "user@example.org",
                                    password: "s", label: "T")
            XCTFail("Expected auth failure")
        } catch AppError.authFailed(let msg) {
            XCTAssertEqual(msg, "Authentication failed.")
        }
    }

    func testWriteItemsHaveDeviceOnlyAccessibility() async throws {
        try await manager.write(
            service: testService,
            account: "user@example.org",
            password: "secret",
            label: "Test"
        )

        // Verify the item was stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // by including the accessibility as a search predicate. On macOS, kSecAttrAccessible
        // is not returned in kSecReturnAttributes, but it IS honoured as a filter: if the
        // item matches, it was stored with that accessibility value.
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    testService!,
            kSecAttrAccount:    "user@example.org",
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess,
            "Item was not found with kSecAttrAccessibleWhenUnlockedThisDeviceOnly — " +
            "write() must set kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly")
    }

    // MARK: - Delete

    func testDeleteRemovesItem() async throws {
        try await manager.write(service: testService, account: "user@example.org",
                                password: "secret", label: "Test")
        try await manager.delete(service: testService, account: "user@example.org")
        do {
            _ = try await manager.read(service: testService, account: "user@example.org")
            XCTFail("Expected AppError.itemNotFound after delete")
        } catch AppError.itemNotFound {
            // ✓
        }
    }

    func testDeleteNonExistentThrowsItemNotFound() async throws {
        do {
            try await manager.delete(service: testService, account: "nobody@example.org")
            XCTFail("Expected AppError.itemNotFound")
        } catch AppError.itemNotFound {
            // ✓
        }
    }

    // MARK: - List

    func testListReturnsAllEntriesForService() async throws {
        try await manager.write(service: testService, account: "a@example.org",
                                password: "p1", label: "T1")
        try await manager.write(service: testService, account: "b@example.org",
                                password: "p2", label: "T2")

        let entries = try await manager.list(service: testService)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            Set(entries.map(\.account)),
            ["a@example.org", "b@example.org"]
        )
    }

    func testListReturnsEmptyArrayForUnknownService() async throws {
        let entries = try await manager.list(service: testService)
        XCTAssertTrue(entries.isEmpty)
    }

    func testListWithNilServiceReturnsItemsAcrossServices() async throws {
        let otherService = "test.keychain-biometric.\(UUID().uuidString)"
        defer {
            SecItemDelete([
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: otherService,
            ] as CFDictionary)
        }
        try await manager.write(service: testService,  account: "a@example.org",
                                password: "p1", label: "T1")
        try await manager.write(service: otherService, account: "b@example.org",
                                password: "p2", label: "T2")

        let all = try await manager.list(service: nil)
        let services = Set(all.map(\.service))
        XCTAssertTrue(services.contains(testService))
        XCTAssertTrue(services.contains(otherService))
    }
}
