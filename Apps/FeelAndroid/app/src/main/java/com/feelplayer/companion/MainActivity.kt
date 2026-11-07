// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.Manifest
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.ui.PlayerView
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

// Same rules as the Mac and iPhone apps: three grays. Orange is only ever something you feel.
// These follow light and dark mode. Text and lines are Ink at some opacity.
internal val Ink: Color @Composable get() = if (isSystemInDarkTheme()) Color.White else Color(0xFF121212)
/** Opposite of Ink, for text on an Ink fill. */
internal val Paper: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF121212) else Color.White
private val Bg: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF131211) else Color(0xFFF4F2F0)
internal val Panel: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF211F1E) else Color(0xFFFEFDFB)
internal val Secondary: Color @Composable get() = Ink.copy(alpha = 0.6f)
internal val Danger: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFFFF6661) else Color(0xFFCC211A)
internal val Accent = Color(0xFFFF6B33)
private val StrongEaseOut = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)

class MainActivity : ComponentActivity() {
    private lateinit var model: CompanionModel
    private lateinit var solo: SoloModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        model = CompanionModel(applicationContext)
        solo = SoloModel(applicationContext, model.haptics)
        handleLink(intent)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent {
            // Only someone who wants a Mac is asked for the network permission.
            var connectPage by remember { mutableStateOf(false) }
            val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { model.start() }
            val openConnect = {
                solo.pause()
                connectPage = true
                if (Build.VERSION.SDK_INT >= 33) ask.launch(Manifest.permission.NEARBY_WIFI_DEVICES) else model.start()
            }
            LaunchedEffect(model.editorName) {
                if (model.editorName != null) {
                    connectPage = false
                    solo.pause()
                }
            }
            BackHandler(connectPage) { connectPage = false }
            val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Ink, background = Bg, surface = Bg)
            else lightColorScheme(primary = Ink, background = Bg, surface = Bg)
            val editor = model.editorName
            val soloVideo = editor == null && !connectPage && solo.player != null
            val macVideo = editor != null && model.video.state is VideoState.Ready && model.video.player != null
            val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
            val immersive = landscape && (soloVideo || macVideo)
            val edgeToEdge = soloVideo || immersive
            val darkTheme = isSystemInDarkTheme()
            SideEffect {
                // Only a video turns sideways. The other pages are made for portrait.
                requestedOrientation =
                    if (soloVideo || macVideo) ActivityInfo.SCREEN_ORIENTATION_FULL_USER else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                val bars = WindowCompat.getInsetsController(window, window.decorView)
                bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (immersive) bars.hide(WindowInsetsCompat.Type.systemBars()) else bars.show(WindowInsetsCompat.Type.systemBars())
                val lightBars = !darkTheme && !edgeToEdge
                bars.isAppearanceLightStatusBars = lightBars
                bars.isAppearanceLightNavigationBars = lightBars
            }
            MaterialTheme(colorScheme = scheme) {
                val page = if (edgeToEdge) Modifier.fillMaxSize().background(Color.Black)
                else Modifier.fillMaxSize().background(Bg).statusBarsPadding().navigationBarsPadding()
                Box(page) {
                    when {
                        immersive && macVideo && editor != null -> MacVideoScreen(model, editor)
                        editor != null -> Connected(model, editor)
                        connectPage -> Join(model) { connectPage = false }
                        else -> SoloScreen(solo, model, openConnect)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleLink(intent)
    }

    private fun handleLink(intent: android.content.Intent?) {
        val data = intent?.data ?: return
        val link = JoinLink.parse(data.toString())
        if (link != null) model.connect(link) else if (intent.action == android.content.Intent.ACTION_VIEW) solo.open(data)
    }

    /** No sound and no vibration from an app the user left. */
    override fun onStop() {
        super.onStop()
        solo.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isFinishing) { model.stop(); model.video.release(); solo.close() }
    }
}

private val JoinSignature = listOf(
    HapticEvent(type = "tap", start = 0.0, intensity = 1.0),
    HapticEvent(type = "rumble", start = 0.25, duration = 0.5, intensity = 0.55, fadeIn = 0.2, fadeOut = 0.25),
    HapticEvent(type = "tickTrain", start = 0.85, intensity = 0.8, repetitionInterval = 0.09, repetitionCount = 4),
)

@Composable
private fun Join(model: CompanionModel, onClose: () -> Unit) {
    val context = LocalContext.current
    var picked by remember { mutableStateOf<Mac?>(null) }
    var code by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), horizontalArrangement = Arrangement.End) {
            RoundIcon(GlyphKind.Close, "Close", onClick = onClose)
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        ) {
            HapticBars(JoinSignature, Modifier.size(width = 112.dp, height = 32.dp))
            Text("Connect to a Mac", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Ink)
            val connecting = model.connecting
            if (connecting != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = Secondary, strokeWidth = 2.dp)
                    Text("Connecting to $connecting…", color = Secondary, fontSize = 15.sp)
                }
                WideButton("Cancel", Color.Transparent, Secondary) { model.cancelConnecting() }
            } else {
                Text(
                    "Open Feel Player or Feel Editor on your Mac, click Connect phone, then scan the QR code. The Mac sends its video here and plays haptics in sync.",
                    color = Secondary, fontSize = 15.sp, textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(4.dp))
                WideButton("Scan QR code", Ink, Paper) {
                    val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                    GmsBarcodeScanning.getClient(context, options).startScan()
                        .addOnSuccessListener { b ->
                            val link = JoinLink.parse(b.rawValue)
                            if (link != null) model.connect(link) else model.fail("This QR code is not from Feel.")
                        }
                        .addOnFailureListener { model.fail("Cannot scan: ${it.message}") }
                }
                if (model.macs.isEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(Modifier.size(12.dp), color = Secondary, strokeWidth = 1.5.dp)
                        Text("Looking for Macs on this Wi-Fi…", color = Secondary, fontSize = 13.sp)
                    }
                } else {
                    Text("Or pick a Mac and type its code", color = Secondary, fontSize = 13.sp, modifier = Modifier.fillMaxWidth())
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Panel)) {
                        model.macs.forEach { mac ->
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = 52.dp)
                                    .clickable(role = Role.RadioButton) {
                                        picked = if (picked == mac) null else mac
                                        code = ""
                                    }
                                    .padding(horizontal = 14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(mac.name, color = Ink, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                if (picked == mac) Glyph(GlyphKind.Check, "Selected", Modifier.size(16.dp))
                            }
                        }
                    }
                    if (picked != null) {
                        CodeField(code) { code = it }
                        val ready = code.length == 6
                        WideButton("Connect", if (ready) Ink else Panel, if (ready) Paper else Secondary, enabled = ready) {
                            picked?.let { model.connect(it, code) }
                        }
                    }
                }
            }
            model.error?.let { Text(it, color = Danger, fontSize = 13.sp, textAlign = TextAlign.Center) }
            model.notice?.let { Text(it, color = Secondary, fontSize = 13.sp, textAlign = TextAlign.Center) }
        }
        Text(
            "Both devices must be on the same Wi-Fi.",
            color = Secondary, fontSize = 13.sp, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        )
    }
}

/** Six boxes drawn over one text field, so paste and TalkBack work as normal. */
@Composable
private fun CodeField(code: String, onChange: (String) -> Unit) {
    BasicTextField(
        value = code,
        onValueChange = { onChange(it.filter(Char::isDigit).take(6)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        textStyle = TextStyle(color = Color.Transparent),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.Transparent),
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Code from your Mac" },
        decorationBox = { inner ->
            Box {
                Box(Modifier.alpha(0f)) { inner() }
                Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    repeat(6) { i ->
                        val current = i == minOf(code.length, 5)
                        Box(
                            Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(10.dp)).background(Panel)
                                .border(1.5.dp, if (current) Ink.copy(alpha = 0.7f) else Color.Transparent, RoundedCornerShape(10.dp)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(code.getOrNull(i)?.toString() ?: "", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Medium)
                        }
                        if (i == 2) Spacer(Modifier.width(6.dp))
                    }
                }
            }
        },
    )
}

@Composable
private fun Connected(model: CompanionModel, editor: String) {
    val context = LocalContext.current
    val debuggable = remember { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(if (model.haptics.supportsHaptics) Accent else Danger))
            Text(editor, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            model.rtt?.let { Text("${(it * 1000).toInt()} ms", color = Secondary, fontSize = 13.sp, style = TabularNumbers) }
            Spacer(Modifier.weight(1f))
            RoundIcon(GlyphKind.Close, "Disconnect") { model.disconnect() }
        }
        VideoArea(model)
        if (model.duration > 0) Transport(model)
        FeelMeter(model, Modifier.weight(1f).fillMaxWidth())
        model.notice?.let { Text(it, color = Danger, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
        if (debuggable && model.debugLine.isNotEmpty()) {
            Text(model.debugLine, color = Secondary, fontSize = 11.sp, fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        WideButton("Test haptic", Panel, Ink) { model.testHaptic() }
    }
}

/** Landscape with a video from the Mac: the video fills the screen. */
@Composable
private fun MacVideoScreen(model: CompanionModel, editor: String) {
    val player = model.video.player ?: return
    VideoScreen(
        model,
        surface = {
            AndroidView(
                factory = { ctx -> PlayerView(ctx).apply { useController = false; this.player = player } },
                update = { it.player = player },
                modifier = Modifier.fillMaxSize(),
            )
        },
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(if (model.haptics.supportsHaptics) Accent else Danger))
        Text(editor, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        model.notice?.let { Text(it, color = VideoDanger, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        val on = model.video.soundOn
        RoundIcon(if (on) GlyphKind.SoundOn else GlyphKind.SoundOff, if (on) "Turn sound off" else "Turn sound on", overVideo = true) {
            model.video.soundOn = !on
        }
        RoundIcon(GlyphKind.Close, "Disconnect", overVideo = true) { model.disconnect() }
    }
}

internal val TabularNumbers = TextStyle(fontFeatureSettings = "tnum")

/** Time, with a glow that hits as hard as the haptic does. Reads time here only, so the page stays still. */
@Composable
private fun FeelMeter(model: CompanionModel, modifier: Modifier) {
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    Box(modifier, contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(200.dp)
                .graphicsLayer {
                    val level = model.hapticLevel.toFloat()
                    alpha = level * 0.7f
                    val s = if (reduceMotion) 1f else 0.75f + 0.5f * level
                    scaleX = s
                    scaleY = s
                }
                .blur(44.dp)
                .clip(CircleShape)
                .background(Accent),
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                timecode(model.mediaTime),
                fontSize = 44.sp, fontWeight = FontWeight.Medium, color = Ink,
                style = TabularNumbers, maxLines = 1,
            )
            Text(if (model.eventCount == 1) "1 haptic" else "${model.eventCount} haptics", color = Secondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun VideoArea(model: CompanionModel) {
    val shape = RoundedCornerShape(14.dp)
    when (val s = model.video.state) {
        is VideoState.Ready -> {
            val player = model.video.player
            if (player != null) Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(Color.Black)) {
                AndroidView(
                    factory = { ctx -> PlayerView(ctx).apply { useController = false; this.player = player } },
                    update = { it.player = player },
                    modifier = Modifier.fillMaxSize(),
                )
                Box(Modifier.align(Alignment.BottomEnd).padding(2.dp)) {
                    val on = model.video.soundOn
                    RoundIcon(if (on) GlyphKind.SoundOn else GlyphKind.SoundOff, if (on) "Turn sound off" else "Turn sound on", overVideo = true) {
                        model.video.soundOn = !on
                    }
                }
            }
        }
        is VideoState.Receiving -> Column(
            Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(Panel),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        ) {
            Text("Getting video from Mac", color = Ink, fontSize = 15.sp)
            LinearProgressIndicator(
                progress = { s.progress.toFloat() },
                color = Ink, trackColor = Ink.copy(alpha = 0.14f), drawStopIndicator = {},
                modifier = Modifier.width(200.dp),
            )
            Text("${(s.progress * 100).toInt()}%", color = Secondary, fontSize = 13.sp, style = TabularNumbers)
        }
        is VideoState.Failed -> Text(s.reason, color = Danger, fontSize = 13.sp)
        VideoState.None -> {}
    }
}

@Composable
private fun Transport(model: CompanionModel) {
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableStateOf(0f) }
    var lastSent by remember { mutableStateOf(0L) }
    val receiving = model.video.state is VideoState.Receiving
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val source = remember { MutableInteractionSource() }
        Box(
            Modifier.pressScale(source).size(48.dp).alpha(if (receiving) 0.4f else 1f).clip(CircleShape).background(Ink)
                .clickable(source, LocalIndication.current, enabled = !receiving, role = Role.Button) { model.togglePlay() },
            contentAlignment = Alignment.Center,
        ) {
            Glyph(
                if (model.isPlaying) GlyphKind.Pause else GlyphKind.Play,
                if (model.isPlaying) "Pause" else "Play",
                Modifier.size(20.dp),
                Paper,
            )
        }
        Slider(
            value = if (dragging) dragValue else model.mediaTime.toFloat(),
            onValueChange = {
                dragging = true
                dragValue = it
                val now = System.currentTimeMillis()
                if (now - lastSent > 60) { lastSent = now; model.seek(it.toDouble(), final = false) }
            },
            onValueChangeFinished = {
                model.seek(dragValue.toDouble(), final = true)
                dragging = false
            },
            valueRange = 0f..maxOf(model.duration.toFloat(), 0.1f),
            colors = SliderDefaults.colors(
                thumbColor = Ink,
                activeTrackColor = Ink,
                inactiveTrackColor = Ink.copy(alpha = 0.14f),
            ),
            modifier = Modifier.weight(1f).semantics { contentDescription = "Position" },
        )
    }
}

/** Scale down while pressed. Gives feedback at the moment of touch. */
@Composable
internal fun Modifier.pressScale(source: MutableInteractionSource): Modifier {
    val pressed by source.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) 0.97f else 1f, tween(140, easing = StrongEaseOut), label = "press")
    return scale(s)
}

@Composable
internal fun WideButton(label: String, fill: Color, text: Color, enabled: Boolean = true, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    Box(
        Modifier.pressScale(source).fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(14.dp)).background(fill)
            .clickable(source, LocalIndication.current, enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(label, color = text, fontSize = 16.sp, fontWeight = FontWeight.Medium) }
}

/** 32 dp circle in a 48 dp touch target. */
@Composable
internal fun RoundIcon(kind: GlyphKind, label: String, overVideo: Boolean = false, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    Box(
        Modifier.pressScale(source).size(48.dp).clickable(source, null, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        val fill = if (overVideo) Color.Black.copy(alpha = 0.55f) else Ink.copy(alpha = 0.12f)
        Box(Modifier.size(32.dp).clip(CircleShape).background(fill), contentAlignment = Alignment.Center) {
            Glyph(kind, label, Modifier.size(14.dp), if (overVideo) Color.White else Ink)
        }
    }
}

internal enum class GlyphKind { Play, Pause, Close, Check, SoundOn, SoundOff, More, Back, Forward }

/** Drawn icons. Text symbols differ per font and look wrong next to the rest of the page. */
@Composable
internal fun Glyph(kind: GlyphKind, label: String, modifier: Modifier, tint: Color = Ink) {
    Canvas(modifier.semantics { contentDescription = label }) {
        val w = size.width
        val h = size.height
        val line = w * 0.13f
        fun stroke(x1: Float, y1: Float, x2: Float, y2: Float) =
            drawLine(tint, Offset(x1 * w, y1 * h), Offset(x2 * w, y2 * h), line, StrokeCap.Round)
        when (kind) {
            GlyphKind.Play -> drawPath(
                Path().apply {
                    moveTo(0.22f * w, 0.1f * h)
                    lineTo(0.9f * w, 0.5f * h)
                    lineTo(0.22f * w, 0.9f * h)
                    close()
                },
                tint,
            )
            GlyphKind.Back, GlyphKind.Forward -> for (x in listOf(0.04f, 0.5f)) {
                val near = if (kind == GlyphKind.Forward) x else 1f - x
                val far = if (kind == GlyphKind.Forward) x + 0.46f else 1f - x - 0.46f
                drawPath(
                    Path().apply {
                        moveTo(near * w, 0.16f * h)
                        lineTo(far * w, 0.5f * h)
                        lineTo(near * w, 0.84f * h)
                        close()
                    },
                    tint,
                )
            }
            GlyphKind.Pause -> for (x in listOf(0.18f, 0.6f)) {
                drawRoundRect(tint, Offset(x * w, 0.1f * h), Size(0.22f * w, 0.8f * h), CornerRadius(0.05f * w))
            }
            GlyphKind.More -> for (x in listOf(0.14f, 0.5f, 0.86f)) {
                drawCircle(tint, line * 0.75f, Offset(x * w, 0.5f * h))
            }
            GlyphKind.Close -> {
                stroke(0.14f, 0.14f, 0.86f, 0.86f)
                stroke(0.86f, 0.14f, 0.14f, 0.86f)
            }
            GlyphKind.Check -> {
                stroke(0.14f, 0.54f, 0.4f, 0.82f)
                stroke(0.4f, 0.82f, 0.88f, 0.2f)
            }
            GlyphKind.SoundOn, GlyphKind.SoundOff -> {
                drawPath(
                    Path().apply {
                        moveTo(0.05f * w, 0.36f * h)
                        lineTo(0.24f * w, 0.36f * h)
                        lineTo(0.5f * w, 0.12f * h)
                        lineTo(0.5f * w, 0.88f * h)
                        lineTo(0.24f * w, 0.64f * h)
                        lineTo(0.05f * w, 0.64f * h)
                        close()
                    },
                    tint,
                )
                if (kind == GlyphKind.SoundOn) {
                    stroke(0.68f, 0.34f, 0.68f, 0.66f)
                    stroke(0.88f, 0.2f, 0.88f, 0.8f)
                } else {
                    stroke(0.66f, 0.36f, 0.94f, 0.64f)
                    stroke(0.94f, 0.36f, 0.66f, 0.64f)
                }
            }
        }
    }
}

/** What events feel like over time, drawn as bars. */
@Composable
private fun HapticBars(events: List<HapticEvent>, modifier: Modifier) {
    Canvas(modifier) {
        val span = maxOf(events.maxOf { it.start + maxOf(it.duration, (it.repetitionCount - 1) * it.repetitionInterval + 0.05) }, 0.3) + 0.08
        val pitch = 3.dp.toPx()
        val bar = 2.dp.toPx()
        var x = 0f
        while (x < size.width) {
            val t = (x / size.width) * span
            val level = events.maxOf { it.level(t) }.toFloat()
            if (level > 0.02f) {
                val h = maxOf(level * size.height, bar)
                drawRoundRect(Accent, Offset(x, (size.height - h) / 2), Size(bar, h), CornerRadius(bar / 2))
            }
            x += pitch
        }
    }
}

internal fun timecode(t: Double): String {
    val total = maxOf(t, 0.0)
    val m = (total / 60).toInt()
    val s = total - m * 60
    return "%02d:%06.3f".format(m, s)
}
