package com.puretube.pure_tube

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

class PurePlaybackService : Service() {
    companion object {
        var isRunning = false
            private set
        private var wakeLock: PowerManager.WakeLock? = null
        private var wifiLock: WifiManager.WifiLock? = null

        fun start(context: Context, notificationId: Int, notification: Notification) {
            val intent = Intent(context, PurePlaybackService::class.java).apply {
                action = "ACTION_START"
                putExtra("NOTIFICATION_ID", notificationId)
                putExtra("NOTIFICATION", notification)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e("PureTube", "Failed to start PurePlaybackService: ${e.message}")
            }
        }

        fun stop(context: Context) {
            if (!isRunning) return
            val intent = Intent(context, PurePlaybackService::class.java).apply {
                action = "ACTION_STOP"
            }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e("PureTube", "Failed to stop PurePlaybackService: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "ACTION_START"
        if (action == "ACTION_STOP") {
            releaseLocks()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            isRunning = false
            Log.i("PureTube", "PurePlaybackService stopped foreground")
            return START_NOT_STICKY
        }

        val notificationId = intent?.getIntExtra("NOTIFICATION_ID", 1002) ?: 1002
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("NOTIFICATION", Notification::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("NOTIFICATION")
        }

        if (notification != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        notificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    )
                } else {
                    startForeground(notificationId, notification)
                }
                acquireLocks()
                isRunning = true
                Log.i("PureTube", "PurePlaybackService is running foreground with WakeLock and WifiLock (id: $notificationId)")
            } catch (e: Exception) {
                Log.e("PureTube", "Error starting foreground service: ${e.message}")
            }
        }

        return START_STICKY
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PureTube:MediaWakeLock").apply {
                    setReferenceCounted(false)
                    acquire(24 * 60 * 60 * 1000L) // 24 saat max
                }
                Log.i("PureTube", "WakeLock acquired")
            }
        } catch (e: Exception) {
            Log.e("PureTube", "WakeLock error: ${e.message}")
        }

        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "PureTube:WifiLock").apply {
                    setReferenceCounted(false)
                    acquire()
                }
                Log.i("PureTube", "WifiLock acquired")
            }
        } catch (e: Exception) {
            Log.e("PureTube", "WifiLock error: ${e.message}")
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (e: Exception) {}

        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
            wifiLock = null
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        releaseLocks()
        isRunning = false
        Log.i("PureTube", "PurePlaybackService destroyed")
        super.onDestroy()
    }
}
