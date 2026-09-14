package md.vox.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Locale
import java.util.UUID

internal data class GeneratedCaptureAsset(
    val uri: Uri,
    val displayName: String,
    val mediaType: String,
    val includeInMarkdown: Boolean = true,
)

internal data class SketchPoint(val x: Float, val y: Float, val pressure: Float)
private data class SketchStroke(val points: androidx.compose.runtime.snapshots.SnapshotStateList<SketchPoint>)

@Composable
internal fun SketchDialog(
    onDismiss: () -> Unit,
    onSave: (List<GeneratedCaptureAsset>) -> Unit,
    onFailure: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val strokes = remember { mutableStateListOf<SketchStroke>() }
    var isSaving by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            modifier = Modifier.fillMaxWidth().height(520.dp),
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(voxString("Sketch"), style = MaterialTheme.typography.headlineSmall)
                Text(voxString("Draw with a finger or stylus. Vox.md keeps an editable source file with the PNG preview."),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(MaterialTheme.colorScheme.background, RoundedCornerShape(12.dp))
                        .pointerInput(Unit) {
                            awaitEachGesture {
                                val down = awaitFirstDown(requireUnconsumed = false)
                                val points = mutableStateListOf(
                                    SketchPoint(
                                        x = down.position.x / size.width.coerceAtLeast(1),
                                        y = down.position.y / size.height.coerceAtLeast(1),
                                        pressure = down.pressure.coerceIn(MIN_PRESSURE, 1f),
                                    ),
                                )
                                strokes += SketchStroke(points)
                                drag(down.id) { change ->
                                    points += SketchPoint(
                                        x = change.position.x / size.width.coerceAtLeast(1),
                                        y = change.position.y / size.height.coerceAtLeast(1),
                                        pressure = change.pressure.coerceIn(MIN_PRESSURE, 1f),
                                    )
                                    change.consume()
                                }
                            }
                        },
                ) {
                    strokes.forEach { stroke ->
                        val points = stroke.points
                        if (points.size == 1) {
                            val point = points.first()
                            drawCircle(
                                color = androidx.compose.ui.graphics.Color.Black,
                                radius = lineWidth(point.pressure) / 2f,
                                center = Offset(point.x * size.width, point.y * size.height),
                            )
                        } else {
                            points.zipWithNext().forEach { (from, to) ->
                                drawLine(
                                    color = androidx.compose.ui.graphics.Color.Black,
                                    start = Offset(from.x * size.width, from.y * size.height),
                                    end = Offset(to.x * size.width, to.y * size.height),
                                    strokeWidth = lineWidth((from.pressure + to.pressure) / 2f),
                                    cap = StrokeCap.Round,
                                )
                            }
                        }
                    }
                    drawIntoCanvas { }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { if (strokes.isNotEmpty()) strokes.removeAt(strokes.lastIndex) }, enabled = strokes.isNotEmpty() && !isSaving) {
                        Text(voxString("Undo"))
                    }
                    TextButton(onClick = { strokes.clear() }, enabled = strokes.isNotEmpty() && !isSaving) { Text(voxString("Clear")) }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onDismiss, enabled = !isSaving) { Text(voxString("Cancel")) }
                    Button(
                        onClick = {
                            isSaving = true
                            runCatching { createSketchAssets(context, strokes) }
                                .onSuccess(onSave)
                                .onFailure { onFailure() }
                            isSaving = false
                        },
                        enabled = strokes.isNotEmpty() && !isSaving,
                    ) { Text(voxString("Add Sketch")) }
                }
            }
        }
    }
}

private fun lineWidth(pressure: Float): Float = 3f + pressure.coerceIn(MIN_PRESSURE, 1f) * 7f

private fun createSketchAssets(context: Context, strokes: List<SketchStroke>): List<GeneratedCaptureAsset> {
    val bitmap = Bitmap.createBitmap(SKETCH_WIDTH, SKETCH_HEIGHT, Bitmap.Config.ARGB_8888)
    val canvas = AndroidCanvas(bitmap)
    canvas.drawColor(Color.WHITE)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    strokes.forEach { stroke ->
        if (stroke.points.size == 1) {
            val point = stroke.points.first()
            paint.style = Paint.Style.FILL
            canvas.drawCircle(point.x * SKETCH_WIDTH, point.y * SKETCH_HEIGHT, lineWidth(point.pressure), paint)
            paint.style = Paint.Style.STROKE
        } else {
            stroke.points.zipWithNext().forEach { (from, to) ->
                paint.strokeWidth = lineWidth((from.pressure + to.pressure) / 2f) * 2f
                canvas.drawLine(from.x * SKETCH_WIDTH, from.y * SKETCH_HEIGHT, to.x * SKETCH_WIDTH, to.y * SKETCH_HEIGHT, paint)
            }
        }
    }

    val token = UUID.randomUUID().toString().lowercase(Locale.ROOT)
    val pngFile = createCaptureImportFile(context, "$token-sketch.png") { output ->
        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) { "sketchEncode" }
    }
    bitmap.recycle()
    val source = encodeSketchDocument(strokes.map { it.points.toList() })
    val sourceFile = createCaptureImportFile(context, "$token-sketch.voxsketch.json") { output ->
        output.write(source)
    }
    return listOf(
        GeneratedCaptureAsset(captureImportUri(context, pngFile), "Sketch.png", "image/png"),
        GeneratedCaptureAsset(
            captureImportUri(context, sourceFile),
            "Sketch.voxsketch.json",
            "application/vnd.vox.sketch+json",
            includeInMarkdown = false,
        ),
    )
}

internal fun encodeSketchDocument(strokes: List<List<SketchPoint>>): ByteArray = buildString {
    append("{\"canvas\":{\"height\":$SKETCH_HEIGHT,\"width\":$SKETCH_WIDTH},\"strokes\":[")
    strokes.forEachIndexed { strokeIndex, stroke ->
        if (strokeIndex > 0) append(',')
        append('[')
        stroke.forEachIndexed { pointIndex, point ->
            if (pointIndex > 0) append(',')
            append(
                String.format(
                    Locale.US,
                    "{\"p\":%.4f,\"x\":%.6f,\"y\":%.6f}",
                    point.pressure.coerceIn(MIN_PRESSURE, 1f),
                    point.x.coerceIn(0f, 1f),
                    point.y.coerceIn(0f, 1f),
                ),
            )
        }
        append(']')
    }
    append("],\"version\":1}\n")
}.toByteArray(StandardCharsets.UTF_8)

internal fun createCaptureImportFile(
    context: Context,
    fileName: String,
    writer: (FileOutputStream) -> Unit = {},
): File {
    val directory = File(context.cacheDir, "capture-imports")
    check((directory.exists() || directory.mkdirs()) && directory.isDirectory) { "captureImportDirectory" }
    val staleBefore = System.currentTimeMillis() - 24L * 60 * 60 * 1_000
    directory.listFiles().orEmpty().filter { it.isFile && it.lastModified() < staleBefore }.forEach(File::delete)
    val temporary = File(directory, ".tmp-${UUID.randomUUID()}")
    FileOutputStream(temporary).use { output ->
        writer(output)
        output.flush()
        output.fd.sync()
    }
    val target = File(directory, fileName)
    Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    return target
}

internal fun captureImportUri(context: Context, file: File): Uri =
    FileProvider.getUriForFile(context, "${context.packageName}.files", file)

private const val SKETCH_WIDTH = 1080
private const val SKETCH_HEIGHT = 720
private const val MIN_PRESSURE = 0.15f
