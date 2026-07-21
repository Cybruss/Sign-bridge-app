package com.example.sign_bridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class HandLandmarkerProcessor(private val context: Context) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processing = AtomicBoolean(false)
    private var handLandmarker: HandLandmarker? = null

    init {
        setupHandLandmarker()
    }

    fun isReady(): Boolean = handLandmarker != null

    private fun setupHandLandmarker() {
        try {
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("hand_landmarker.task")
                        .setDelegate(Delegate.CPU)
                        .build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .build()

            handLandmarker = HandLandmarker.createFromOptions(context, options)
            Log.i(TAG, "HandLandmarkerProcessor initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize HandLandmarkerProcessor: ${e.message}", e)
            handLandmarker = null
        }
    }

    fun processFrame(request: FrameRequest, callback: (Map<String, Any?>) -> Unit) {
        if (handLandmarker == null) {
            mainHandler.post {
                callback(
                    mapOf(
                        "landmarks" to null,
                        "allHands" to emptyList<List<Double>>()
                    )
                )
            }
            return
        }
        if (!processing.compareAndSet(false, true)) {
            mainHandler.post { callback(emptyMap()) }
            return
        }

        executor.execute {
            try {
                val argb = yuv420ToArgb(
                    request.yBytes,
                    request.uBytes,
                    request.vBytes,
                    request.width,
                    request.height,
                    request.yRowStride,
                    request.uRowStride,
                    request.vRowStride,
                    request.uPixelStride,
                    request.vPixelStride
                )

                val bitmap = Bitmap.createBitmap(request.width, request.height, Bitmap.Config.ARGB_8888)
                bitmap.setPixels(argb, 0, request.width, 0, 0, request.width, request.height)

                val matrix = Matrix().apply {
                    postRotate(request.rotationDegrees.toFloat())
                }

                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                bitmap.recycle()

                val result = try {
                    val mpImage = BitmapImageBuilder(rotated).build()
                    handLandmarker?.detect(mpImage)
                } finally {
                    // MediaPipe reads pixel memory from this bitmap during detect().
                    // Recycle only after detect() returns to avoid JNI crashes.
                    rotated.recycle()
                }
                val hands = result?.landmarks() ?: emptyList()
                val allHands = hands.map { hand ->
                    val points = DoubleArray(hand.size * 3)
                    hand.forEachIndexed { index, landmark ->
                        val base = index * 3
                        points[base] = landmark.x().toDouble()
                        points[base + 1] = landmark.y().toDouble()
                        points[base + 2] = landmark.z().toDouble()
                    }
                    points.toList()
                }

                val primary = allHands.firstOrNull()
                if (primary != null) {
                    LandmarkerBridge.updateLatestLandmarks(primary.map { it.toFloat() }.toFloatArray())
                } else {
                    LandmarkerBridge.clearLatest()
                }

                mainHandler.post {
                    callback(
                        mapOf(
                            "landmarks" to primary,
                            "allHands" to allHands
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "processFrame failed: ${e.message}", e)
                mainHandler.post {
                    callback(
                        mapOf(
                            "landmarks" to null,
                            "allHands" to emptyList<List<Double>>()
                        )
                    )
                }
            } finally {
                processing.set(false)
            }
        }
    }

    private fun yuv420ToArgb(
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        width: Int,
        height: Int,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        uPixelStride: Int,
        vPixelStride: Int,
    ): IntArray {
        val out = IntArray(width * height)
        for (y in 0 until height) {
            val uvRow = y / 2
            for (x in 0 until width) {
                val yIndex = y * yRowStride + x
                val uvCol = x / 2
                val uIndex = uvRow * uRowStride + uvCol * uPixelStride
                val vIndex = uvRow * vRowStride + uvCol * vPixelStride

                val yy = yBytes[yIndex].toInt() and 0xFF
                val uu = uBytes[uIndex].toInt() and 0xFF
                val vv = vBytes[vIndex].toInt() and 0xFF

                var r = (yy + 1.370705f * (vv - 128)).toInt()
                var g = (yy - 0.337633f * (uu - 128) - 0.698001f * (vv - 128)).toInt()
                var b = (yy + 1.732446f * (uu - 128)).toInt()

                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255

                out[y * width + x] = Color.argb(255, r, g, b)
            }
        }
        return out
    }

    override fun close() {
        handLandmarker?.close()
        handLandmarker = null
        executor.shutdownNow()
    }

    data class FrameRequest(
        val yBytes: ByteArray,
        val uBytes: ByteArray,
        val vBytes: ByteArray,
        val width: Int,
        val height: Int,
        val rotationDegrees: Int,
        val isFrontCamera: Boolean,
        val yRowStride: Int,
        val uRowStride: Int,
        val vRowStride: Int,
        val uPixelStride: Int,
        val vPixelStride: Int,
    ) {
        companion object {
            fun from(arguments: Map<String, Any?>): FrameRequest {
                return FrameRequest(
                    yBytes = arguments["yBytes"] as ByteArray,
                    uBytes = arguments["uBytes"] as ByteArray,
                    vBytes = arguments["vBytes"] as ByteArray,
                    width = arguments["width"] as Int,
                    height = arguments["height"] as Int,
                    rotationDegrees = arguments["rotationDegrees"] as Int,
                    isFrontCamera = arguments["isFrontCamera"] as Boolean,
                    yRowStride = arguments["yRowStride"] as Int,
                    uRowStride = arguments["uRowStride"] as Int,
                    vRowStride = arguments["vRowStride"] as Int,
                    uPixelStride = arguments["uPixelStride"] as Int,
                    vPixelStride = arguments["vPixelStride"] as Int,
                )
            }
        }
    }

    companion object {
        private const val TAG = "HandLandmarkerProcessor"
    }
}
