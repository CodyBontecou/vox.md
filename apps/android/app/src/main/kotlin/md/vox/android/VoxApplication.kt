package md.vox.android

import android.app.Application
import androidx.work.Configuration
import md.vox.android.capturedomain.CaptureAvailability
import md.vox.android.capturedomain.CaptureFoundation
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.corebridge.productionCoreBridge
import md.vox.android.data.AndroidCaptureRepository

class VoxApplication : Application(), Configuration.Provider {
    val compositionRoot: AppCompositionRoot by lazy { AppCompositionRoot.create(this) }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(VoxWorkerFactory { compositionRoot.captureRepository })
            .build()

    override fun onCreate() {
        super.onCreate()
        CaptureDrainWorker.schedule(this)
    }
}

class AppCompositionRoot private constructor(
    val captureFoundation: CaptureFoundation,
) {
    val captureRepository: CaptureRepository get() = captureFoundation.captureRepository

    companion object {
        fun create(application: Application): AppCompositionRoot {
            val app = application
            val coreBridge = productionCoreBridge()
            val repository = AndroidCaptureRepository(app, coreBridge)
            val captureFoundation = object : CaptureFoundation {
                override val coreBridge = coreBridge
                override val captureRepository = repository
                override val captureAvailability = CaptureAvailability.READY
            }
            return AppCompositionRoot(captureFoundation)
        }
    }
}
