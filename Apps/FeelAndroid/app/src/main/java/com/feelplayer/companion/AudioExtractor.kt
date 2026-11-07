// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/** Decodes the sound of a video to 16 kHz mono and measures its spectrum. Runs on the calling thread. */
object AudioExtractor {
    private const val TIMEOUT_US = 10_000L

    /** null when the file has no sound, it cannot be decoded, or `cancelled` turned true. */
    fun extract(context: Context, uri: Uri, cancelled: () -> Boolean): AudioSpectrum? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var speech: SpeechDetector? = null
        try {
            // A descriptor works for every kind of URI. The media service may not be able to open the path itself.
            val source = context.contentResolver.openAssetFileDescriptor(uri, "r") ?: return null
            source.use { extractor.setDataSource(it) }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME) ?: return null)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()

            val analyzer = SpectrumAnalyzer()
            val detector = SpeechDetector(context).also { speech = it }
            val meter = PeakMeter()
            val sink: (FloatArray, Int) -> Unit = { samples, n ->
                analyzer.push(samples, n)
                meter.push(samples, n)
                detector.push(samples, n)
            }
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var resampler: Resampler? = null
            var mono = FloatArray(8192)
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
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = decoder.outputFormat
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (out.containsKey(MediaFormat.KEY_PCM_ENCODING)) encoding = out.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    resampler = null
                } else if (index >= 0) {
                    if (info.size > 0) {
                        val output = decoder.getOutputBuffer(index) ?: return null
                        output.position(info.offset).limit(info.offset + info.size)
                        val frames = info.size / (channels * if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2)
                        if (frames > mono.size) mono = FloatArray(frames)
                        downmix(output.slice().order(ByteOrder.nativeOrder()), encoding, channels, frames, mono)
                        val r = resampler ?: Resampler(rate).also { resampler = it }
                        r.push(mono, frames, sink)
                    }
                    decoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
            resampler?.finish(sink)
            val result = analyzer.result()
            return if (result.count > 0) result.withSpeech(detector.finish()).withEnvelope(meter.peaks()) else null
        } catch (e: Exception) {
            Log.w("Feel", "Cannot read audio: ${e.message}")
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
            speech?.close()
        }
    }

    /** Peak of every 10 ms at 16 kHz. */
    private class PeakMeter {
        private var peaks = FloatArray(6000)
        private var count = 0
        private var inBucket = 0
        private var current = 0f

        fun push(samples: FloatArray, n: Int) {
            for (i in 0 until n) {
                current = maxOf(current, abs(samples[i]))
                if (++inBucket == 160) {
                    if (count == peaks.size) peaks = peaks.copyOf(count * 2)
                    peaks[count++] = minOf(current, 1f)
                    inBucket = 0
                    current = 0f
                }
            }
        }

        fun peaks(): FloatArray = peaks.copyOf(count)
    }

    private fun downmix(data: ByteBuffer, encoding: Int, channels: Int, frames: Int, out: FloatArray) {
        if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val f = data.asFloatBuffer()
            for (i in 0 until frames) {
                var sum = 0f
                for (c in 0 until channels) sum += f.get(i * channels + c)
                out[i] = sum / channels
            }
        } else {
            val s = data.asShortBuffer()
            for (i in 0 until frames) {
                var sum = 0f
                for (c in 0 until channels) sum += s.get(i * channels + c) / 32768f
                out[i] = sum / channels
            }
        }
    }
}
