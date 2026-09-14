package md.vox.android.data

import md.vox.android.capturedomain.VaultDestination

/**
 * Production candidate-occupancy observation for the materialization control: resolves
 * the destination folder through the SAF gateway and reports which candidate display
 * names already exist. All M3 candidates share one logical folder; a name present in the
 * bounded provider listing marks that candidate occupied.
 */
internal class SafCandidateOccupancy(
    private val gateway: SafDocumentsGateway,
    private val destination: VaultDestination,
) : CoreMaterializationCoordinator.CandidateOccupancySource,
    CoreMaterializationCoordinator.ExistingNoteSource {
    override fun observeOccupiedCandidates(destination: VaultDestination, candidates: List<List<String>>): List<List<String>>? {
        if (candidates.isEmpty()) return emptyList()
        val folderSegments = candidates.first().dropLast(1)
        if (candidates.any { it.dropLast(1) != folderSegments || it.isEmpty() }) return null
        val folder = gateway.resolveFolder(destination, folderSegments, createMissing = false)
            // A folder that does not exist yet means zero occupancy: folders are created
            // only at commit. The destination root must still be reachable, or the
            // observation is an honest failure rather than a fabricated empty set.
            ?: run {
                gateway.resolveFolder(destination, emptyList(), createMissing = false) ?: return null
                return emptyList()
            }
        val names = gateway.listChildDisplayNames(folder) ?: return null
        return candidates.filter { candidate -> candidate.last() in names }
    }

    override fun observeExistingNote(
        destination: VaultDestination,
        logicalPath: List<String>,
        maximumBytes: Long,
    ): CoreMaterializationCoordinator.ExistingNoteSnapshot? {
        if (logicalPath.isEmpty() || maximumBytes !in 1..268_435_456L) return null
        val folder = gateway.resolveFolder(destination, logicalPath.dropLast(1), createMissing = false)
            ?: return if (gateway.resolveFolder(destination, emptyList(), createMissing = false) != null) {
                CoreMaterializationCoordinator.ExistingNoteSnapshot.Absent
            } else {
                null
            }
        val matches = gateway.findChildByDisplayName(folder, logicalPath.last())
        if (matches.isEmpty()) return CoreMaterializationCoordinator.ExistingNoteSnapshot.Absent
        if (matches.size != 1) return null
        return when (val bytes = gateway.readDocument(matches.single(), maximumBytes)) {
            is SafResult.Success -> CoreMaterializationCoordinator.ExistingNoteSnapshot.Present(bytes.value)
            is SafResult.Error -> null
        }
    }
}
