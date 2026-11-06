package com.spotnik.ephemeron

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires when an alarm goes off; re-registers after boot/time changes. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_LOCALE_CHANGED -> {
                AlarmStore.rescheduleAll(context)
                return
            }
        }
        val rc = intent.getIntExtra(AlarmPlugin.EXTRA_REQUEST_CODE, intent.getIntExtra("requestCode", -1))
        if (rc < 0) return
        val title = intent.getStringExtra(AlarmPlugin.EXTRA_TITLE) ?: intent.getStringExtra("title") ?: "Alarm"
        val preset = intent.getStringExtra(AlarmPlugin.EXTRA_PRESET) ?: intent.getStringExtra("preset") ?: "notification"
        val body = intent.getStringExtra(AlarmPlugin.EXTRA_BODY) ?: intent.getStringExtra("body") ?: ""
        val kind = intent.getStringExtra(AlarmPlugin.EXTRA_KIND) ?: intent.getStringExtra("kind") ?: "alarm"
        val fullScreen = intent.getBooleanExtra(AlarmPlugin.EXTRA_FULL_SCREEN, intent.getBooleanExtra("fullScreen", true))
        val sourceType = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_TYPE) ?: ""
        val sourceId = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_ID) ?: ""
        AlarmPlugin.fire(context, rc, title, preset, body, kind, fullScreen, sourceType, sourceId)
        // Full-screen long preset: constant sound + vibration, repeat every
        // minute until resolved, capped at 30 minutes.
        val norm = AlarmPlugin.normalizePreset(preset)
        if (kind == "alarm" && norm == "full_long") {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val count = intent.getIntExtra("repeatCount", 0)
            if (count < 30) {
                val repeatIntent = Intent(context, AlarmReceiver::class.java).apply {
                    putExtra(AlarmPlugin.EXTRA_REQUEST_CODE, rc)
                    putExtra(AlarmPlugin.EXTRA_TITLE, title)
                    putExtra(AlarmPlugin.EXTRA_PRESET, preset)
                    putExtra(AlarmPlugin.EXTRA_BODY, body)
                    putExtra(AlarmPlugin.EXTRA_KIND, kind)
                    putExtra(AlarmPlugin.EXTRA_FULL_SCREEN, fullScreen)
                    putExtra(AlarmPlugin.EXTRA_SOURCE_TYPE, sourceType)
                    putExtra(AlarmPlugin.EXTRA_SOURCE_ID, sourceId)
                    putExtra("repeatCount", count + 1)
                }
                val repeat = PendingIntent.getBroadcast(
                    context, rc,
                    repeatIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 60000, repeat
                )
            }
        }
    }
}

/** Snooze, dismiss, and fallback done actions work without launching the app.
 *  Done/+1 for task and habit sources are launched via MainActivity so Dart
 *  can complete the underlying source reliably. */
class AlarmActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_SNOOZE = "com.spotnik.ephemeron.SNOOZE"
        const val ACTION_DONE = "com.spotnik.ephemeron.DONE"
        const val ACTION_DISMISS = "com.spotnik.ephemeron.DISMISS"
        const val ACTION_PLUS_ONE = "com.spotnik.ephemeron.PLUS_ONE"
        const val SNOOZE_MINUTES = 10
    }

    override fun onReceive(context: Context, intent: Intent) {
        val rc = intent.getIntExtra(AlarmPlugin.EXTRA_REQUEST_CODE, intent.getIntExtra("requestCode", -1))
        if (rc < 0) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as android.app.NotificationManager
        nm.cancel(rc)
        try { AlarmRingService.stop(context, rc) } catch (_: Exception) {}
        val row = AlarmStore.rowForRequestCode(context, rc)
        val title = intent.getStringExtra(AlarmPlugin.EXTRA_TITLE) ?: row?.title ?: "Alarm"
        val preset = intent.getStringExtra(AlarmPlugin.EXTRA_PRESET) ?: row?.preset ?: "notification"
        val body = intent.getStringExtra(AlarmPlugin.EXTRA_BODY) ?: ""
        val kind = intent.getStringExtra(AlarmPlugin.EXTRA_KIND) ?: row?.kind ?: "alarm"
        val fullScreen = intent.getBooleanExtra(AlarmPlugin.EXTRA_FULL_SCREEN, kind == "alarm" && AlarmPlugin.usesFullScreen(preset))
        val sourceType = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_TYPE) ?: row?.sourceType ?: ""
        val sourceId = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_ID) ?: row?.sourceId ?: ""
        when (intent.action) {
            ACTION_SNOOZE -> {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val fireAt = System.currentTimeMillis() + SNOOZE_MINUTES * 60000L
                val fire = PendingIntent.getBroadcast(
                    context, rc,
                    Intent(context, AlarmReceiver::class.java).apply {
                        putExtra(AlarmPlugin.EXTRA_REQUEST_CODE, rc)
                        putExtra(AlarmPlugin.EXTRA_TITLE, title)
                        putExtra(AlarmPlugin.EXTRA_PRESET, preset)
                        putExtra(AlarmPlugin.EXTRA_BODY, body)
                        putExtra(AlarmPlugin.EXTRA_KIND, kind)
                        putExtra(AlarmPlugin.EXTRA_FULL_SCREEN, fullScreen)
                        putExtra(AlarmPlugin.EXTRA_SOURCE_TYPE, sourceType)
                        putExtra(AlarmPlugin.EXTRA_SOURCE_ID, sourceId)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, fire)
                AlarmStore.upsert(context, rc, fireAt)
            }
            ACTION_DISMISS, ACTION_DONE -> {
                AlarmStore.markState(context, rc, if (intent.action == ACTION_DISMISS) "dismissed" else "done")
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val stale = PendingIntent.getBroadcast(
                    context, rc, Intent(context, AlarmReceiver::class.java),
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (stale != null) am.cancel(stale)
            }
        }
    }
}
