import XCTest
@testable import VoxboardShared

/// Route switch "Transcribe Recordings" (#163).
final class CapturePresetTranscriptionEnabledTests: XCTestCase {
    func test_legacyPayloadDecodesAsTranscribingAndOmitsKey() throws {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book"}"#.utf8)
        let preset = try JSONDecoder().decode(CapturePreset.self, from: data)
        XCTAssertTrue(preset.transcriptionEnabled)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any]
        XCTAssertNil(object?["transcriptionEnabled"], "the default must not change existing payloads")
    }

    func test_newPresetDefaultsToTranscribing() {
        XCTAssertTrue(CapturePreset(id: "plain", name: "Plain", symbolName: "doc").transcriptionEnabled)
    }

    func test_offRoundTripsAndIsWritten() throws {
        var preset = CapturePreset(id: "field-audio", name: "Field Audio", symbolName: "waveform")
        preset.transcriptionEnabled = false
        let data = try JSONEncoder().encode(preset)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["transcriptionEnabled"] as? Bool, false)
        XCTAssertFalse(try JSONDecoder().decode(CapturePreset.self, from: data).transcriptionEnabled)
    }

    func test_offDoesNotTouchOtherVoiceSettings() throws {
        var preset = CapturePreset(id: "field-audio", name: "Field Audio", symbolName: "waveform")
        preset.transcriptionModelID = TranscriptionBackendID.automatic
        preset.speakerDiarizationEnabled = true
        preset.transcriptionEnabled = false
        let decoded = try JSONDecoder().decode(CapturePreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded.transcriptionModelID, TranscriptionBackendID.automatic)
        XCTAssertTrue(decoded.speakerDiarizationEnabled)
    }
}
