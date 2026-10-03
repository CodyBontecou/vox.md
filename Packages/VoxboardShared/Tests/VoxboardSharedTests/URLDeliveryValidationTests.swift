import XCTest
@testable import VoxboardShared

final class URLDeliveryValidationTests: XCTestCase {

    func test_validate_httpsRemote_isAccepted() throws {
        let url = try URLDeliveryValidator.validate("https://example.invalid/ingest")
        XCTAssertEqual(url.host, "example.invalid")
        XCTAssertEqual(url.path, "/ingest")
    }

    func test_validate_httpRemote_isRejected() {
        XCTAssertThrowsError(try URLDeliveryValidator.validate("http://example.invalid/ingest")) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .insecureScheme)
        }
    }

    func test_validate_httpLoopback_requiresExplicitLocalConfirmation() throws {
        XCTAssertThrowsError(
            try URLDeliveryValidator.validate("http://127.0.0.1:8080/ingest")
        ) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .insecureLocalRequiresConfirmation)
        }
        let url = try URLDeliveryValidator.validate(
            "http://127.0.0.1:8080/ingest",
            allowingInsecureLocal: true
        )
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 8080)
    }

    func test_validate_localNetworkLiterals_areRecognized() {
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("localhost"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("::1"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("mac.local"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("10.0.0.4"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("172.16.5.9"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("192.168.1.20"))
        XCTAssertTrue(URLDeliveryValidator.isLocalHost("169.254.10.1"))
        XCTAssertFalse(URLDeliveryValidator.isLocalHost("172.32.0.1"))
        XCTAssertFalse(URLDeliveryValidator.isLocalHost("example.invalid"))
    }

    func test_validate_credentialsInURL_areRejected() {
        XCTAssertThrowsError(try URLDeliveryValidator.validate("https://user:pass@example.invalid/ingest")) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .credentialsInURL)
        }
    }

    func test_validate_queryStringSecret_isRejected() {
        XCTAssertThrowsError(try URLDeliveryValidator.validate("https://example.invalid/ingest?token=abc")) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .queryStringSecret)
        }
    }

    func test_validate_emptyAndUnsupportedScheme_areRejected() {
        XCTAssertThrowsError(try URLDeliveryValidator.validate("   ")) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .emptyURL)
        }
        XCTAssertThrowsError(try URLDeliveryValidator.validate("ftp://example.invalid/ingest")) { error in
            XCTAssertEqual(error as? URLDeliveryValidationError, .invalidURL)
        }
    }

    func test_validateBody_overCap_isRejected() throws {
        let oversized = Data(count: URLDeliveryValidator.maxBodyBytes + 1)
        XCTAssertThrowsError(try URLDeliveryValidator.validateBody(oversized)) { error in
            guard case URLDeliveryValidationError.bodyTooLarge(let bytes) = error else {
                return XCTFail("expected bodyTooLarge, got \(error)")
            }
            XCTAssertEqual(bytes, URLDeliveryValidator.maxBodyBytes + 1)
        }
        XCTAssertNoThrow(try URLDeliveryValidator.validateBody(Data(count: 64)))
    }
}
