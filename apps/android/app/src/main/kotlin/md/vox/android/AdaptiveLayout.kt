package md.vox.android

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalMetrics
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp

internal enum class VoxWindowWidthClass { COMPACT, MEDIUM, EXPANDED }

internal fun classifyVoxWindowWidth(widthDp: Int): VoxWindowWidthClass = when {
    widthDp >= 840 -> VoxWindowWidthClass.EXPANDED
    widthDp >= 600 -> VoxWindowWidthClass.MEDIUM
    else -> VoxWindowWidthClass.COMPACT
}

@Composable
internal fun currentVoxWindowWidthClass(): VoxWindowWidthClass {
    val widthPixels = LocalWindowInfo.current.containerSize.width
    val widthDp = with(LocalDensity.current) { widthPixels.toDp().value.toInt() }
    return classifyVoxWindowWidth(widthDp)
}

@Composable
internal fun AdaptiveDetailPlaceholder(
    title: VoxUiText,
    detail: VoxUiText,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Signal.colors.bg),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SignalEmptyState(
                icon = Icons.Outlined.Description,
                title = title.localized(),
                message = detail.localized(),
                iconTint = Signal.colors.muted,
                modifier = Modifier.widthIn(max = 420.dp),
            )
        }
    }
}
