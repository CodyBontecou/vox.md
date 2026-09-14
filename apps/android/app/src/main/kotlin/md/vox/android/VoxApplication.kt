package md.vox.android

import android.app.Application
import androidx.work.Configuration
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.corebridge.productionCoreBridge
import md.vox.android.data.AndroidCaptureRepository
import md.vox.android.platformservices.installLocalLiveSpeechProvider
import md.vox.android.platformservices.SpeechModelManager

class VoxApplication : Application(), Configuration.Provider {
    val compositionRoot: AppCompositionRoot by lazy { AppCompositionRoot.create(this) }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(VoxWorkerFactory { compositionRoot.captureRepository })
            .build()

    override fun onCreate() {
        super.onCreate()
        installLocalLiveSpeechProvider()
        // Begin verifying/materializing the install-time Whisper Small AI pack before the first
        // recording completes. Selection switches to it automatically as soon as it is ready.
        SpeechModelManager.get(this)
        compositionRoot.billingManager.start()
        PrivacySafeDebugLog.record(
            this,
            PrivacySafeDebugLog.Event.APP_STARTED,
            mapOf("version" to appVersionString(this)),
        )
        CaptureDrainWorker.schedule(this)
        RecordingRetentionWorker.scheduleSweep(this)
    }
}

class AppCompositionRoot private constructor(
    val captureRepository: CaptureRepository,
    val billingManager: PlayBillingManager,
) {
    companion object {
        fun create(application: Application): AppCompositionRoot {
            val app = application
            val coreBridge = productionCoreBridge()
            val billingManager = PlayBillingManager.get(app)
            val repository = AndroidCaptureRepository(
                app,
                coreBridge,
                hasUnlimitedAccess = { billingManager.state.value.hasUnlimitedAccess },
                generateImageAltText = LocalImageAltTextGenerator.get()::describe,
            )
            return AppCompositionRoot(repository, billingManager)
        }
    }
}
