/*
 * Copyright 2022 The TensorFlow Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *             http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.example.sign_bridge

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.util.Log
import android.view.View
import androidx.core.content.ContextCompat
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import kotlin.math.max
import kotlin.math.min

class OverlayView(context: Context?, attrs: AttributeSet?) :
    View(context, attrs) {

    private var results: HandLandmarkerResult? = null
    private var linePaint = Paint()
    private var pointPaint = Paint()

    private var scaleFactor: Float = 1f
    private var imageWidth: Int = 1
    private var imageHeight: Int = 1
    private var offsetX: Float = 0f
    private var offsetY: Float = 0f

    init {
        initPaints()
    }

    fun clear() {
        results = null
        linePaint.reset()
        pointPaint.reset()
        invalidate()
        initPaints()
    }

    private fun initPaints() {
        linePaint.color =
            ContextCompat.getColor(context!!, R.color.mp_color_primary)
        linePaint.strokeWidth = LANDMARK_STROKE_WIDTH
        linePaint.style = Paint.Style.STROKE

        pointPaint.color = Color.YELLOW
        pointPaint.strokeWidth = LANDMARK_STROKE_WIDTH
        pointPaint.style = Paint.Style.FILL
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        results?.let { handLandmarkerResult ->
            for (landmark in handLandmarkerResult.landmarks()) {
                for (normalizedLandmark in landmark) {
                    // Convert normalized coordinates (0-1) to pixel coordinates
                    val x = normalizedLandmark.x() * imageWidth
                    val y = normalizedLandmark.y() * imageHeight
                    
                    // Apply scaling and offset
                    val screenX = x * scaleFactor + offsetX
                    val screenY = y * scaleFactor + offsetY
                    
                    canvas.drawPoint(screenX, screenY, pointPaint)
                }

                HandLandmarker.HAND_CONNECTIONS.forEach {
                    val startX = landmark.get(it!!.start()).x() * imageWidth
                    val startY = landmark.get(it.start()).y() * imageHeight
                    val endX = landmark.get(it.end()).x() * imageWidth
                    val endY = landmark.get(it.end()).y() * imageHeight
                    
                    val screenStartX = startX * scaleFactor + offsetX
                    val screenStartY = startY * scaleFactor + offsetY
                    val screenEndX = endX * scaleFactor + offsetX
                    val screenEndY = endY * scaleFactor + offsetY
                    
                    canvas.drawLine(screenStartX, screenStartY, screenEndX, screenEndY, linePaint)
                }
            }
        }
    }

    fun setResults(
        handLandmarkerResults: HandLandmarkerResult,
        imageHeight: Int,
        imageWidth: Int,
        runningMode: RunningMode = RunningMode.IMAGE
    ) {
        results = handLandmarkerResults
        this.imageHeight = imageHeight
        this.imageWidth = imageWidth

        when (runningMode) {
            RunningMode.IMAGE,
            RunningMode.VIDEO -> {
                scaleFactor = min(width * 1f / imageWidth, height * 1f / imageHeight)
                offsetX = (width - imageWidth * scaleFactor) / 2f
                offsetY = (height - imageHeight * scaleFactor) / 2f
            }
            RunningMode.LIVE_STREAM -> {
                // For live camera preview, simply scale to match view dimensions
                // PreviewView handles rotation, we just need to scale the overlay
                scaleFactor = width * 1f / imageWidth
                val scaledHeight = imageHeight * scaleFactor
                
                // Center vertically if needed
                offsetX = 0f
                offsetY = (height - scaledHeight) / 2f
                
                Log.d(TAG, "OverlayView: view=${width}x${height}, image=${imageWidth}x${imageHeight}, " +
                    "scale=$scaleFactor, offset=($offsetX, $offsetY)")
            }
        }
        invalidate()
    }

    companion object {
        private const val TAG = "OverlayView"
        private const val LANDMARK_STROKE_WIDTH = 8F
    }
}