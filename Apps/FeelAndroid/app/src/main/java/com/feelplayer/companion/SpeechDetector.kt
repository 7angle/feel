// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Finds the time ranges that hold speech with the YAMNet sound classifier. Runs on the device.
 * Android has no built-in classifier like Apple's, so the app ships this model.
 * When the model cannot run, the result is empty and no audio is treated as speech.
 */
class SpeechDetector(context: Context) : AutoCloseable {
    private var model: Interpreter? = null
    private val input = ByteBuffer.allocateDirect(WINDOW * Float.SIZE_BYTES).order(ByteOrder.nativeOrder())
    private var output: ByteBuffer = ByteBuffer.allocateDirect(0)
    private val pending = FloatArray(WINDOW * 2)
    private var pendingCount = 0
    private var position = 0L
    private val found = ArrayList<ClosedFloatingPointRange<Double>>()

    init {
        try {
            val bytes = context.assets.open(MODEL).use { it.readBytes() }
            val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
            buffer.put(bytes).rewind()
            val m = Interpreter(buffer, Interpreter.Options().setNumThreads(2))
            output = ByteBuffer.allocateDirect(m.getOutputTensor(0).numBytes()).order(ByteOrder.nativeOrder())
            model = m
        } catch (e: Exception) {
            unavailable(e)
        } catch (e: LinkageError) {
            unavailable(e)
        }
    }

    private fun unavailable(e: Throwable) {
        Log.w("Feel", "Speech detection is off: ${e.message}")
        close()
    }

    /** Mono samples at 16 kHz. */
    fun push(samples: FloatArray, count: Int) {
        if (model == null) return
        var from = 0
        while (from < count) {
            val n = minOf(count - from, pending.size - pendingCount)
            samples.copyInto(pending, pendingCount, from, from + n)
            pendingCount += n
            from += n
            drain()
        }
    }

    private fun drain() {
        while (pendingCount >= WINDOW) {
            classify()
            pending.copyInto(pending, 0, HOP, pendingCount)
            pendingCount -= HOP
            position += HOP
        }
    }

    private fun classify() {
        val m = model ?: return
        try {
            input.clear()
            input.asFloatBuffer().put(pending, 0, WINDOW)
            output.clear()
            m.run(input, output)
            val confidence = output.getFloat(SPEECH_CLASS * Float.SIZE_BYTES)
            if (confidence >= MIN_CONFIDENCE) {
                val start = position.toDouble() / SpectrumAnalyzer.SAMPLE_RATE
                found.add(start..start + WINDOW.toDouble() / SpectrumAnalyzer.SAMPLE_RATE)
            }
        } catch (e: Exception) {
            unavailable(e)
        }
    }

    /** Sorted ranges that do not overlap. */
    fun finish(): List<ClosedFloatingPointRange<Double>> = SpeechRanges.merged(found, TRIM)

    override fun close() {
        model?.close()
        model = null
    }

    private companion object {
        const val MODEL = "yamnet.tflite"
        /** The model takes 0.975 s of sound. */
        const val WINDOW = 15_600
        /** 75% overlap, as FeelCore asks of Apple's classifier. */
        const val HOP = WINDOW / 4
        /** "Speech" in the YAMNet label list. */
        const val SPEECH_CLASS = 0
        /**
         * Lower than FeelCore's 0.5. YAMNet scores speech over a music bed low, and at 0.2 it found
         * few windows that Apple's classifier did not call speech. Tuned on two clips only.
         */
        const val MIN_CONFIDENCE = 0.2f
        /** The window is wider than the speech it finds. Trim each side, so hits next to a line stay. */
        const val TRIM = 0.2
    }
}
