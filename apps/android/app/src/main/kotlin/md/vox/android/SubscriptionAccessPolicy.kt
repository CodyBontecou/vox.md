package md.vox.android

/** Only complete Play ownership observations can end previously verified subscription access. */
internal fun subscriptionAccessEnded(
    previouslyEnded: Boolean,
    previouslyOwnedSubscription: Boolean,
    authoritativeOwned: Boolean?,
): Boolean = when (authoritativeOwned) {
    true -> false
    false -> previouslyEnded || previouslyOwnedSubscription
    null -> previouslyEnded
}
