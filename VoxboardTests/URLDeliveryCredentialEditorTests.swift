import XCTest
import VoxboardShared
@testable import Voxboard

final class URLDeliveryCredentialEditorTests: XCTestCase {
    func testRemovingLastTokenWithoutURLAllowsAnotherAnonymousEndpoint() throws {
        let keychain = TestKeychain(token: "synthetic-token")
        var settings = keychain.settings
        settings.urlString = ""

        try keychain.editor.removeToken(settings: &settings)

        XCTAssertNil(settings.credentialID)
        XCTAssertNil(settings.credentialURLString)
        XCTAssertFalse(settings.hasBearerToken)
        XCTAssertFalse(settings.hasCustomHeaders)
        settings.urlString = "https://example.invalid/another-endpoint"
        XCTAssertNil(try keychain.editor.loadCredentials(settings: &settings))
        try keychain.editor.updateCredentials(settings: &settings) { $0.bearerToken = "replacement-token" }
        XCTAssertEqual(try keychain.editor.loadCredentials(settings: &settings)?.bearerToken, "replacement-token")
    }

    func testRemovingTokenWithoutURLRetainsCustomHeadersAndDestinationBinding() throws {
        let keychain = TestKeychain(token: "synthetic-token", headers: ["X-Synthetic": "stored-header"])
        var settings = keychain.settings
        settings.urlString = ""

        try keychain.editor.removeToken(settings: &settings)

        XCTAssertEqual(settings.credentialID, keychain.id)
        XCTAssertEqual(settings.credentialURLString, keychain.url)
        XCTAssertFalse(settings.hasBearerToken)
        XCTAssertTrue(settings.hasCustomHeaders)
        settings.urlString = keychain.url
        let credentials = try XCTUnwrap(keychain.editor.loadCredentials(settings: &settings))
        XCTAssertNil(credentials.bearerToken)
        XCTAssertEqual(credentials.customHeaders, ["X-Synthetic": "stored-header"])
    }

    func testClearingLastHeaderAllowsAnotherAnonymousEndpoint() throws {
        let keychain = TestKeychain(headers: ["X-Synthetic": "stored-header"])
        var settings = keychain.settings

        try keychain.editor.updateCredentials(settings: &settings) { $0.customHeaders = [:] }

        XCTAssertNil(settings.credentialID)
        XCTAssertNil(settings.credentialURLString)
        XCTAssertFalse(settings.hasBearerToken)
        XCTAssertFalse(settings.hasCustomHeaders)
        settings.urlString = "https://example.invalid/another-endpoint"
        XCTAssertNil(try keychain.editor.loadCredentials(settings: &settings))
    }

    func testFailedAccountDeletionRetainsMetadataAndToken() throws {
        let keychain = TestKeychain(token: "synthetic-token")
        keychain.deleteError = .deleteFailed
        var settings = keychain.settings
        settings.urlString = ""
        let original = settings

        XCTAssertThrowsError(try keychain.editor.removeToken(settings: &settings))

        XCTAssertEqual(settings, original)
        XCTAssertEqual(try keychain.editor.load(keychain.id)?.bearerToken, "synthetic-token")
    }

    func testFailedTokenRemovalSaveRetainsMetadataTokenAndHeaders() throws {
        let keychain = TestKeychain(token: "synthetic-token", headers: ["X-Synthetic": "stored-header"])
        keychain.saveError = .saveFailed
        var settings = keychain.settings
        let original = settings

        XCTAssertThrowsError(try keychain.editor.removeToken(settings: &settings))

        XCTAssertEqual(settings, original)
        let credentials = try XCTUnwrap(keychain.editor.loadCredentials(settings: &settings))
        XCTAssertEqual(credentials.bearerToken, "synthetic-token")
        XCTAssertEqual(credentials.customHeaders, ["X-Synthetic": "stored-header"])
    }

    func testFailedCredentialUpdateRetainsMetadataAndStoredToken() throws {
        let keychain = TestKeychain(token: "synthetic-token")
        keychain.saveError = .saveFailed
        var settings = keychain.settings
        let original = settings

        XCTAssertThrowsError(try keychain.editor.updateCredentials(settings: &settings) { $0.bearerToken = "replacement-token" })

        XCTAssertEqual(settings, original)
        XCTAssertEqual(try keychain.editor.loadCredentials(settings: &settings)?.bearerToken, "synthetic-token")
    }

    func testReopeningEmptyAccountClearsItsOldDestinationBinding() throws {
        let keychain = TestKeychain()
        var settings = keychain.settings
        settings.urlString = "https://example.invalid/another-endpoint"

        XCTAssertNil(try keychain.editor.loadCredentials(settings: &settings))

        XCTAssertNil(settings.credentialID)
        XCTAssertNil(settings.credentialURLString)
        XCTAssertFalse(settings.hasBearerToken)
        XCTAssertFalse(settings.hasCustomHeaders)
    }

    func testReopeningEditedEndpointRetainsBoundTokenAndHeaderDraftsForReverting() throws {
        let keychain = TestKeychain(token: "synthetic-token", headers: ["X-Synthetic": "stored-header"])
        var settings = keychain.settings
        settings.urlString = "https://example.invalid/another-endpoint"
        let original = settings

        let credentials = try XCTUnwrap(keychain.editor.loadBoundCredentials(settings: &settings))

        XCTAssertEqual(credentials.bearerToken, "synthetic-token")
        XCTAssertEqual(credentials.customHeaders, ["X-Synthetic": "stored-header"])
        XCTAssertEqual(credentials.urlString, keychain.url)
        XCTAssertEqual(settings, original)
        settings.urlString = keychain.url
        XCTAssertEqual(try keychain.editor.loadCredentials(settings: &settings), credentials)
    }

    func testReopeningRealCredentialsAtAnotherEndpointFailsWithoutClearingThem() throws {
        for keychain in [TestKeychain(token: "synthetic-token"), TestKeychain(headers: ["X-Synthetic": "stored-header"])] {
            var settings = keychain.settings
            settings.urlString = "https://example.invalid/another-endpoint"
            let original = settings

            XCTAssertThrowsError(try keychain.editor.loadCredentials(settings: &settings)) {
                XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .destinationChanged)
            }

            XCTAssertEqual(settings, original)
            settings.urlString = keychain.url
            XCTAssertNotNil(try keychain.editor.loadCredentials(settings: &settings))
        }
    }

    func testBoundCredentialLoadRejectsIncorrectDestinationBinding() throws {
        let keychain = TestKeychain(token: "synthetic-token", headers: ["X-Synthetic": "stored-header"])
        var settings = keychain.settings
        settings.credentialURLString = "https://example.invalid/incorrect-binding"
        let original = settings

        XCTAssertThrowsError(try keychain.editor.loadBoundCredentials(settings: &settings)) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .destinationChanged)
        }

        XCTAssertEqual(settings, original)
    }

    func testBoundCredentialLoadRejectsMissingAccountWithoutClearingMetadata() throws {
        let keychain = TestKeychain(token: "synthetic-token")
        var settings = keychain.settings
        let original = settings
        try keychain.editor.delete(keychain.id)

        XCTAssertThrowsError(try keychain.editor.loadBoundCredentials(settings: &settings)) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .missingCredentials)
        }

        XCTAssertEqual(settings, original)
    }

    func testBoundCredentialDraftsCannotBeWrittenToAnotherEndpoint() throws {
        let keychain = TestKeychain(token: "synthetic-token", headers: ["X-Synthetic": "stored-header"])
        var settings = keychain.settings
        settings.urlString = "https://example.invalid/another-endpoint"
        let original = settings

        XCTAssertThrowsError(try keychain.editor.updateCredentials(settings: &settings) {
            $0.bearerToken = "replacement-token"
            $0.customHeaders = ["X-Synthetic": "replacement-header"]
        }) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .destinationChanged)
        }

        XCTAssertEqual(settings, original)
        settings.urlString = keychain.url
        let credentials = try XCTUnwrap(keychain.editor.loadCredentials(settings: &settings))
        XCTAssertEqual(credentials.bearerToken, "synthetic-token")
        XCTAssertEqual(credentials.customHeaders, ["X-Synthetic": "stored-header"])
    }

    func testFailedEmptyAccountCleanupRetainsItsBinding() throws {
        let keychain = TestKeychain()
        keychain.deleteError = .deleteFailed
        var settings = keychain.settings
        settings.urlString = "https://example.invalid/another-endpoint"
        let original = settings

        XCTAssertThrowsError(try keychain.editor.loadCredentials(settings: &settings))

        XCTAssertEqual(settings, original)
        XCTAssertEqual(try keychain.editor.load(keychain.id)?.urlString, keychain.url)
    }

    private final class TestKeychain {
        enum TestError: Error { case saveFailed, deleteFailed }
        let id = "00000000-0000-0000-0000-000000000001"
        let url = "https://example.invalid/original"
        private var records: [String: URLDeliveryKeychain.Credentials]
        var saveError: TestError?
        var deleteError: TestError?

        init(token: String? = nil, headers: [String: String] = [:]) {
            records = [id: .init(urlString: url, bearerToken: token, customHeaders: headers)]
        }

        var settings: CapturePresetURLDeliverySettings {
            .init(enabled: true, urlString: url, hasBearerToken: records[id]?.bearerToken != nil,
                  hasCustomHeaders: !(records[id]?.customHeaders.isEmpty ?? true),
                  credentialID: id, credentialURLString: url)
        }

        var editor: URLDeliveryCredentialEditor {
            .init(load: { [self] account in records[account] },
                  save: { [self] credentials, account in
                      if let saveError { throw saveError }
                      records[account] = credentials
                  },
                  delete: { [self] account in
                      if let deleteError { throw deleteError }
                      records.removeValue(forKey: account)
                  })
        }
    }
}
