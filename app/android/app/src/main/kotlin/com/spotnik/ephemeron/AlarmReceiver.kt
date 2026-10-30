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
        val rc = intent.getIntExtra("requestCode", -1)
        if (rc < 0) return
        val title = intent.getStringExtra("title") ?: "Alarm"
        val preset = intent.getStringExtra("preset") ?: "medium"
        AlarmPlugin.fire(context, rc, title, preset)
        if (preset == "constant") {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val count = intent.getIntExtra("repeatCount", 0)
            if (count < 30) {
                val repeatIntent = Intent(context, AlarmReceiver::class.java).apply {
                    putExtra("requestCode", rc)
                    putExtra("title", title)
                    putExtra("preset", preset)
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

/** Snooze and Done actions work without launching the app. */
class AlarmActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_SNOOZE = "com.spotnik.ephemeron.SNOOZE"
        const val ACTION_DONE = "com.spotnik.ephemeron.DONE"
        const val SNOOZE_MINUTES = 10
    }

    override fun onReceive(context: Context, intent: Intent) {
        val rc = intent.getIntExtra("requestCode", -1)
        if (rc < 0) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as android.app.NotificationManager
        nm.cancel(rc)
        when (intent.action) {
            ACTION_SNOOZE -> {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val fireAt = System.currentTimeMillis() + SNOOZE_MINUTES * 60000L
                val fire = PendingIntent.getBroadcast(
                    context, rc,
                    Intent(context, AlarmReceiver::class.java).apply {
                        putExtra("requestCode", rc)
                        putExtra("title", "Snoozed alarm")
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, fire)
                AlarmStore.upsert(context, rc, fireAt)
            }
            ACTION_DONE -> {
                AlarmStore.markState(context, rc, "done")
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
