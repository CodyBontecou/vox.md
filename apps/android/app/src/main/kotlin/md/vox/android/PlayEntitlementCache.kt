package md.vox.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

internal data class CachedPlayEntitlement(
    val productID: String,
    val isOwned: Boolean,
    val checkedAtEpochMillis: Long,
)

/**
 * Installation-scoped, tamper-evident continuity evidence for the last authoritative
 * Google Play ownership query. App backup is disabled, and the HMAC key is non-exportable.
 */
internal class PlayEntitlementCache(
    context: Context,
    private val productID: String,
    private val preferencesName: String = PREFERENCES_NAME,
    private val keyAlias: String = KEY_ALIAS,
) {
    private val preferences = context.applicationContext.getSharedPreferences(
        preferencesName,
        Context.MODE_PRIVATE,
    )

    fun read(): CachedPlayEntitlement? {
        if (!preferences.contains(KEY_PRODUCT_ID) &&
            !preferences.contains(KEY_OWNED) &&
            !preferences.contains(KEY_CHECKED_AT) &&
            !preferences.contains(KEY_MAC)
        ) {
            return null
        }
        val cachedProductID = preferences.getString(KEY_PRODUCT_ID, null)
        val checkedAt = preferences.getLong(KEY_CHECKED_AT, Long.MIN_VALUE)
        val encodedMac = preferences.getString(KEY_MAC, null)
        if (cachedProductID != productID ||
            !preferences.contains(KEY_OWNED) ||
            checkedAt <= 0L ||
            encodedMac.isNullOrBlank()
        ) {
            clear()
            return null
        }
        val isOwned = preferences.getBoolean(KEY_OWNED, false)
        val valid = runCatching {
            val supplied = Base64.decode(encodedMac, Base64.NO_WRAP)
            MessageDigest.isEqual(supplied, signature(payload(cachedProductID, isOwned, checkedAt)))
        }.getOrDefault(false)
        if (!valid) {
            clear()
            return null
        }
        return CachedPlayEntitlement(cachedProductID, isOwned, checkedAt)
    }

    fun write(isOwned: Boolean, checkedAtEpochMillis: Long): Boolean {
        if (checkedAtEpochMillis <= 0L) return false
        return runCatching {
            val encodedMac = Base64.encodeToString(
                signature(payload(productID, isOwned, checkedAtEpochMillis)),
                Base64.NO_WRAP,
            )
            preferences.edit()
                .putString(KEY_PRODUCT_ID, productID)
                .putBoolean(KEY_OWNED, isOwned)
                .putLong(KEY_CHECKED_AT, checkedAtEpochMillis)
                .putString(KEY_MAC, encodedMac)
                .commit()
        }.getOrDefault(false).also { persisted ->
            if (!persisted) clear()
        }
    }

    fun clear() {
        preferences.edit().clear().commit()
    }

    internal fun deleteTestKey() {
        runCatching {
            val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
            if (keyStore.containsAlias(keyAlias)) keyStore.deleteEntry(keyAlias)
        }
    }

    private fun signature(payload: ByteArray): ByteArray = Mac.getInstance(HMAC_ALGORITHM).run {
        init(secretKey())
        doFinal(payload)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, ANDROID_KEY_STORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generateKey()
        }
    }

    private fun payload(productID: String, isOwned: Boolean, checkedAtEpochMillis: Long): ByteArray =
        "$CACHE_VERSION\n$productID\n${if (isOwned) 1 else 0}\n$checkedAtEpochMillis"
            .toByteArray(Charsets.UTF_8)

    companion object {
        internal const val PREFERENCES_NAME = "vox-play-entitlement-v2"
        private const val KEY_ALIAS = "md.vox.android.play-entitlement-v2"
        internal const val KEY_PRODUCT_ID = "product-id"
        internal const val KEY_OWNED = "owned"
        internal const val KEY_CHECKED_AT = "checked-at-epoch-millis"
        internal const val KEY_MAC = "evidence-mac"
        private const val CACHE_VERSION = 2
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val HMAC_ALGORITHM = "HmacSHA256"
    }
}
