package md.vox.android.platformservices

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import java.util.Locale
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

sealed interface CurrentLocationResult {
    data class Available(val latitude: Double, val longitude: Double, val accuracyMeters: Float) : CurrentLocationResult
    data object PermissionDenied : CurrentLocationResult
    data object Restricted : CurrentLocationResult
    data object ReducedAccuracy : CurrentLocationResult
    data object Timeout : CurrentLocationResult
    data object Unavailable : CurrentLocationResult
}

data class CurrentLocationLabel(
    val place: String?,
    val city: String?,
    val region: String?,
    val country: String?,
) {
    val isEmpty: Boolean get() = listOf(place, city, region, country).all { it.isNullOrBlank() }
}

/** One-shot platform location lookup. It never geocodes or contacts an app-owned service. */
class CurrentLocationResolver(context: Context) {
    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(LocationManager::class.java)

    @SuppressLint("MissingPermission") // Both coarse and fine permission paths are checked immediately below.
    suspend fun resolve(
        timeoutMillis: Long = 15_000L,
        exactRequired: Boolean = false,
    ): CurrentLocationResult = suspendCancellableCoroutine { continuation ->
        val userManager = appContext.getSystemService(UserManager::class.java)
        if (userManager?.hasUserRestriction(UserManager.DISALLOW_SHARE_LOCATION) == true) {
            continuation.resume(CurrentLocationResult.Restricted)
            return@suspendCancellableCoroutine
        }
        val hasFine = ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            continuation.resume(CurrentLocationResult.PermissionDenied)
            return@suspendCancellableCoroutine
        }
        if (exactRequired && !hasFine) {
            continuation.resume(CurrentLocationResult.ReducedAccuracy)
            return@suspendCancellableCoroutine
        }

        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
        if (provider == null) {
            continuation.resume(CurrentLocationResult.Unavailable)
            return@suspendCancellableCoroutine
        }

        val finished = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        var cancellationSignal: CancellationSignal? = null
        var legacyListener: LocationListener? = null

        fun finish(result: CurrentLocationResult) {
            if (!finished.compareAndSet(false, true)) return
            legacyListener?.let { runCatching { manager.removeUpdates(it) } }
            cancellationSignal?.cancel()
            if (continuation.isActive) {
                continuation.resume(result)
            }
        }

        fun finishLocation(location: Location?) = finish(
            location?.let { CurrentLocationResult.Available(it.latitude, it.longitude, it.accuracy) }
                ?: CurrentLocationResult.Unavailable,
        )

        handler.postDelayed({ finish(CurrentLocationResult.Timeout) }, timeoutMillis.coerceIn(1_000L, 60_000L))
        continuation.invokeOnCancellation {
            if (finished.compareAndSet(false, true)) {
                legacyListener?.let { listener -> runCatching { manager.removeUpdates(listener) } }
                cancellationSignal?.cancel()
            }
        }

        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                cancellationSignal = CancellationSignal()
                manager.getCurrentLocation(provider, cancellationSignal, appContext.mainExecutor, ::finishLocation)
            } else {
                @Suppress("DEPRECATION")
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) = finishLocation(location)
                    override fun onProviderDisabled(provider: String) = finish(CurrentLocationResult.Unavailable)
                    override fun onProviderEnabled(provider: String) = Unit
                    @Deprecated("Deprecated in Android")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
                }
                legacyListener = listener
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }
        }.onFailure { error ->
            finish(if (error is SecurityException) CurrentLocationResult.PermissionDenied else CurrentLocationResult.Unavailable)
        }
    }

    /**
     * Explicit, consent-gated system reverse geocode. Android may contact a remote
     * backend, so callers must never invoke this unless the frozen preset carries
     * the current disclosure consent. Failure is best-effort and coordinates remain usable.
     */
    suspend fun resolveLabel(
        latitude: Double,
        longitude: Double,
        timeoutMillis: Long = 5_000L,
    ): CurrentLocationLabel? {
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
            return null
        }
        if (!Geocoder.isPresent()) return null
        val address = withTimeoutOrNull(timeoutMillis.coerceIn(1_000L, 30_000L)) {
            reverseGeocode(latitude, longitude)
        } ?: return null
        return address.toFrozenLabel()
    }

    @Suppress("DEPRECATION")
    private suspend fun reverseGeocode(latitude: Double, longitude: Double): Address? {
        val geocoder = Geocoder(appContext, Locale.getDefault())
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            suspendCancellableCoroutine { continuation ->
                val finished = AtomicBoolean(false)
                geocoder.getFromLocation(
                    latitude,
                    longitude,
                    1,
                    object : Geocoder.GeocodeListener {
                        override fun onGeocode(addresses: MutableList<Address>) {
                            if (finished.compareAndSet(false, true) && continuation.isActive) {
                                continuation.resume(addresses.firstOrNull())
                            }
                        }

                        override fun onError(errorMessage: String?) {
                            if (finished.compareAndSet(false, true) && continuation.isActive) {
                                continuation.resume(null)
                            }
                        }
                    },
                )
                continuation.invokeOnCancellation { finished.set(true) }
            }
        } else {
            withContext(Dispatchers.IO) {
                runCatching { geocoder.getFromLocation(latitude, longitude, 1)?.firstOrNull() }.getOrNull()
            }
        }
    }

    private fun Address.toFrozenLabel(): CurrentLocationLabel? {
        fun clean(value: String?): String? = value
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?.take(512)
        val label = CurrentLocationLabel(
            place = clean(featureName),
            city = clean(locality) ?: clean(subLocality),
            region = clean(adminArea),
            country = clean(countryName),
        )
        return label.takeUnless(CurrentLocationLabel::isEmpty)
    }
}
