package com.example.sign_bridge

import android.content.Context
import android.util.Log
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.max

import org.tensorflow.lite.Interpreter
// Avoid relying on FlutterLoader APIs at compile time; try known asset lookup prefixes instead.

class SignClassifier(context: Context) {
    companion object {
        private const val TAG = "SignClassifier"
        private const val MODEL_PATH = "models/sign_language_model.tflite"
        private const val LABEL_PATH = "models/labels.txt"
        private const val SEQ_LEN = 30
        private const val FEAT_LEN = 63
    }

    private val interpreter: Interpreter
    private val labels: List<String>
    private val frameBuffer: ArrayDeque<FloatArray> = ArrayDeque()

    init {
        interpreter = Interpreter(loadModelFile(context, MODEL_PATH))
        labels = loadLabels(context)
        Log.i(TAG, "Loaded TFLite model and ${labels.size} labels")
    }

    private fun loadLabels(context: Context): List<String> {
        return try {
            // Try direct path first, then try Flutter asset lookup key
            try {
                context.assets.open(LABEL_PATH).bufferedReader().useLines { it.toList() }
            } catch (e: Exception) {
                // Try common Flutter asset locations (flutter_assets/ and assets/ prefixes)
                val tryKeys = listOf(LABEL_PATH, "assets/$LABEL_PATH", "flutter_assets/$LABEL_PATH", "flutter_assets/assets/$LABEL_PATH")
                var lines: List<String>? = null
                for (key in tryKeys) {
                    try {
                        lines = context.assets.open(key).bufferedReader().useLines { it.toList() }
                        break
                    } catch (_: Exception) {
                        // try next
                    }
                }
                lines ?: throw RuntimeException("Label asset not found: $LABEL_PATH")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load labels: $e")
            listOf()
        }
    }

    private fun loadModelFile(context: Context, modelPath: String): MappedByteBuffer {
        try {
            // Try direct asset path first
            val fileDescriptor = context.assets.openFd(modelPath)
            FileInputStream(fileDescriptor.fileDescriptor).use { input ->
                val channel: FileChannel = input.channel
                val startOffset = fileDescriptor.startOffset
                val declaredLength = fileDescriptor.declaredLength
                return channel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
            }
        } catch (e: Exception) {
            // Fallback: try Flutter's lookup key for packaged assets (try with/without leading 'assets/')
            val tryKeys = listOf(modelPath, "assets/$modelPath", "flutter_assets/$modelPath", "flutter_assets/assets/$modelPath")
            var afd: android.content.res.AssetFileDescriptor? = null
            for (key in tryKeys) {
                try {
                    afd = context.assets.openFd(key)
                    break
                } catch (_: Exception) {
                    // continue trying
                }
            }
            if (afd == null) throw RuntimeException("Model asset not found: $modelPath")
            FileInputStream(afd.fileDescriptor).use { input ->
                val channel: FileChannel = input.channel
                val startOffset = afd.startOffset
                val declaredLength = afd.declaredLength
                return channel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
            }
        }
    }

    fun addFrameAndClassify(frame: FloatArray): Pair<String, Float>? {
        if (frame.size != FEAT_LEN) {
            Log.w(TAG, "Unexpected frame length: ${frame.size}")
            return null
        }

        if (frameBuffer.size >= SEQ_LEN) frameBuffer.removeFirst()
        frameBuffer.addLast(frame)

        if (frameBuffer.size < SEQ_LEN) return null // not enough frames yet

        // Build input [1, SEQ_LEN, FEAT_LEN]
        val input = Array(1) { Array(SEQ_LEN) { FloatArray(FEAT_LEN) } }
        var i = 0
        for (f in frameBuffer) {
            input[0][i++] = f
        }

        // Output shape [1, numClasses]
        val numClasses = if (labels.isNotEmpty()) labels.size else 1
        val output = Array(1) { FloatArray(max(numClasses, 1)) }

        try {
            interpreter.run(input, output)
        } catch (e: Exception) {
            Log.e(TAG, "Interpreter run failed: $e")
            return null
        }

        val scores = output[0]
        var maxIdx = 0
        var maxVal = scores[0]
        for (k in scores.indices) {
            if (scores[k] > maxVal) {
                maxVal = scores[k]
                maxIdx = k
            }
        }

        val label = if (labels.isNotEmpty() && maxIdx < labels.size) labels[maxIdx] else "CLASS_$maxIdx"
        return Pair(label, maxVal)
    }

    fun close() {
        interpreter.close()
    }
}
