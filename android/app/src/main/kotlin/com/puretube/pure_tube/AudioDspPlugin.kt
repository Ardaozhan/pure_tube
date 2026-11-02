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
    private val cachedBandLevels = mutableMapOf<Int, Short>()
    private var cachedBassStrength: Short = 0
    private var cachedLoudnessGainMb: Int = 0

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

    private fun ensureEffectsAttached(): Boolean {
        if (equalizer != null) return true
        return try {
            val audioSessionId = 0
            val priority = 0
            equalizer = Equalizer(priority, audioSessionId).apply {
                enabled = isDspEnabled
            }
            try {
                bassBoost = BassBoost(priority, audioSessionId).apply {
                    enabled = isDspEnabled
                }
            } catch (e: Exception) {
                Log.w(TAG, "BassBoost could not be initialized on session 0: ${e.message}")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                try {
                    loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                        enabled = isDspEnabled
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "LoudnessEnhancer could not be initialized on session 0: ${e.message}")
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to attach AudioEffects: ${e.message}")
            false
        }
    }

    private fun initDsp(): Map<String, Any?> {
        try {
            release()

            if (ensureEffectsAttached()) {
                val eq = equalizer
                if (eq != null) {
                    val numBands = eq.numberOfBands.toInt()
                    val range = eq.bandLevelRange
                    val centerFreqs = mutableListOf<Int>()

                    for (i in 0 until numBands) {
                        val freqHz = try {
                            eq.getCenterFreq(i.toShort()) / 1000
                        } catch (_: Exception) {
                            60 * (1 shl i)
                        }
                        centerFreqs.add(freqHz)
                    }

                    val minFreq = try {
                        if (numBands > 0) eq.getBandFreqRange(0.toShort())[0] / 1000 else 20
                    } catch (_: Exception) { 20 }
                    val maxFreq = try {
                        if (numBands > 0) eq.getBandFreqRange((numBands - 1).toShort())[1] / 1000 else 20000
                    } catch (_: Exception) { 20000 }

                    val hasBb = bassBoost != null
                    val hasLe = loudnessEnhancer != null
                    isSupported = true
                    Log.i(TAG, "DSP probed: $numBands bands, range: [${range[0]}, ${range[1]}] mB, freqs: $centerFreqs")

                    // Release immediately if DSP is not enabled so OEM audio (Dolby Atmos / HyperOS / OneUI) is never hijacked
                    if (!isDspEnabled) {
                        release()
                    }

                    return mapOf(
                        "isSupported" to true,
                        "numberOfBands" to numBands,
                        "minFreq" to minFreq,
                        "maxFreq" to maxFreq,
                        "centerFreqs" to centerFreqs,
                        "bandLevelRange" to listOf(range[0].toInt(), range[1].toInt()),
                        "hasBassBoost" to hasBb,
                        "hasLoudnessEnhancer" to hasLe
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AudioDspPlugin: ${e.message}", e)
            release()
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
        cachedBandLevels[band] = level
        if (!isDspEnabled) return true
        return try {
            if (!ensureEffectsAttached()) return false
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
        if (!isDspEnabled) return cachedBandLevels[band]?.toInt() ?: 0
        return try {
            equalizer?.let { eq ->
                if (band in 0 until eq.numberOfBands) {
                    eq.getBandLevel(band.toShort()).toInt()
                } else {
                    0
                }
            } ?: (cachedBandLevels[band]?.toInt() ?: 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error in getBandLevel: ${e.message}")
            cachedBandLevels[band]?.toInt() ?: 0
        }
    }

    private fun setBassBoost(strength: Short): Boolean {
        cachedBassStrength = strength.coerceIn(0.toShort(), 1000.toShort())
        if (!isDspEnabled) return true
        return try {
            if (!ensureEffectsAttached()) return false
            bassBoost?.let { bb ->
                bb.setStrength(cachedBassStrength)
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error in setBassBoost: ${e.message}")
            false
        }
    }

    private fun setLoudnessEnhancer(gainMb: Int): Boolean {
        cachedLoudnessGainMb = gainMb.coerceIn(0, 2000)
        if (!isDspEnabled) return true
        return try {
            if (!ensureEffectsAttached()) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.let { le ->
                    le.setTargetGain(cachedLoudnessGainMb)
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
        if (!enabled) {
            release()
            Log.i(TAG, "DSP disabled and released from session 0")
            return true
        }
        return try {
            if (!ensureEffectsAttached()) return false
            equalizer?.enabled = true
            bassBoost?.enabled = true
            loudnessEnhancer?.enabled = true
            for ((band, level) in cachedBandLevels) {
                setBandLevel(band, level)
            }
            setBassBoost(cachedBassStrength)
            setLoudnessEnhancer(cachedLoudnessGainMb)
            Log.i(TAG, "DSP enabled and attached to session 0")
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
