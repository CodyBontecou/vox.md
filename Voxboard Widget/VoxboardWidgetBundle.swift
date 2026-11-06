import WidgetKit
import SwiftUI

@main
struct VoxboardWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoxboardRecordWidget()
        VoxboardCaptureWidget()
        CapturePresetWidget()
        RouteSpeakWidget()
        RouteTodayWidget()
        RouteScanWidget()
        if #available(iOSApplicationExtension 17.0, *) {
            VoxboardLiveActivity()
        }
        if #available(iOSApplicationExtension 18.0, *) {
            VoxboardRecordControl()
            VoxboardQuickCaptureControl()
        }
        if #available(iOSApplicationExtension 26.0, *) {
            VoxboardToggleRecordingControl()
        }
    }
}
