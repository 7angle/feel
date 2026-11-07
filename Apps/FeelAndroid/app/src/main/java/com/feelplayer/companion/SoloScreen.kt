// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.net.Uri
import android.view.TextureView
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.delay

/** What the video controls need from a model. */
interface PlayerTransport {
    val isPlaying: Boolean
    val mediaTime: Double
    val duration: Double
    val hapticGraph: List<Double>
    fun togglePlay()
    fun seek(to: Double, final: Boolean)
}

/** How much haptic there is along a video, for the graph over a timeline. */
object HapticGraph {
    /** One value per slot, from 0 to 1, smoothed, and falling to 0 at both ends. Empty if there is nothing to show. */
    fun levels(events: List<HapticEvent>, duration: Double, count: Int = 96): List<Double> {
        if (duration <= 0 || count <= 0 || events.isEmpty()) return emptyList()
        var slots = DoubleArray(count)
        fun slot(t: Double) = (t / duration * count).toInt().coerceIn(0, count - 1)
        for (e in events) {
            if (e.start >= duration) continue
            val end = e.start + maxOf(e.duration, (e.repetitionCount - 1) * e.repetitionInterval + 0.05)
            for (i in slot(e.start)..slot(end)) slots[i] += e.intensity
        }
        repeat(3) {
            val previous = slots
            slots = DoubleArray(count) { i ->
                val from = maxOf(i - 3, 0)
                val to = minOf(i + 3, count - 1)
                (from..to).sumOf { previous[it] } / (to - from + 1)
            }
        }
        val top = slots.max()
        if (top <= 0) return emptyList()
        return slots.mapIndexed { i, v ->
            val edge = minOf(minOf(i, count - 1 - i) / 4.0, 1.0)
            v / top * edge * edge * (3 - 2 * edge)
        }
    }
}

/** Danger on the dark video screen, in light mode too. */
internal val VideoDanger = Color(0xFFFF6661)

/** Home of the app: a video player that makes you feel the video. Connecting to a Mac is an option. */
@Composable
fun SoloScreen(model: SoloModel, connect: CompanionModel, onConnect: () -> Unit) {
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) model.open(uri)
    }
    val openFile = {
        // No sound or haptics behind the file picker. onStop comes too late, or not at all in split screen.
        model.pause()
        pick.launch(arrayOf("video/*", "application/json", "application/octet-stream"))
    }
    val player = model.player
    if (player != null) {
        SoloVideo(model, player, connect, openFile, onConnect)
    } else {
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Feel", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Ink, modifier = Modifier.weight(1f))
                ConnectingStatus(connect, onConnect, Secondary)
                var menu by remember { mutableStateOf(false) }
                SoloMenu(model, menu, { menu = it }, openFile, onConnect, overVideo = false)
            }
            Empty(Modifier.weight(1f).fillMaxWidth(), openFile, onConnect)
            Notices(model, connect, Danger, TextAlign.Center)
        }
    }
}

@Composable
private fun SoloVideo(model: SoloModel, player: ExoPlayer, connect: CompanionModel, openFile: () -> Unit, onConnect: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    VideoScreen(
        model,
        preparing = model.isMaking,
        hold = menu,
        surface = {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Box(Modifier.aspectRatio(model.aspect)) {
                    // A TextureView follows every size change. A SurfaceView keeps a stale size.
                    key(player) {
                        AndroidView(
                            factory = { ctx -> TextureView(ctx).also { player.setVideoTextureView(it) } },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
        },
        notices = { Notices(model, connect, VideoDanger, TextAlign.Start) },
    ) {
        Text(model.name, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        ConnectingStatus(connect, onConnect, Color.White.copy(alpha = 0.6f))
        val on = model.soundOn
        RoundIcon(if (on) GlyphKind.SoundOn else GlyphKind.SoundOff, if (on) "Turn sound off" else "Turn sound on", overVideo = true) {
            model.soundOn = !on
        }
        SoloMenu(model, menu, { menu = it }, openFile, onConnect, overVideo = true)
    }
}

@Composable
private fun ConnectingStatus(connect: CompanionModel, onConnect: () -> Unit, color: Color) {
    connect.connecting?.let { mac ->
        Row(
            Modifier.clickable(role = Role.Button, onClick = onConnect),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            CircularProgressIndicator(Modifier.size(12.dp), color = color, strokeWidth = 1.5.dp)
            Text(mac, color = color, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun SoloMenu(
    model: SoloModel,
    open: Boolean,
    onOpen: (Boolean) -> Unit,
    openFile: () -> Unit,
    onConnect: () -> Unit,
    overVideo: Boolean,
) {
    @Composable
    fun Item(label: String, color: Color = Ink, action: () -> Unit) =
        DropdownMenuItem(text = { Text(label, color = color) }, onClick = { onOpen(false); action() })
    var about by remember { mutableStateOf(false) }
    if (about) AboutDialog { about = false }
    Box {
        RoundIcon(GlyphKind.More, "More", overVideo = overVideo) { onOpen(true) }
        DropdownMenu(expanded = open, onDismissRequest = { onOpen(false) }, containerColor = Panel) {
            Item("Open video", action = openFile)
            Item("Connect to Mac", action = onConnect)
            Item("About") { about = true }
            if (model.player != null) {
                if (model.events.isNotEmpty()) {
                    Item("Test haptics") { model.testHaptic() }
                    Item("Remove haptics") { model.clearHaptics() }
                } else if (!model.isMaking) {
                    Item("Make haptics") { model.makeFromSound() }
                }
                Item("Close video", Danger) { model.close() }
            }
        }
    }
}

@Composable
private fun AboutDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        title = { Text("About Feel") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Privacy", fontWeight = FontWeight.SemiBold)
                Text("Feel does not collect your data. It has no account, no analytics, no ads, and no tracking.")
                Text("Videos stay on your device. Feel makes haptics from the sound on your device.")
                Text("The camera scans the QR code on your Mac. The image is not saved or sent.")
                Text("The local network link goes only to your own Mac. It is encrypted.")
                Text("License", fontWeight = FontWeight.SemiBold)
                Text("Copyright © 2026 7 Angle.")
                Text("Feel is free software under the GNU AGPL 3.0 or later.")
                Text("The AGPL does not apply to the Feel names and icons. All rights reserved.")
                AboutLink("View the source code on GitHub", "https://github.com/mcnaveen/feel")
                AboutLink("Read the license", "https://github.com/mcnaveen/feel/blob/main/LICENSE")
                Text("Open-source licenses", fontWeight = FontWeight.SemiBold)
                Text(
                    "AndroidX and Jetpack Compose, Media3, LiteRT: Apache License 2.0, The Android Open Source Project and Google.\n" +
                        "YAMNet sound model: Apache License 2.0, Google.\n" +
                        "Bouncy Castle: MIT License, The Legion of the Bouncy Castle Inc.\n" +
                        "Google code scanner: Google Play services terms.",
                )
                Text("Version", fontWeight = FontWeight.SemiBold)
                val context = LocalContext.current
                Text(context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty())
            }
        },
    )
}

@Composable
private fun AboutLink(label: String, url: String) {
    val style = TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline))
    Text(buildAnnotatedString { withLink(LinkAnnotation.Url(url, style)) { append(label) } })
}

@Composable
private fun Empty(modifier: Modifier, openFile: () -> Unit, onConnect: () -> Unit) {
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
    ) {
        Text("Feel your videos", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Ink)
        Text(
            "Open a video. Feel makes haptics from its sound as it opens, or plays a haptics file from the Feel editor.",
            color = Secondary, fontSize = 15.sp, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.size(4.dp))
        WideButton("Open video", Ink, Paper, onClick = openFile)
        Box(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onConnect),
            contentAlignment = Alignment.Center,
        ) { Text("Connect to Mac", color = Secondary, fontSize = 15.sp) }
    }
}

/** Only the video, edge to edge. Tap to show the controls. They hide again while it plays. */
@Composable
internal fun VideoScreen(
    model: PlayerTransport,
    preparing: Boolean = false,
    hold: Boolean = false,
    surface: @Composable () -> Unit,
    notices: @Composable () -> Unit = {},
    top: @Composable RowScope.() -> Unit,
) {
    val context = LocalContext.current
    val screenReader = remember {
        (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager).isTouchExplorationEnabled
    }
    var shown by remember { mutableStateOf(true) }
    var scrubbing by remember { mutableStateOf(false) }
    var skips by remember { mutableIntStateOf(0) }
    val playing = model.isPlaying
    LaunchedEffect(shown, playing, scrubbing, hold, skips) {
        if (shown && playing && !scrubbing && !hold) {
            delay(3000)
            shown = false
        }
    }
    val visible = shown || !playing || scrubbing || hold || preparing || screenReader
    val ease = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        surface()
        Box(
            Modifier.matchParentSize().clickable(remember { MutableInteractionSource() }, null, onClickLabel = "Show or hide controls") {
                shown = if (playing) !shown else true
            },
        )
        AnimatedVisibility(preparing, enter = fadeIn(tween(200, easing = ease)), exit = fadeOut(tween(200, easing = ease))) {
            Column(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            ) {
                CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                Text("Preparing to play", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
        }
        AnimatedVisibility(visible, enter = fadeIn(tween(200, easing = ease)), exit = fadeOut(tween(200, easing = ease))) {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        0f to Color.Black.copy(alpha = 0.6f),
                        0.3f to Color.Black.copy(alpha = 0.25f),
                        0.7f to Color.Black.copy(alpha = 0.25f),
                        1f to Color.Black.copy(alpha = 0.6f),
                    ),
                ),
            ) {
                if (!preparing) {
                    CenterControls(model, Modifier.align(Alignment.Center)) { skips++ }
                }
                Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal = 12.dp, vertical = 4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = top)
                    notices()
                    Spacer(Modifier.weight(1f))
                    if (!preparing) PositionSlider(model) { scrubbing = it }
                }
            }
        }
    }
}

/** Skip back, play or pause, skip forward. */
@Composable
private fun CenterControls(model: PlayerTransport, modifier: Modifier, onSkip: () -> Unit) {
    @Composable
    fun Skip(kind: GlyphKind, label: String, by: Double) {
        Box(
            Modifier.size(56.dp).clip(CircleShape).clickable(role = Role.Button) {
                onSkip()
                model.seek((model.mediaTime + by).coerceIn(0.0, model.duration), final = true)
            },
            contentAlignment = Alignment.Center,
        ) { Glyph(kind, label, Modifier.size(24.dp), Color.White) }
    }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(32.dp)) {
        Skip(GlyphKind.Back, "Back 10 seconds", -10.0)
        val source = remember { MutableInteractionSource() }
        Box(
            Modifier.pressScale(source).size(72.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f))
                .clickable(source, LocalIndication.current, role = Role.Button) { model.togglePlay() },
            contentAlignment = Alignment.Center,
        ) {
            Glyph(
                if (model.isPlaying) GlyphKind.Pause else GlyphKind.Play,
                if (model.isPlaying) "Pause" else "Play",
                Modifier.size(28.dp),
                Color.White,
            )
        }
        Skip(GlyphKind.Forward, "Forward 10 seconds", 10.0)
    }
}

/** Own composable: it reads the time on every tick, so the rest of the screen stays still. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PositionSlider(model: PlayerTransport, onScrub: (Boolean) -> Unit) {
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableFloatStateOf(0f) }
    var lastSent by remember { mutableLongStateOf(0L) }
    val dim = Color.White.copy(alpha = 0.6f)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(clock(if (dragging) dragValue.toDouble() else model.mediaTime), color = dim, fontSize = 13.sp, style = TabularNumbers)
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
        Slider(
            value = if (dragging) dragValue else model.mediaTime.toFloat(),
            onValueChange = {
                if (!dragging) onScrub(true)
                dragging = true
                dragValue = it
                val now = System.currentTimeMillis()
                if (now - lastSent > 60) { lastSent = now; model.seek(it.toDouble(), final = false) }
            },
            onValueChangeFinished = {
                model.seek(dragValue.toDouble(), final = true)
                dragging = false
                onScrub(false)
            },
            valueRange = 0f..maxOf(model.duration.toFloat(), 0.1f),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Position" },
            thumb = { Box(Modifier.size(14.dp).clip(CircleShape).background(Color.White)) },
            track = { state ->
                SliderDefaults.Track(
                    state,
                    Modifier.height(4.dp),
                    colors = SliderDefaults.colors(activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.24f)),
                    drawStopIndicator = null,
                    thumbTrackGapSize = 0.dp,
                    trackInsideCornerSize = 2.dp,
                )
            },
        )
        val graph = model.hapticGraph
        if (graph.isNotEmpty()) {
            val time = if (dragging) dragValue.toDouble() else model.mediaTime
            // The thumb stops 7 dp from each end of the track.
            HapticGraphLine(graph, time / maxOf(model.duration, 0.1), Modifier.fillMaxWidth().padding(horizontal = 7.dp).height(28.dp).offset(y = (-19).dp))
        }
        }
        Text(clock(model.duration), color = dim, fontSize = 13.sp, style = TabularNumbers)
    }
}

/** Where the haptics are, over the timeline. Orange up to the playhead, because you felt it. */
@Composable
private fun HapticGraphLine(levels: List<Double>, progress: Double, modifier: Modifier) {
    Canvas(modifier) {
        val step = size.width / maxOf(levels.size - 1, 1)
        fun y(i: Int) = size.height * (1 - levels[i].toFloat())
        // Each level pulls the line toward it, so the line has no corners.
        val line = Path().apply {
            moveTo(0f, y(0))
            for (i in 1 until levels.size) {
                quadraticTo((i - 1) * step, y(i - 1), (i - 0.5f) * step, (y(i - 1) + y(i)) / 2)
            }
            lineTo(size.width, y(levels.size - 1))
        }
        val area = Path().apply {
            addPath(line)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        val split = size.width * progress.coerceIn(0.0, 1.0).toFloat()
        val stroke = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round)
        fun fade(color: Color, top: Float) = Brush.verticalGradient(listOf(color.copy(alpha = top), color.copy(alpha = 0f)), 0f, size.height)
        clipRect(right = split) {
            drawPath(area, fade(Accent, 0.7f))
            drawPath(line, Accent, style = stroke)
        }
        clipRect(left = split) {
            drawPath(area, fade(Color.White, 0.4f))
            drawPath(line, Color.White.copy(alpha = 0.9f), style = stroke)
        }
    }
}

@Composable
private fun Notices(model: SoloModel, connect: CompanionModel, color: Color, align: TextAlign) {
    val messages = listOfNotNull(
        model.warning,
        model.message,
        connect.error,
        if (connect.haptics.supportsHaptics) null else "This device has no vibration motor.",
    )
    messages.forEach {
        Text(it, color = color, fontSize = 13.sp, textAlign = align, modifier = Modifier.fillMaxWidth())
    }
}

/** For a video player: m:ss, or h:mm:ss for a long video. */
private fun clock(t: Double): String {
    val total = maxOf(t, 0.0).toInt()
    val h = total / 3600
    val m = total % 3600 / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
