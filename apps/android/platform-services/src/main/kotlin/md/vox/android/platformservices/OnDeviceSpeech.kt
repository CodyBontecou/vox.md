package md.vox.android.platformservices

import android.content.Context
import android.os.Build
import android.speech.SpeechRecognizer

enum class OnDeviceSpeechAvailability {
    AVAILABLE,
    NOT_AVAILABLE,
    REQUIRES_ANDROID_12,
    CHECK_FAILED,
}

data class OnDeviceSpeechCapability(
    val availability: OnDeviceSpeechAvailability,
    val platformAPI: Int,
) {
    val canCreateExplicitOnDeviceRecognizer: Boolean
        get() = availability == OnDeviceSpeechAvailability.AVAILABLE
}

object OnDeviceSpeechProbe {
    fun inspect(context: Context): OnDeviceSpeechCapability {
        val api = Build.VERSION.SDK_INT
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return resolveOnDeviceSpeechCapability(api, null)
        val reported = runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(context.applicationContext) }.getOrNull()
        return resolveOnDeviceSpeechCapability(api, reported)
    }
}

internal fun resolveOnDeviceSpeechCapability(api: Int, reportedAvailable: Boolean?): OnDeviceSpeechCapability =
    OnDeviceSpeechCapability(
        availability = when {
            api < 31 -> OnDeviceSpeechAvailability.REQUIRES_ANDROID_12
            reportedAvailable == true -> OnDeviceSpeechAvailability.AVAILABLE
            reportedAvailable == false -> OnDeviceSpeechAvailability.NOT_AVAILABLE
            else -> OnDeviceSpeechAvailability.CHECK_FAILED
        },
        platformAPI = api,
    )
