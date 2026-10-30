package com.puretube.pure_tube

import android.content.Context
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioDspPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.puretube.pure_tube/audio_dsp"
        private const val TAG = "AudioDspPlugin"
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null

    private var isDspEnabled: Boolean = false
    private var isSupported: Boolean = false

    init {
        channel.setMethodCallHandler(this)
        Log.i(TAG, "AudioDspPlugin registered on channel: $CHANNEL_NAME")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initDsp" -> {
                val res = initDsp()
                result.success(res)
            }
            "setBandLevel" -> {
                val band = (call.argument<Number>("band"))?.toInt() ?: 0
                val level = (call.argument<Number>("level"))?.toShort() ?: 0.toShort()
                val success = setBandLevel(band, level)
                result.success(success)
            }
            "getBandLevel" -> {
                val band = (call.argument<Number>("band"))?.toInt() ?: 0
                val level = getBandLevel(band)
                result.success(level)
            }
            "setBassBoost" -> {
                val strength = (call.argument<Number>("strength"))?.toShort() ?: 0.toShort()
                val success = setBassBoost(strength)
                result.success(success)
            }
            "setLoudnessEnhancer" -> {
                val gainMb = (call.argument<Number>("gainMb"))?.toInt() ?: 0
                val success = setLoudnessEnhancer(gainMb)
                result.success(success)
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val success = setEnabled(enabled)
                result.success(success)
            }
            "release" -> {
                release()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun initDsp(): Map<String, Any?> {
        try {
            release()

            // Initialize on Audio Session 0 (global Android media output mix)
            val audioSessionId = 0
            val priority = 0

            // 1. Equalizer
            equalizer = Equalizer(priority, audioSessionId).apply {
                enabled = isDspEnabled
            }

            // 2. BassBoost
            try {
                bassBoost = BassBoost(priority, audioSessionId).apply {
                    enabled = isDspEnabled
                }
            } catch (e: Exception) {
                Log.w(TAG, "BassBoost could not be initialized on session 0: ${e.message}")
            }

            // 3. LoudnessEnhancer (API 19+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                try {
                    loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                        enabled = isDspEnabled
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "LoudnessEnhancer could not be initialized on session 0: ${e.message}")
                }
            }

            val eq = equalizer
            if (eq != null) {
                val numBands = eq.numberOfBands.toInt()
                val range = eq.bandLevelRange // ShortArray [min, max] in mB (e.g. -1500 to +1500)
                val centerFreqs = mutableListOf<Int>()

                for (i in 0 until numBands) {
                    // Center freq is returned in milliHertz (mHz), e.g. 60000 mHz = 60 Hz
                    val freqHz = eq.getCenterFreq(i.toShort()) / 1000
                    centerFreqs.add(freqHz)
                }

                val minFreq = if (numBands > 0) eq.getBandFreqRange(0.toShort())[0] / 1000 else 20
                val maxFreq = if (numBands > 0) eq.getBandFreqRange((numBands - 1).toShort())[1] / 1000 else 20000

                isSupported = true
                Log.i(TAG, "DSP successfully initialized: $numBands bands, range: [${range[0]}, ${range[1]}] mB, freqs: $centerFreqs")

                return mapOf(
                    "isSupported" to true,
                    "numberOfBands" to numBands,
                    "minFreq" to minFreq,
                    "maxFreq" to maxFreq,
                    "centerFreqs" to centerFreqs,
                    "bandLevelRange" to listOf(range[0].toInt(), range[1].toInt()),
                    "hasBassBoost" to (bassBoost != null),
                    "hasLoudnessEnhancer" to (loudnessEnhancer != null)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AudioDspPlugin: ${e.message}", e)
        }

        isSupported = false
        return mapOf(
            "isSupported" to false,
            "numberOfBands" to 5,
            "minFreq" to 60,
            "maxFreq" to 14000,
            "centerFreqs" to listOf(60, 230, 910, 3600, 14000),
            "bandLevelRange" to listOf(-1500, 1500),
            "hasBassBoost" to false,
            "hasLoudnessEnhancer" to false
        )
    }

    private fun setBandLevel(band: Int, level: Short): Boolean {
        return try {
            equalizer?.let { eq ->
                if (band in 0 until eq.numberOfBands) {
                    val range = eq.bandLevelRange
                    val clampedLevel = level.coerceIn(range[0], range[1])
                    eq.setBandLevel(band.toShort(), clampedLevel)
                    true
                } else {
                    false
                }
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error in setBandLevel: ${e.message}")
            false
        }
    }

    private fun getBandLevel(band: Int): Int {
        return try {
            equalizer?.let { eq ->
                if (band in 0 until eq.numberOfBands) {
                    eq.getBandLevel(band.toShort()).toInt()
                } else {
                    0
                }
            } ?: 0
        } catch (e: Exception) {
            Log.e(TAG, "Error in getBandLevel: ${e.message}")
            0
        }
    }

    private fun setBassBoost(strength: Short): Boolean {
        return try {
            bassBoost?.let { bb ->
                val clampedStrength = strength.coerceIn(0.toShort(), 1000.toShort())
                bb.setStrength(clampedStrength)
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error in setBassBoost: ${e.message}")
            false
        }
    }

    private fun setLoudnessEnhancer(gainMb: Int): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.let { le ->
                    val clampedGain = gainMb.coerceIn(0, 2000)
                    le.setTargetGain(clampedGain)
                    true
                } ?: false
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in setLoudnessEnhancer: ${e.message}")
            false
        }
    }

    private fun setEnabled(enabled: Boolean): Boolean {
        isDspEnabled = enabled
        return try {
            equalizer?.enabled = enabled
            bassBoost?.enabled = enabled
            loudnessEnhancer?.enabled = enabled
            Log.i(TAG, "DSP enabled state set to: $enabled")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error setting DSP enabled state: ${e.message}")
            false
        }
    }

    fun release() {
        try {
            equalizer?.release()
            equalizer = null
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing Equalizer: ${e.message}")
        }

        try {
            bassBoost?.release()
            bassBoost = null
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing BassBoost: ${e.message}")
        }

        try {
            loudnessEnhancer?.release()
            loudnessEnhancer = null
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing LoudnessEnhancer: ${e.message}")
        }
    }
}
