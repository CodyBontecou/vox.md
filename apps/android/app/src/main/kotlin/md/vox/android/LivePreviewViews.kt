package md.vox.android

import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.net.Uri
import android.widget.VideoView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalType

/** A preview block whose source is hidden; its first line is [heightSp] tall to make room. */
internal data class HiddenPreviewBlock(val start: Int, val end: Int, val heightSp: Float)

/**
 * Hides each block's characters (transparent, 1sp) and gives its first line the panel's
 * height, so the text layout reserves the space the overlay draws in. Offsets are untouched.
 */
internal fun hidePreviewBlocks(text: AnnotatedString, hidden: List<HiddenPreviewBlock>): AnnotatedString {
    if (hidden.isEmpty()) return text
    val source = text.text
    return buildAnnotatedString {
        append(text)
        for (block in hidden) {
            val start = block.start.coerceIn(0, source.length)
            val end = block.end.coerceIn(start, source.length)
            if (start == end) continue
            addStyle(SpanStyle(color = Color.Transparent, fontSize = 1.sp, background = Color.Transparent), start, end)
            // One paragraph style over the whole block: its lines share the reserved height
            // evenly, so the block is exactly as tall as the panel drawn over it.
            val lines = source.substring(start, end).count { it == '\n' } + 1
            addStyle(
                ParagraphStyle(
                    lineHeight = (block.heightSp / lines).sp,
                    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Top, LineHeightStyle.Trim.None),
                ),
                start,
                end,
            )
        }
    }
}

/** Height reserved for a block's panel (the overlay is sized from the actual layout). */
internal fun previewBlockHeight(block: PreviewBlock): Dp = when (block) {
    is FrontmatterBlock -> (44 + 30 * block.properties.size.coerceAtLeast(1)).dp
    is EmbedBlock -> when (block.kind) {
        EmbedKind.AUDIO -> 72.dp
        EmbedKind.IMAGE -> 272.dp
        EmbedKind.VIDEO -> 232.dp
    }
}

/** Obsidian's Properties panel: muted keys, values, list values as chips. Tap to edit the YAML. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FrontmatterPanel(block: FrontmatterBlock, reveal: () -> Unit, modifier: Modifier = Modifier) {
    val c = Signal.colors
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.card)
            .border(1.dp, c.divider, RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = reveal)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .testTag("live-preview-properties"),
    ) {
        Text(voxString("Properties"), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold), color = c.muted)
        if (block.properties.isEmpty()) {
            Text(voxString("No properties"), style = SignalType.caption, color = c.faint, modifier = Modifier.heightIn(min = 30.dp).padding(top = 6.dp))
        }
        block.properties.forEach { property ->
            Row(Modifier.fillMaxWidth().heightIn(min = 30.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(property.key, style = SignalType.monoCaption, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(96.dp))
                if (property.isList) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), maxLines = 1, modifier = Modifier.weight(1f)) {
                        property.values.forEach { value ->
                            Text(
                                value,
                                style = MaterialTheme.typography.labelSmall,
                                color = c.accentText,
                                maxLines = 1,
                                modifier = Modifier.clip(CircleShape).background(c.accentSoft).padding(horizontal = 8.dp, vertical = 2.dp),
                            )
                        }
                    }
                } else {
                    Text(property.values.firstOrNull().orEmpty(), style = SignalType.caption, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

/** An embed line drawn as its media; a tap outside the controls reveals the source to edit. */
@Composable
internal fun EmbedPreview(block: EmbedBlock, resolve: suspend (String) -> String?, reveal: () -> Unit, modifier: Modifier = Modifier) {
    val lookup by produceState<Pair<Boolean, String?>>(false to null, block.target) { value = true to resolve(block.target) }
    val (resolved, uri) = lookup
    val c = Signal.colors
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.divider, shape)
            .clickable(role = Role.Button, onClick = reveal)
            .testTag("live-preview-embed-${block.kind.name.lowercase()}"),
    ) {
        val target = uri
        when {
            target == null && resolved -> Row(Modifier.fillMaxSize().padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.BrokenImage, contentDescription = null, tint = c.faint, modifier = Modifier.size(18.dp))
                Text(voxFormat("Can't find %@", block.fileName), style = SignalType.caption, color = c.muted, maxLines = 2)
            }
            target == null -> Unit
            block.kind == EmbedKind.AUDIO -> AudioEmbed(target, block.fileName)
            block.kind == EmbedKind.IMAGE -> ImageEmbed(target, block.fileName)
            block.kind == EmbedKind.VIDEO -> VideoEmbed(target, block.fileName)
        }
    }
}

@Composable
private fun AudioEmbed(uri: String, fileName: String) {
    val c = Signal.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var player by remember(uri) { mutableStateOf<MediaPlayer?>(null) }
    var playing by remember(uri) { mutableStateOf(false) }
    var failed by remember(uri) { mutableStateOf(false) }
    var position by remember(uri) { mutableLongStateOf(0L) }
    var duration by remember(uri) { mutableLongStateOf(0L) }
    DisposableEffect(uri) { onDispose { player?.release(); player = null } }
    LaunchedEffect(uri) {
        // Duration up front, without holding a player open.
        duration = withContext(Dispatchers.IO) {
            runCatching {
                android.media.MediaMetadataRetriever().run {
                    try { setDataSource(context, Uri.parse(uri)); extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L } finally { release() }
                }
            }.getOrDefault(0L)
        }
    }
    LaunchedEffect(playing, player) {
        val active = player ?: return@LaunchedEffect
        while (playing) {
            position = runCatching { active.currentPosition.toLong() }.getOrDefault(position)
            delay(200)
        }
    }
    val label = voxString(if (playing) "Pause recording" else "Play recording")
    Row(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(c.accentSoft)
                .clickable(enabled = !failed, role = Role.Button) {
                    val current = player
                    when {
                        current != null && playing -> { current.pause(); playing = false }
                        current != null -> { current.start(); playing = true }
                        else -> scope.launch {
                            val prepared = withContext(Dispatchers.IO) {
                                runCatching { MediaPlayer().apply { setDataSource(context, Uri.parse(uri)); prepare() } }.getOrNull()
                            }
                            if (prepared == null) failed = true else {
                                prepared.setOnCompletionListener { playing = false; position = 0L; it.seekTo(0) }
                                prepared.duration.toLong().takeIf { it > 0 }?.let { duration = it }
                                prepared.start()
                                player = prepared
                                playing = true
                            }
                        }
                    }
                }
                .semantics { contentDescription = label }
                .testTag("live-preview-audio-play"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(if (playing) Icons.Outlined.Pause else Icons.Outlined.PlayArrow, contentDescription = null, tint = c.accentText, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(fileName, style = SignalType.monoCaption, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            LinearProgressIndicator(
                progress = { if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f },
                modifier = Modifier.fillMaxWidth().height(3.dp).clip(CircleShape),
                color = c.tint,
                trackColor = c.well,
                drawStopIndicator = {},
            )
        }
        Text(
            if (failed) voxString("Unavailable") else "${formatTranscriptDuration(position)} / ${formatTranscriptDuration(duration)}",
            style = SignalType.monoCaption,
            color = c.muted,
        )
    }
}

@Composable
private fun ImageEmbed(uri: String, fileName: String) {
    val context = LocalContext.current
    val c = Signal.colors
    val bitmap by produceState<ImageBitmap?>(null, uri) {
        value = withContext(Dispatchers.IO) { decodeSampled(context, uri, targetPx = 1_080) }
    }
    val image = bitmap
    if (image == null) {
        Box(Modifier.fillMaxSize().background(c.well))
    } else {
        Image(
            bitmap = image,
            contentDescription = fileName,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize().padding(4.dp).testTag("live-preview-image"),
        )
    }
}

private fun decodeSampled(context: android.content.Context, uri: String, targetPx: Int): ImageBitmap? = runCatching {
    val resolver = context.contentResolver
    val parsed = Uri.parse(uri)
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(parsed)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= targetPx || bounds.outHeight / (sample * 2) >= targetPx) sample *= 2
    val options = BitmapFactory.Options().apply { inSampleSize = sample }
    resolver.openInputStream(parsed)?.use { BitmapFactory.decodeStream(it, null, options) }?.asImageBitmap()
}.getOrNull()

@Composable
private fun VideoEmbed(uri: String, fileName: String) {
    val c = Signal.colors
    var playing by remember(uri) { mutableStateOf(false) }
    var view by remember(uri) { mutableStateOf<VideoView?>(null) }
    val label = voxString(if (playing) "Pause video" else "Play video")
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        AndroidView(
            factory = { context ->
                VideoView(context).apply {
                    setVideoURI(Uri.parse(uri))
                    setOnPreparedListener { it.isLooping = false; seekTo(1) }
                    setOnCompletionListener { playing = false }
                    view = this
                }
            },
            modifier = Modifier.fillMaxSize(),
            onRelease = { it.stopPlayback() },
        )
        Box(
            Modifier
                .fillMaxSize()
                .clickable(role = Role.Button) {
                    val video = view ?: return@clickable
                    if (video.isPlaying) { video.pause(); playing = false } else { video.start(); playing = true }
                }
                .semantics { contentDescription = "$label · $fileName" }
                .testTag("live-preview-video"),
            contentAlignment = Alignment.Center,
        ) {
            if (!playing) Box(Modifier.size(52.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
            }
        }
    }
}
