package md.vox.android.data

import md.vox.android.capturedomain.CaptureState
import md.vox.android.corebridge.CoreBuildInfo
import md.vox.android.corebridge.CoreResult

internal sealed interface CompletionCompactionResult {
    data object Compacted : CompletionCompactionResult
    data object AlreadyCompacted : CompletionCompactionResult
    data class Deferred(val code: String) : CompletionCompactionResult
}

/**
 * Converts a verified completed capture package into its privacy-safe durable tail.
 * Ordering is deliberate: quota proof and coarse activity first, then the ID/time-only
 * completion marker, then deletion of every content-bearing package byte.
 */
internal class CompletedCaptureCompactor(
    private val store: DurableCapturePackageStore,
    private val quota: RoomQuotaLedger,
    private val activity: RoomActivityStatsLedger,
    private val completions: RoomCaptureCompletionLedger,
    private val buildInfo: () -> CoreResult<CoreBuildInfo>,
    private val rendererVersion: String,
    private val profileID: String,
) {
    fun compact(requestID: String): CompletionCompactionResult {
        val existingCompletion = completions.read(requestID)
        val snapshot = store.loadJournal(requestID)
        if (snapshot == null) {
            return if (existingCompletion != null) CompletionCompactionResult.AlreadyCompacted
            else CompletionCompactionResult.Deferred("completedPackageMissing")
        }
        if (snapshot.state != CaptureState.COMPLETED) {
            return CompletionCompactionResult.Deferred("captureNotCompleted")
        }
        val request = store.loadRequestBytes(requestID)
            ?.let { runCatching { CapturePackageCodec.decodeHistoricalRequest(it) }.getOrNull() }
            ?: return CompletionCompactionResult.Deferred("completedRequestInvalid")
        val receiptID = snapshot.events.lastOrNull()?.receiptID
            ?: return CompletionCompactionResult.Deferred("completedReceiptMissing")
        val receipt = store.loadReceipt(requestID, receiptID)
            ?: return CompletionCompactionResult.Deferred("completedReceiptInvalid")
        if (receipt.requestID != requestID) return CompletionCompactionResult.Deferred("completedReceiptCorrelation")
        val info = (buildInfo() as? CoreResult.Success)?.value
            ?: return CompletionCompactionResult.Deferred("coreBuildInfoUnavailable")
        val terminal = quota.commitVerifiedTerminal(
            VerifiedTerminalDraft(
                requestID = requestID,
                completedAtEpochMillis = snapshot.events.last().occurredAtEpochMillis,
                destinationID = receipt.destinationID,
                receiptID = receiptID,
                packageVersion = 1,
                journalVersion = 1,
                requestContractVersion = 1,
                finalJournalRevision = snapshot.revision,
                coreVersion = info.coreVersion,
                rendererVersion = rendererVersion,
                profileID = profileID,
                profileVersion = 1,
            ),
        )
        if (terminal !in setOf(TerminalQuotaResult.COMMITTED, TerminalQuotaResult.IDENTICAL)) {
            return CompletionCompactionResult.Deferred("terminalQuota${terminal.name.lowercase().replaceFirstChar(Char::uppercaseChar)}")
        }
        if (!activity.recordCapture(
                requestID = requestID,
                completedAtEpochMillis = snapshot.events.last().occurredAtEpochMillis,
                source = request.captureSource,
                attachmentCount = store.loadPackagedAssets(requestID)?.size ?: 0,
            )
        ) return CompletionCompactionResult.Deferred("activityPersistence")
        if (!completions.record(requestID, snapshot.events.last().occurredAtEpochMillis)) {
            return CompletionCompactionResult.Deferred("completionConflict")
        }
        if (!store.pruneCompletedPackage(requestID)) {
            return CompletionCompactionResult.Deferred("completedPackagePrune")
        }
        return CompletionCompactionResult.Compacted
    }
}
