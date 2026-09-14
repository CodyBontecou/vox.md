# Wear entry points are declared in the manifest and instantiated by Android/Google Play services.
-keep class md.vox.android.wear.WearMainActivity { *; }
-keep class md.vox.android.platformservices.AudioCaptureService { *; }
-keep class md.vox.android.wear.VoxCaptureTileService { *; }
-keep class md.vox.android.wear.VoxCaptureComplicationService { *; }
-keep class md.vox.android.wear.WearDataListenerService { *; }
-keep class md.vox.android.wear.WearRecordingNotificationExtender { public <init>(); public *; }
