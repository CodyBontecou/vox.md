package md.vox.android

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
    Column(
        modifier = modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Outlined.Description,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(title.localized(), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
        Text(
            detail.localized(),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}
