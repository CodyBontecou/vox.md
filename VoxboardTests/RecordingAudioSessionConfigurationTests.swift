import AVFoundation
import XCTest
@testable import Voxboard
import VoxboardShared

final class RecordingAudioSessionConfigurationTests: XCTestCase {
    func testStandardMatchesTheSessionEveryRecordingUsedBefore() {
        let standard = RecordingAudioSessionConfiguration(.standard)
        XCTAssertEqual(standard, .standard)
        XCTAssertEqual(standard.mode, .default)
        XCTAssertEqual(standard.options, [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        XCTAssertFalse(standard.prefersNoSystemAlertInterruptions)
        XCTAssertTrue(standard.isStandard)
    }

    func testNaturalInputUsesMeasurementModeAndKeepsTheOptions() {
        let natural = RecordingAudioSessionConfiguration(KeptAudioInputOptions(naturalInput: true))
        XCTAssertEqual(natural.mode, .measurement)
        XCTAssertEqual(natural.options, RecordingAudioSessionConfiguration.standard.options)
        XCTAssertFalse(natural.isStandard)
    }

    func testHighQualityBluetoothKeepsHFPAsTheFallback() {
        let configuration = RecordingAudioSessionConfiguration(KeptAudioInputOptions(highQualityBluetooth: true))
        XCTAssertEqual(configuration.mode, .default)
        XCTAssertTrue(configuration.options.contains(.allowBluetooth))
        XCTAssertTrue(configuration.options.contains(.defaultToSpeaker))
        if #available(iOS 26.0, *) {
            XCTAssertTrue(configuration.options.contains(.bluetoothHighQualityRecording))
            XCTAssertTrue(configuration.prefersNoSystemAlertInterruptions)
        } else {
            XCTAssertEqual(configuration, .standard)
        }
    }

    func testBuiltInMicrophoneKeepsAirPodsAsOutputOnly() {
        // Stereo and Spatial Audio: AirPods play over A2DP but are never the
        // microphone (HFP off), and high-quality Bluetooth recording is off.
        let configuration = RecordingAudioSessionConfiguration(
            KeptAudioInputOptions(highQualityBluetooth: true, builtInMicrophone: true)
        )
        XCTAssertEqual(configuration.mode, .default)
        XCTAssertEqual(configuration.options, [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        XCTAssertFalse(configuration.prefersNoSystemAlertInterruptions)
        XCTAssertTrue(configuration.prefersBuiltInMicrophone)
        XCTAssertFalse(RecordingAudioSessionConfiguration.standard.prefersBuiltInMicrophone)
        XCTAssertTrue(configuration.describe().contains("builtInMic"))
    }

    func testApplyingTheStandardSessionSucceeds() throws {
        var messages: [String] = []
        let applied = try RecordingAudioSessionConfiguration.standard.apply(to: .sharedInstance()) { messages.append($0) }
        XCTAssertEqual(applied, .standard)
        XCTAssertTrue(messages.isEmpty)
    }
}
