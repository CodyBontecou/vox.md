package md.vox.android.data

/** Replay admitted decisions before selecting pending packages, including retired sources. */
internal fun reconcileCaptureRecoveries(
    store: DurableCapturePackageStore,
    intents: CaptureRecoveryIntentStore,
    replacements: CaptureReplacement,
): Int {
    store.reconcile()
    // Accepted intents are existing durable work, including after access ends.
    // Waiting includes an occupied source lease and uncertain persistence. Neither
    // can be reported to the background worker as an empty, successfully drained queue.
    return intents.sourceIDs().count { replacements.replay(it) is ReplacementOutcome.Waiting }
}
