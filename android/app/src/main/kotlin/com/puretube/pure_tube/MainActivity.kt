package com.puretube.pure_tube

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.util.Rational
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

class PureMediaSession(
    val source: String,
    val channelId: String,
    val channelName: String,
    val notificationId: Int,
    val sessionTag: String,
    private val activity: MainActivity
) {
    var mediaSession: MediaSessionCompat? = null
    var isPlaying: Boolean = false
    var currentTitle: String = ""
    var currentArtist: String = ""
    var currentArtworkUrl: String = ""
    var cachedArtworkBitmap: Bitmap? = null
    var currentPositionMs: Long = 0L
    var currentDurationMs: Long = 0L

    val actionToggle = "com.puretube.ACTION_TOGGLE_${source.uppercase()}"
    val actionPlay = "com.puretube.ACTION_PLAY_${source.uppercase()}"
    val actionPause = "com.puretube.ACTION_PAUSE_${source.uppercase()}"
    val actionNext = "com.puretube.ACTION_NEXT_${source.uppercase()}"
    val actionPrev = "com.puretube.ACTION_PREV_${source.uppercase()}"

    fun init(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "$channelName medya kontrolleri ve bildirim paneli"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val mediaButtonReceiver = ComponentName(activity, MediaButtonReceiver::class.java)
        mediaSession = MediaSessionCompat(activity, sessionTag, mediaButtonReceiver, null).apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                        MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    Log.i("PureTube", "[$source] MediaSessionCompat.onPlay")
                    handlePlay()
                }

                override fun onPause() {
                    Log.i("PureTube", "[$source] MediaSessionCompat.onPause")
                    handlePause()
                }

                override fun onSkipToNext() {
                    Log.i("PureTube", "[$source] MediaSessionCompat.onSkipToNext")
                    handleNext()
                }

                override fun onSkipToPrevious() {
                    Log.i("PureTube", "[$source] MediaSessionCompat.onSkipToPrevious")
                    handlePrev()
                }

                override fun onSeekTo(pos: Long) {
                    Log.i("PureTube", "[$source] MediaSessionCompat.onSeekTo: $pos")
                    handleSeek(pos)
                }

                override fun onFastForward() {
                    handleSeek(currentPositionMs + 10000L)
                }

                override fun onRewind() {
                    handleSeek(maxOf(0L, currentPositionMs - 10000L))
                }

                override fun onMediaButtonEvent(mediaButtonEvent: Intent?): Boolean {
                    val keyEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonEvent?.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonEvent?.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }
                    if (keyEvent != null && keyEvent.action == KeyEvent.ACTION_DOWN) {
                        Log.i("PureTube", "[$source] onMediaButtonEvent keyCode: ${keyEvent.keyCode}")
                        when (keyEvent.keyCode) {
                            KeyEvent.KEYCODE_MEDIA_PLAY -> { handlePlay(); return true }
                            KeyEvent.KEYCODE_MEDIA_PAUSE -> { handlePause(); return true }
                            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK -> {
                                handleToggle()
                                return true
                            }
                            KeyEvent.KEYCODE_MEDIA_NEXT -> { handleNext(); return true }
                            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> { handlePrev(); return true }
                        }
                    }
                    return super.onMediaButtonEvent(mediaButtonEvent)
                }
            })
            isActive = true
        }
    }

    fun handleToggle() {
        if (isPlaying) {
            handlePause()
        } else {
            handlePlay()
        }
    }

    fun handlePlay() {
        Log.i("PureTube", "[$source] handlePlay -> updating state & sending onPlay to Flutter")
        isPlaying = true
        updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
        buildAndPostNotification()
        activity.runOnUiThread {
            activity.mediaMethodChannel?.invokeMethod("onPlay", mapOf("source" to source))
        }
    }

    fun handlePause() {
        Log.i("PureTube", "[$source] handlePause -> updating state & sending onPause to Flutter")
        isPlaying = false
        updatePlaybackState(PlaybackStateCompat.STATE_PAUSED)
        buildAndPostNotification()
        activity.runOnUiThread {
            activity.mediaMethodChannel?.invokeMethod("onPause", mapOf("source" to source))
        }
    }

    fun handleNext() {
        Log.i("PureTube", "[$source] handleNext -> sending onNext to Flutter")
        activity.runOnUiThread {
            activity.mediaMethodChannel?.invokeMethod("onNext", mapOf("source" to source))
        }
    }

    fun handlePrev() {
        Log.i("PureTube", "[$source] handlePrev -> sending onPrevious to Flutter")
        activity.runOnUiThread {
            activity.mediaMethodChannel?.invokeMethod("onPrevious", mapOf("source" to source))
        }
    }

    fun handleSeek(pos: Long) {
        Log.i("PureTube", "[$source] handleSeek: $pos ms -> sending onSeek to Flutter")
        currentPositionMs = pos
        updatePlaybackState(if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED)
        activity.runOnUiThread {
            activity.mediaMethodChannel?.invokeMethod("onSeek", mapOf("source" to source, "positionMs" to pos))
        }
    }

    fun updatePlaybackState(state: Int) {
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_STOP
            )
            .setState(
                state,
                currentPositionMs,
                if (state == PlaybackStateCompat.STATE_PLAYING) 1.0f else 0.0f,
                SystemClock.elapsedRealtime()
            )
            .build()
        mediaSession?.setPlaybackState(playbackState)
    }

    fun updateMetadata(
        title: String,
        artist: String,
        artworkUrl: String,
        playing: Boolean,
        posMs: Long,
        durMs: Long
    ) {
        if (title.isBlank()) return

        currentTitle = title
        currentArtist = artist
        isPlaying = playing
        currentPositionMs = posMs
        currentDurationMs = durMs

        updatePlaybackState(if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED)

        val metaBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durMs)

        if (cachedArtworkBitmap != null) {
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, cachedArtworkBitmap)
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, cachedArtworkBitmap)
        }

        mediaSession?.setMetadata(metaBuilder.build())
        buildAndPostNotification()

        if (artworkUrl.isNotBlank() && artworkUrl != currentArtworkUrl) {
            currentArtworkUrl = artworkUrl
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val url = URL(artworkUrl)
                    val bitmap = BitmapFactory.decodeStream(url.openStream())
                    withContext(Dispatchers.Main) {
                        cachedArtworkBitmap = bitmap
                        val updatedMeta = MediaMetadataCompat.Builder()
                            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
                            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
                            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, currentDurationMs)
                            .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
                            .putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bitmap)
                            .build()
                        mediaSession?.setMetadata(updatedMeta)
                        buildAndPostNotification()
                    }
                } catch (e: Exception) {}
            }
        }
    }

    fun buildAndPostNotification() {
        val session = mediaSession ?: return
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val contentIntent = PendingIntent.getActivity(
            activity,
            if (source == "youtube") 10 else 20,
            Intent(activity, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            flags
        )

        val prevIntent = PendingIntent.getBroadcast(
            activity,
            if (source == "youtube") 11 else 21,
            Intent(actionPrev).setPackage(activity.packageName),
            flags
        )
        val playPauseIntent = PendingIntent.getBroadcast(
            activity,
            if (source == "youtube") 12 else 22,
            Intent(actionToggle).setPackage(activity.packageName),
            flags
        )
        val nextIntent = PendingIntent.getBroadcast(
            activity,
            if (source == "youtube") 13 else 23,
            Intent(actionNext).setPackage(activity.packageName),
            flags
        )

        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val playPauseTitle = if (isPlaying) "Durdur" else "Oynat"

        val defaultSubtext = if (source == "music") "YouTube Music" else "YouTube"
        val builder = NotificationCompat.Builder(activity, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist.ifEmpty { defaultSubtext })
            .setSubText(defaultSubtext)
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .addAction(android.R.drawable.ic_media_previous, "Önceki", prevIntent)
            .addAction(playPauseIcon, playPauseTitle, playPauseIntent)
            .addAction(android.R.drawable.ic_media_next, "Sonraki", nextIntent)
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        if (cachedArtworkBitmap != null) {
            builder.setLargeIcon(cachedArtworkBitmap)
        }

        try {
            activity.notificationManager?.notify(notificationId, builder.build())
        } catch (e: Exception) {}
    }

    fun clear() {
        activity.notificationManager?.cancel(notificationId)
        val playbackState = PlaybackStateCompat.Builder()
            .setState(PlaybackStateCompat.STATE_STOPPED, 0, 0f)
            .build()
        mediaSession?.setPlaybackState(playbackState)
    }

    fun release() {
        clear()
        mediaSession?.release()
    }
}

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.puretube/pip"
    private val MEDIA_CHANNEL = "com.puretube/media"

    private var pipMethodChannel: MethodChannel? = null
    var mediaMethodChannel: MethodChannel? = null
    private var autoPipEnabled: Boolean = false

    var notificationManager: NotificationManager? = null
    lateinit var ytSession: PureMediaSession
    lateinit var musicSession: PureMediaSession

    private val mediaActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val act = intent?.action ?: return
            Log.i("PureTube", "mediaActionReceiver received action: $act")
            when (act) {
                ytSession.actionToggle -> ytSession.handleToggle()
                ytSession.actionPlay -> ytSession.handlePlay()
                ytSession.actionPause -> ytSession.handlePause()
                ytSession.actionNext -> ytSession.handleNext()
                ytSession.actionPrev -> ytSession.handlePrev()
                musicSession.actionToggle -> musicSession.handleToggle()
                musicSession.actionPlay -> musicSession.handlePlay()
                musicSession.actionPause -> musicSession.handlePause()
                musicSession.actionNext -> musicSession.handleNext()
                musicSession.actionPrev -> musicSession.handlePrev()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )
        unlockHighRefreshRate()
        initMediaSessions()
        registerMediaReceiver()
    }

    private fun registerMediaReceiver() {
        val filter = IntentFilter().apply {
            addAction(ytSession.actionToggle)
            addAction(ytSession.actionPlay)
            addAction(ytSession.actionPause)
            addAction(ytSession.actionNext)
            addAction(ytSession.actionPrev)
            addAction(musicSession.actionToggle)
            addAction(musicSession.actionPlay)
            addAction(musicSession.actionPause)
            addAction(musicSession.actionNext)
            addAction(musicSession.actionPrev)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaActionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(mediaActionReceiver, filter)
        }
    }

    private fun initMediaSessions() {
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        ytSession = PureMediaSession(
            source = "youtube",
            channelId = "puretube_yt_playback",
            channelName = "PureTube YouTube",
            notificationId = 1001,
            sessionTag = "PureTubeYT",
            activity = this
        )
        ytSession.init(notificationManager!!)

        musicSession = PureMediaSession(
            source = "music",
            channelId = "puretube_music_playback",
            channelName = "PureTube YouTube Music",
            notificationId = 1002,
            sessionTag = "PureTubeMusic",
            activity = this
        )
        musicSession.init(notificationManager!!)
    }

    private fun unlockHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val window = window
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    window.windowManager.defaultDisplay
                }
                val modes = display?.supportedModes
                val highestMode = modes?.maxByOrNull { it.refreshRate }
                if (highestMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = highestMode.modeId
                    window.attributes = params
                }
            } catch (e: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. PIP Channel
        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val builder = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                builder.setAutoEnterEnabled(autoPipEnabled)
                            }
                            val entered = enterPictureInPictureMode(builder.build())
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setAutoPip" -> {
                    autoPipEnabled = call.argument<Boolean>("enabled") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .setAutoEnterEnabled(autoPipEnabled)
                                .build()
                            setPictureInPictureParams(params)
                        } catch (e: Exception) {}
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Media Notification Channel
        mediaMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        mediaMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMediaMetadata" -> {
                    val source = call.argument<String>("source") ?: "youtube"
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val artwork = call.argument<String>("artwork") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong() ?: 0L

                    if (source == "music") {
                        musicSession.updateMetadata(title, artist, artwork, isPlaying, positionMs, durationMs)
                    } else {
                        ytSession.updateMetadata(title, artist, artwork, isPlaying, positionMs, durationMs)
                    }
                    result.success(true)
                }
                "clearMediaNotification" -> {
                    val source = call.argument<String>("source") ?: "all"
                    when (source) {
                        "youtube" -> ytSession.clear()
                        "music" -> musicSession.clear()
                        else -> {
                            ytSession.clear()
                            musicSession.clear()
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(mediaActionReceiver)
        } catch (e: Exception) {}
        ytSession.release()
        musicSession.release()
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(true)
                }
                enterPictureInPictureMode(builder.build())
            } catch (e: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMethodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
