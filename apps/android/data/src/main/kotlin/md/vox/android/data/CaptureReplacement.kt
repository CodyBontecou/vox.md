package md.vox.android.data

import md.vox.android.capturedomain.*
import java.util.UUID

internal sealed interface ReplacementOutcome {
    data class Ready(val requestID: String) : ReplacementOutcome
    data class Waiting(val requestID: String?) : ReplacementOutcome
    data class Rejected(val code: String) : ReplacementOutcome
}

/** No provider I/O. Durable intent -> fenced source retirement -> immutable replacement enqueue. */
internal class CaptureReplacement(
    private val store: DurableCapturePackageStore,
    private val coordinator: CaptureDurabilityCoordinator,
    private val intents: CaptureRecoveryIntentStore,
    private val clock: () -> Long,
    private val auxiliaryAllowsReplacement: (String) -> Boolean,
    private val completed: (String) -> Boolean = { false },
    private val checkpoint: (String) -> Unit = {},
) {
    fun admit(intent: CaptureRecoveryIntent, authorized: () -> Boolean): ReplacementOutcome = fenced(intent.sourceID) { token ->
        val prior = intents.read(intent.sourceID)
        if (prior != null) {
            if (prior.intentID != intent.intentID || prior.choice != intent.choice ||
                prior.sourceSHA256 != intent.sourceSHA256 || prior.sourceRevision != intent.sourceRevision || prior.sourceState != intent.sourceState ||
                !prior.replacementBytes.contentEquals(intent.replacementBytes)) {
                return@fenced ReplacementOutcome.Rejected("recoveryIntentConflict")
            }
            coordinator.withCurrentLease(intent.sourceID, token, clock()) { intents.persist(prior) }
                ?: return@fenced ReplacementOutcome.Waiting(prior.replacementID)
            return@fenced resume(prior, token)
        }
        coordinator.recoverJournal(intent.sourceID, token, clock())
            ?: return@fenced ReplacementOutcome.Rejected("requestUnavailable")
        val admitted = coordinator.withCurrentLease(intent.sourceID, token, clock()) {
            val current = store.loadJournal(intent.sourceID) ?: return@withCurrentLease false
            val bytes = store.loadRequestBytes(intent.sourceID) ?: return@withCurrentLease false
            if (!authorized() || current.revision != intent.sourceRevision || current.state != intent.sourceState ||
                CapturePackageCodec.sha256(bytes) != intent.sourceSHA256 || !canDiscardCapture(current, store.readCommitMarker(intent.sourceID)) ||
                !auxiliaryAllowsReplacement(intent.sourceID)) return@withCurrentLease false
            val sources = intents.sourceIDs()
            if (sources.size >= 4096 || store.hasPackageEntry(intent.replacementID) || completed(intent.replacementID) ||
                sources.any { source -> intents.read(source)?.replacementID == intent.replacementID }) return@withCurrentLease false
            CapturePackageCodec.admitRequest(intent.replacementBytes)
            intents.persist(intent)
            true
        } ?: false
        if (!admitted) return@fenced ReplacementOutcome.Rejected("staleOrUnauthorizedRecovery")
        checkpoint("intentPersisted")
        resume(intent, token)
    }

    fun replay(sourceID: String): ReplacementOutcome = fenced(sourceID) { token ->
        val intent = intents.read(sourceID) ?: return@fenced ReplacementOutcome.Rejected("recoveryUnavailable")
        // Also completes the rename/directory-sync window after an uncertain intent persist result.
        coordinator.withCurrentLease(sourceID, token, clock()) { intents.persist(intent) }
            ?: return@fenced ReplacementOutcome.Waiting(intent.replacementID)
        resume(intent, token)
    }

    private fun resume(intent: CaptureRecoveryIntent, token: String): ReplacementOutcome {
        val snapshot = coordinator.recoverJournal(intent.sourceID, token, clock())
            ?: return ReplacementOutcome.Waiting(intent.replacementID)
        val bytes = store.loadRequestBytes(intent.sourceID) ?: return ReplacementOutcome.Waiting(intent.replacementID)
        if (CapturePackageCodec.sha256(bytes) != intent.sourceSHA256) return ReplacementOutcome.Rejected("sourceChanged")
        // Verify and retain every asset before retiring the source. The source remains a
        // DISCARDED package, which pruneCompletedPackage cannot remove, even after enqueue.
        val assets = store.loadPackagedAssets(intent.sourceID) ?: return ReplacementOutcome.Waiting(intent.replacementID)
        val event = intent.retirementEvent()
        if (snapshot.state == CaptureState.DISCARDED) {
            if (snapshot.events.last() != event) return ReplacementOutcome.Rejected("sourceRetirementConflict")
        } else if (snapshot.revision != intent.sourceRevision || snapshot.state != intent.sourceState ||
            !canDiscardCapture(snapshot, store.readCommitMarker(intent.sourceID)) || !auxiliaryAllowsReplacement(intent.sourceID)) {
            return ReplacementOutcome.Rejected("sourceFrontierChanged")
        }
        when (coordinator.mutate(JournalMutationCommand(intent.sourceID, intent.sourceRevision, event, token), clock())) {
            is JournalMutationResult.Applied, is JournalMutationResult.AlreadyApplied, is JournalMutationResult.PersistedIndexPending -> Unit
            else -> return ReplacementOutcome.Waiting(intent.replacementID)
        }
        checkpoint("sourceRetired")
        if (completed(intent.replacementID)) return ReplacementOutcome.Ready(intent.replacementID)
        val inputs = assets.map { DurableAssetInput(it.metadata.sourceID, it.metadata.fileName, it.metadata.mediaType, it.bytes) }
        val enqueued = store.enqueue(intent.replacementBytes, clock(), inputs)
        checkpoint("replacementEnqueued")
        return if (enqueued is EnqueueResult.SavedLocally) ReplacementOutcome.Ready(intent.replacementID)
            else ReplacementOutcome.Waiting(intent.replacementID)
    }

    private fun fenced(sourceID: String, action: (String) -> ReplacementOutcome): ReplacementOutcome {
        if (!UUID_PATTERN.matches(sourceID)) return ReplacementOutcome.Rejected("invalidRequest")
        val token = UUID.randomUUID().toString().lowercase()
        if (coordinator.acquire(sourceID, token, clock(), 600_000) !is LeasePlan.Grant) return ReplacementOutcome.Waiting(null)
        return try { action(token) } catch (_: Exception) {
            // Never turn uncertain intent/retirement/enqueue persistence into rejection or fresh-ID retry.
            ReplacementOutcome.Waiting(runCatching { intents.read(sourceID)?.replacementID }.getOrNull())
        } finally { coordinator.release(sourceID, token) }
    }
}
