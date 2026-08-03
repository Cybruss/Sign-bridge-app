package com.example.sign_bridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarkerResult
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Produces the exact 180-landmark-per-frame feature vector the Sign Bridge GRU
 * model was trained on (see the Kaggle "sign-bridge" notebook).
 *
 * Training raw layout was MediaPipe Holistic concatenated as:
 *   [0:21]=right hand, [21:42]=left hand, [42:75]=pose(33), [75:553]=face(478)
 * and then filtered down to 180 landmarks in this order:
 *   21 right-hand + 21 left-hand + 6 pose(idx 11..16) + 132 face(FACE_INDICES).
 *
 * Coordinates are MediaPipe normalized image coords (x,y in [0,1], z relative).
 * Missing hands / out-of-range iris points are zero-filled — the model was
 * trained with landmark-dropout augmentation, so it tolerates a few zeros.
 */
class HolisticLandmarkerProcessor(private val context: Context) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processing = AtomicBoolean(false)
    private var holistic: HolisticLandmarker? = null

    init {
        setup()
    }

    fun isReady(): Boolean = holistic != null

    private fun setup() {
        // Try the GPU delegate first (much faster for holistic on the Pixel),
        // then fall back to CPU if the device/driver can't create it.
        for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
            try {
                val options = HolisticLandmarker.HolisticLandmarkerOptions.builder()
                    .setBaseOptions(
                        BaseOptions.builder()
                            .setModelAssetPath(MODEL_ASSET)
                            .setDelegate(delegate)
                            .build()
                    )
                    .setRunningMode(RunningMode.IMAGE)
                    .setMinFaceDetectionConfidence(0.5f)
                    .setMinPoseDetectionConfidence(0.5f)
                    .setMinHandLandmarksConfidence(0.5f)
                    .build()
                holistic = HolisticLandmarker.createFromOptions(context, options)
                Log.i(TAG, "HolisticLandmarkerProcessor initialized ($delegate)")
                return
            } catch (t: Throwable) {
                // Catch Throwable (not just Exception) so an init Error can't
                // crash the app — try the next delegate, else stay unavailable.
                Log.e(TAG, "Init with $delegate failed: ${t.message}", t)
                holistic = null
            }
        }
    }

    fun processFrame(request: FrameRequest, callback: (Map<String, Any?>) -> Unit) {
        if (holistic == null) {
            mainHandler.post { callback(emptyResult()) }
            return
        }
        if (!processing.compareAndSet(false, true)) {
            mainHandler.post { callback(emptyMap()) }
            return
        }

        executor.execute {
            try {
                val argb = yuv420ToArgb(
                    request.yBytes, request.uBytes, request.vBytes,
                    request.width, request.height,
                    request.yRowStride, request.uRowStride, request.vRowStride,
                    request.uPixelStride, request.vPixelStride
                )

                val bitmap = Bitmap.createBitmap(request.width, request.height, Bitmap.Config.ARGB_8888)
                bitmap.setPixels(argb, 0, request.width, 0, 0, request.width, request.height)

                val matrix = Matrix().apply { postRotate(request.rotationDegrees.toFloat()) }
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                bitmap.recycle()

                val result = try {
                    holistic?.detect(BitmapImageBuilder(rotated).build())
                } finally {
                    rotated.recycle()
                }

                mainHandler.post { callback(buildResult(result)) }
            } catch (e: Exception) {
                Log.e(TAG, "processFrame failed: ${e.message}", e)
                mainHandler.post { callback(emptyResult()) }
            } finally {
                processing.set(false)
            }
        }
    }

    /** Assemble the 180x3 feature vector (length 540) in the trained order. */
    private fun buildResult(result: HolisticLandmarkerResult?): Map<String, Any?> {
        if (result == null) return emptyResult()

        val right = result.rightHandLandmarks()
        val left = result.leftHandLandmarks()
        val pose = result.poseLandmarks()
        val face = result.faceLandmarks()

        val out = DoubleArray(TOTAL_LANDMARKS * 3) // zero-filled by default

        var w = 0
        // [0:21] right hand
        w = writeLandmarks(out, w, right, (0 until 21).toList())
        // [21:42] left hand
        w = writeLandmarks(out, w, left, (0 until 21).toList())
        // [42:48] pose subset (shoulders/elbows/wrists)
        w = writeLandmarks(out, w, pose, POSE_INDICES)
        // [48:180] face subset
        writeLandmarks(out, w, face, FACE_INDICES)

        val hasHands = right.isNotEmpty() || left.isNotEmpty()
        val hasPerson = hasHands || pose.isNotEmpty() || face.isNotEmpty()

        return mapOf(
            "landmarks180" to if (hasPerson) out.toList() else null,
            "hasHands" to hasHands,
            "rightHand" to handOverlay(right),
            "leftHand" to handOverlay(left)
        )
    }

    /**
     * Copy selected landmarks into [out] starting at flat index [start] (in floats/doubles).
     * If the source list is empty or an index is out of range, that slot stays 0.
     * Returns the next write offset.
     */
    private fun writeLandmarks(
        out: DoubleArray,
        start: Int,
        src: List<NormalizedLandmark>,
        indices: List<Int>
    ): Int {
        var w = start
        for (idx in indices) {
            if (src.isNotEmpty() && idx < src.size) {
                val lm = src[idx]
                out[w] = lm.x().toDouble()
                out[w + 1] = lm.y().toDouble()
                out[w + 2] = lm.z().toDouble()
            }
            w += 3
        }
        return w
    }

    /** 21x3 flat list for the on-screen overlay painter, or null if the hand is absent. */
    private fun handOverlay(hand: List<NormalizedLandmark>): List<Double>? {
        if (hand.isEmpty()) return null
        val pts = DoubleArray(hand.size * 3)
        hand.forEachIndexed { i, lm ->
            pts[i * 3] = lm.x().toDouble()
            pts[i * 3 + 1] = lm.y().toDouble()
            pts[i * 3 + 2] = lm.z().toDouble()
        }
        return pts.toList()
    }

    private fun emptyResult(): Map<String, Any?> = mapOf(
        "landmarks180" to null,
        "hasHands" to false,
        "rightHand" to null,
        "leftHand" to null
    )

    private fun yuv420ToArgb(
        yBytes: ByteArray, uBytes: ByteArray, vBytes: ByteArray,
        width: Int, height: Int,
        yRowStride: Int, uRowStride: Int, vRowStride: Int,
        uPixelStride: Int, vPixelStride: Int,
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
        holistic?.close()
        holistic = null
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
            fun from(a: Map<String, Any?>): FrameRequest = FrameRequest(
                yBytes = a["yBytes"] as ByteArray,
                uBytes = a["uBytes"] as ByteArray,
                vBytes = a["vBytes"] as ByteArray,
                width = a["width"] as Int,
                height = a["height"] as Int,
                rotationDegrees = a["rotationDegrees"] as Int,
                isFrontCamera = a["isFrontCamera"] as Boolean,
                yRowStride = a["yRowStride"] as Int,
                uRowStride = a["uRowStride"] as Int,
                vRowStride = a["vRowStride"] as Int,
                uPixelStride = a["uPixelStride"] as Int,
                vPixelStride = a["vPixelStride"] as Int,
            )
        }
    }

    companion object {
        private const val TAG = "HolisticProcessor"
        private const val MODEL_ASSET = "holistic_landmarker.task"

        // 180 landmarks total: 21 + 21 + 6 + 132
        private const val TOTAL_LANDMARKS = 180

        // Pose subset (indices into the 33 pose landmarks): shoulders, elbows, wrists.
        private val POSE_INDICES = listOf(11, 12, 13, 14, 15, 16)

        // Face subset (indices into the face-mesh landmarks) — 132 points, from the
        // notebook's filtered_face. Iris indices >= 468 are zero-filled when the
        // Tasks HolisticLandmarker returns only 468 face points.
        private val FACE_INDICES = listOf(
            0, 4, 7, 8, 10, 13, 14, 17, 21, 33, 37, 39, 40, 46, 52, 53, 54, 55, 58,
            61, 63, 65, 66, 67, 70, 78, 80, 81, 82, 84, 87, 88, 91, 93, 95, 103, 105,
            107, 109, 127, 132, 133, 136, 144, 145, 146, 148, 149, 150, 152, 153, 154,
            155, 157, 158, 159, 160, 161, 162, 163, 172, 173, 176, 178, 181, 185, 191,
            234, 246, 249, 251, 263, 267, 269, 270, 276, 282, 283, 284, 285, 288, 291,
            293, 295, 296, 297, 300, 308, 310, 311, 312, 314, 317, 318, 321, 323, 324,
            332, 334, 336, 338, 356, 361, 362, 365, 373, 374, 375, 377, 378, 379, 380,
            381, 382, 384, 385, 386, 387, 388, 389, 390, 397, 398, 400, 402, 405, 409,
            415, 454, 466, 468, 473
        )
    }
}
