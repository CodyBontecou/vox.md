package md.vox.android.platformservices

/**
 * Process-local bridge from the phone app's billing owner to shared capture services.
 * The phone application installs the last verified value before any transcription work starts.
 * Wear never grants unlimited access and does not depend on Play Billing.
 */
object UnlimitedAccessRegistry {
    @Volatile private var unlimited = false

    fun update(hasUnlimitedAccess: Boolean) {
        unlimited = hasUnlimitedAccess
    }

    fun hasUnlimitedAccess(): Boolean = unlimited
}
