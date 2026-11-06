package com.spotnik.ephemeron

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat

class AlarmRingService : Service() {

    companion object {
        const val EXTRA_REQUEST_CODE = "requestCode"
        const val EXTRA_TITLE = "title"
        const val EXTRA_PRESET = "preset"
        const val EXTRA_BODY = "body"
        const val EXTRA_KIND = "kind"
        const val EXTRA_FULL_SCREEN = "fullScreen"

        const val ACTION_STOP = "com.spotnik.ephemeron.ALARM_RING_STOP"

        fun shouldRing(preset: String, kind: String): Boolean {
            if (kind == "reminder") return false
            return AlarmPlugin.normalizePreset(preset) != "notification"
        }

        fun start(
            context: Context,
            requestCode: Int,
            title: String,
            preset: String,
            body: String,
            kind: String,
            fullScreen: Boolean,
        ) {
            if (!shouldRing(preset, kind)) return
            val intent = Intent(context, AlarmRingService::class.java).apply {
                putExtra(EXTRA_REQUEST_CODE, requestCode)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PRESET, preset)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_KIND, kind)
                putExtra(EXTRA_FULL_SCREEN, fullScreen)
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context, requestCode: Int) {
            val intent = Intent(context, AlarmRingService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_REQUEST_CODE, requestCode)
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
            }
        }

        fun stopAll(context: Context) {
            val intent = Intent(context, AlarmRingService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_REQUEST_CODE, -1)
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
            }
        }
    }

    private class Active(
        val player: MediaPlayer?,
        val handler: Handler,
        val blink: Runnable,
        val torchOff: Runnable,
        val cameraId: String?,
    )

    private val actives = mutableMapOf<Int, Active>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            val rc = intent.getIntExtra(EXTRA_REQUEST_CODE, -1)
            if (rc >= 0) stopRing(rc) else {
                for (key in ArrayList(actives.keys)) stopRing(key)
            }
            if (actives.isEmpty()) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(STOP_FOREGROUND_DETACH)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(false)
                    }
                } catch (_: Exception) {
                }
                stopSelf()
            }
            return START_NOT_STICKY
        }

        val rc = intent?.getIntExtra(EXTRA_REQUEST_CODE, -1) ?: -1
        if (rc < 0) return START_NOT_STICKY
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Alarm"
        val preset = intent?.getStringExtra(EXTRA_PRESET) ?: "notification"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""
        val kind = intent?.getStringExtra(EXTRA_KIND) ?: "alarm"
        val fullScreen = intent?.getBooleanExtra(EXTRA_FULL_SCREEN, true) ?: true

        if (!shouldRing(preset, kind)) return START_NOT_STICKY

        val norm = AlarmPlugin.normalizePreset(preset)

        val notification = AlarmPlugin.buildNotification(
            this, rc, title, preset, body, kind, fullScreen,
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(rc, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(rc, notification)
            }
        } catch (_: Exception) {
            try {
                startForeground(rc, notification)
            } catch (_: Exception) {
            }
        }

        if (actives.containsKey(rc)) return START_NOT_STICKY

        val handler = Handler(Looper.getMainLooper())

        var player: MediaPlayer? = null
        try {
            val mp = MediaPlayer()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            if (uri != null) {
                mp.setDataSource(this, uri)
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                mp.isLooping = (norm == "full_long")
                mp.prepare()
                mp.start()
                player = mp
            } else {
                try { mp.release() } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            try { player?.release() } catch (_: Exception) {}
            player = null
        }

        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        var cameraId: String? = null
        if (cameraManager != null) {
            cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                try {
                    cameraManager.getCameraCharacteristics(id)
                        .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                } catch (_: Exception) {
                    false
                }
            }
        }

        val blink = object : Runnable {
            var on = false
            override fun run() {
                if (cameraId == null || cameraManager == null) return
                on = !on
                try {
                    cameraManager.setTorchMode(cameraId, on)
                } catch (_: Exception) {
                }
                handler.postDelayed(this, 500)
            }
        }

        val torchOff = Runnable {
            handler.removeCallbacks(blink)
            if (cameraId != null && cameraManager != null) {
                try {
                    cameraManager.setTorchMode(cameraId, false)
                } catch (_: Exception) {
                }
            }
        }

        if (cameraId != null) {
            handler.post(blink)
            handler.postDelayed(torchOff, 30000)
        }

        actives[rc] = Active(player, handler, blink, torchOff, cameraId)
        return START_NOT_STICKY
    }

    private fun stopRing(rc: Int) {
        val active = actives.remove(rc) ?: return
        try {
            active.player?.stop()
        } catch (_: Exception) {
        }
        try {
            active.player?.release()
        } catch (_: Exception) {
        }
        active.handler.removeCallbacks(active.blink)
        active.handler.removeCallbacks(active.torchOff)
        if (active.cameraId != null) {
            try {
                val cm = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                cm?.setTorchMode(active.cameraId, false)
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        for (key in ArrayList(actives.keys)) stopRing(key)
        super.onDestroy()
    }
}
