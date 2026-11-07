// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.graphics.ImageFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log

/** Decodes the picture of a video and measures small frames. Runs on the calling thread. */
object FrameExtractor {
    private const val WIDTH = 160
    private const val HEIGHT = 90
    /** Samples per second. */
    private const val SAMPLE_RATE = 15.0
    /** Source pixels read per side of one small pixel. */
    private const val READS = 4
    private const val TIMEOUT_US = 10_000L

    /** null when the picture cannot be decoded or `cancelled` turned true. */
    fun extract(context: Context, uri: Uri, cancelled: () -> Boolean): List<FrameFeature>? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            val source = context.contentResolver.openAssetFileDescriptor(uri, "r") ?: return null
            source.use { extractor.setDataSource(it) }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME) ?: return null)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()

            val features = ArrayList<FrameFeature>()
            var previous: MeasuredFrame? = null
            var lastT = Double.NEGATIVE_INFINITY
            val step = 1 / SAMPLE_RATE
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone) {
                if (cancelled()) return null
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val input = decoder.getInputBuffer(index) ?: return null
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index >= 0) {
                    val t = info.presentationTimeUs / 1e6
                    if (info.size > 0 && t - lastT >= step - 0.001) {
                        val fullRange = decoder.outputFormat.let {
                            it.containsKey(MediaFormat.KEY_COLOR_RANGE) &&
                                it.getInteger(MediaFormat.KEY_COLOR_RANGE) == MediaFormat.COLOR_RANGE_FULL
                        }
                        val luma = decoder.getOutputImage(index)?.use { readLuma(it, fullRange) } ?: return null
                        val frame = MeasuredFrame(luma, WIDTH, HEIGHT)
                        features.add(frame.feature(t, previous))
                        previous = frame
                        lastT = t
                    }
                    decoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
            return features
        } catch (e: Exception) {
            Log.w("Feel", "Cannot read picture: ${e.message}")
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    /** Small luma frame, 0..255. null when the decoder gives a layout other than 8-bit samples. */
    private fun readLuma(image: Image, fullRange: Boolean): IntArray? {
        val plane = image.planes.firstOrNull() ?: return null
        if (image.format != ImageFormat.YUV_420_888 || plane.pixelStride != 1) return null
        val crop = image.cropRect
        val data = plane.buffer
        val xs = IntArray(WIDTH * READS) { crop.left + it * crop.width() / (WIDTH * READS) }
        val ys = IntArray(HEIGHT * READS) { crop.top + it * crop.height() / (HEIGHT * READS) }
        val out = IntArray(WIDTH * HEIGHT)
        for (y in 0 until HEIGHT) {
            for (x in 0 until WIDTH) {
                var sum = 0
                for (r in 0 until READS) {
                    val row = ys[y * READS + r] * plane.rowStride
                    for (c in 0 until READS) sum += data.get(row + xs[x * READS + c]).toInt() and 0xff
                }
                val y8 = sum / (READS * READS)
                out[y * WIDTH + x] = if (fullRange) y8 else ((y8 - 16) * 255 / 219).coerceIn(0, 255)
            }
        }
        return out
    }
}
