package com.example.sign_bridge

/**
 * A small thread-safe bridge to share the latest hand landmarks and availability
 * between native MediaPipe components and Flutter via MethodChannel.
 */
object LandmarkerBridge {
    // Volatile to ensure visibility across threads
    @Volatile
    private var available: Boolean = false

    // Latest landmarks as a copy of the FloatArray (x,y,z for 21 points => 63 floats)
    @Volatile
    private var latest: FloatArray? = null

    // All hands' landmarks
    @Volatile
    private var allHandsLandmarks: List<FloatArray>? = null

    // Number of detected hands
    @Volatile
    private var handCount: Int = 0

    // Sentence result from sign detection
    @Volatile
    private var sentenceResult: String? = null

    @Synchronized
    fun setAvailable(value: Boolean) {
        available = value
    }

    fun isAvailable(): Boolean = available

    @Synchronized
    fun updateLatestLandmarks(arr: FloatArray) {
        // store a copy to avoid callers mutating the array
        latest = arr.copyOf()
    }

    @Synchronized
    fun updateAllHandsLandmarks(allHands: List<FloatArray>) {
        allHandsLandmarks = allHands.map { it.copyOf() }
        handCount = allHands.size
        // Also update first hand as "latest" for backward compatibility
        if (allHands.isNotEmpty()) {
            latest = allHands[0].copyOf()
        } else {
            latest = null
        }
    }

    @Synchronized
    fun getLatestLandmarks(): FloatArray? {
        return latest?.copyOf()
    }

    @Synchronized
    fun getAllHandsLandmarks(): List<FloatArray>? {
        return allHandsLandmarks?.map { it.copyOf() }
    }

    @Synchronized
    fun getHandCount(): Int = handCount

    @Synchronized
    fun clearLatest() {
        latest = null
        allHandsLandmarks = null
        handCount = 0
    }

    @Synchronized
    fun setSentenceResult(sentence: String) {
        sentenceResult = sentence
    }

    @Synchronized
    fun getSentenceResult(): String? {
        val result = sentenceResult
        sentenceResult = null // Clear after reading (single-use)
        return result
    }
}
