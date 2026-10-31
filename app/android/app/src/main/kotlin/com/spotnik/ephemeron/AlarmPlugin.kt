package com.spotnik.ephemeron

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Registers ephemeron/alarms channel. Only entry point for OS scheduling. */
class AlarmPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "ephemeron/alarms"

        /** Current preset ids: notification, full_short, full_long.
         * Legacy ids (light/medium/strong/constant/habit/focus) still map. */
        fun normalizePreset(raw: String): String {
            return when (raw) {
                "notification", "full_short", "full_long" -> raw
                "light", "habit", "focus" -> "notification"
                "medium", "strong" -> "full_short"
                "constant" -> "full_long"
                else -> "notification"
            }
        }

        fun usesFullScreen(preset: String): Boolean =
            normalizePreset(preset) != "notification"

        fun registerWith(engine: FlutterEngine, context: Context) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(AlarmPlugin(context))
        }

        fun notifyChannels(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val presets = listOf(
                "notification", "full_short", "full_long",
                "light", "medium", "strong", "constant", "habit", "focus"
            )
            for (p in presets) {
                val norm = normalizePreset(p)
                val importance = when (norm) {
                    "notification" -> NotificationManager.IMPORTANCE_DEFAULT
                    else -> NotificationManager.IMPORTANCE_HIGH
                }
                nm.createNotificationChannel(
                    NotificationChannel("alarm_$p", "Alarm $p", importance).apply {
                        if (norm == "full_long") {
                            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                            enableVibration(true)
                            vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 1000)
                        } else if (norm == "full_short") {
                            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                        }
                    }
                )
            }
            nm.createNotificationChannel(
                NotificationChannel(
                    "focus_ongoing", "Focus timer",
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        fun fire(context: Context, requestCode: Int, title: String, preset: String, body: String = "", kind: String = "alarm", fullScreen: Boolean = true) {
            notifyChannels(context)
            val norm = normalizePreset(preset)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val contentIntent = PendingIntent.getActivity(
                context, requestCode,
                Intent(context, MainActivity::class.java).apply {
                    putExtra("ring", true)
                    putExtra("requestCode", requestCode)
                    putExtra("title", title)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val snoozeIntent = PendingIntent.getBroadcast(
                context, requestCode,
                Intent(context, AlarmActionReceiver::class.java).apply {
                    action = AlarmActionReceiver.ACTION_SNOOZE
                    putExtra("requestCode", requestCode)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val doneIntent = PendingIntent.getBroadcast(
                context, requestCode + 500000,
                Intent(context, AlarmActionReceiver::class.java).apply {
                    action = AlarmActionReceiver.ACTION_DONE
                    putExtra("requestCode", requestCode)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val isReminder = kind == "reminder"
            // Reminders and the notification preset never use full-screen:
            // plain notification with short sound. Full-screen presets use
            // fullScreenIntent; Android shows a heads-up notification instead
            // while the phone is in use.
            val wantFullScreen = !isReminder && fullScreen && usesFullScreen(norm)
            val defaults = when {
                isReminder || norm == "notification" -> NotificationCompat.DEFAULT_SOUND
                norm == "full_short" -> NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE
                else -> NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE
            }
            val text = when {
                body.isNotEmpty() -> body
                isReminder -> "Reminder"
                norm == "full_long" -> "Alarm - long sound"
                norm == "full_short" -> "Alarm"
                else -> "Notification"
            }
            val builder = NotificationCompat.Builder(context, "alarm_$norm")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(text)
                .setPriority(
                    if (wantFullScreen) NotificationCompat.PRIORITY_MAX
                    else NotificationCompat.PRIORITY_HIGH
                )
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(defaults)
                .setContentIntent(contentIntent)
                .setAutoCancel(!wantFullScreen)
                .setOngoing(wantFullScreen)
                .addAction(android.R.drawable.ic_menu_recent_history, "Snooze 10 min", snoozeIntent)
                .addAction(android.R.drawable.ic_menu_agenda, "Done", doneIntent)
            if (wantFullScreen) {
                builder.setFullScreenIntent(contentIntent, true)
            }
            nm.notify(requestCode, builder.build())
            AlarmStore.markState(context, requestCode, "fired")
        }
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(true)
            "schedule" -> {
                val rc = call.argument<Int>("requestCode") ?: return result.error("ARG", "no code", null)
                val at = call.argument<Number>("fireAtUtcMs")?.toLong()
                    ?: return result.error("ARG", "no time", null)
                val useClock = call.argument<Boolean>("useAlarmClock") ?: false
                val title = call.argument<String>("title") ?: "Alarm"
                val body = call.argument<String>("body") ?: ""
                val preset = call.argument<String>("preset") ?: "notification"
                val kind = call.argument<String>("kind") ?: "alarm"
                val fullScreen = call.argument<Boolean>("fullScreen")
                    ?: usesFullScreen(preset)
                schedule(rc, at, useClock, title, preset, body, kind, fullScreen)
                result.success(null)
            }
            "cancel" -> {
                val rc = call.argument<Int>("requestCode") ?: return result.error("ARG", "no code", null)
                cancel(rc)
                result.success(null)
            }
            "cancelAll" -> {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                for (rc in AlarmStore.requestCodes(context)) cancel(rc)
                result.success(null)
            }
            "canScheduleExact" -> {
                if (Build.VERSION.SDK_INT >= 31) {
                    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    result.success(am.canScheduleExactAlarms())
                } else {
                    result.success(true)
                }
            }
            "openExactAlarmSettings" -> {
                if (Build.VERSION.SDK_INT >= 31) {
                    context.startActivity(Intent(
                        android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                }
                result.success(null)
            }
            "openBatterySettings" -> {
                context.startActivity(Intent(
                    android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun schedule(rc: Int, at: Long, useClock: Boolean, title: String, preset: String, body: String = "", kind: String = "alarm", fullScreen: Boolean = true) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = PendingIntent.getBroadcast(
            context, rc,
            Intent(context, AlarmReceiver::class.java).apply {
                putExtra("requestCode", rc)
                putExtra("title", title)
                putExtra("preset", preset)
                putExtra("body", body)
                putExtra("kind", kind)
                putExtra("fullScreen", fullScreen)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (useClock) {
            val showIntent = PendingIntent.getActivity(
                context, rc,
                Intent(context, MainActivity::class.java).apply { putExtra("ring", true) },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, showIntent), intent)
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
        AlarmStore.upsert(context, rc, at)
    }

    private fun cancel(rc: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = PendingIntent.getBroadcast(
            context, rc, Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (intent != null) am.cancel(intent)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(rc)
        AlarmStore.markState(context, rc, "cancelled")
    }
}

/** Reads/writes the alarms_index table directly so reboot recovery works
 *  without a Dart engine. Writes only scheduler state, never user content. */
object AlarmStore {
    private fun dbFile(context: Context): File {
        return context.getDatabasePath("ephemeron_db")
            ?: File(context.filesDir, "ephemeron_db")
    }

    fun upsert(context: Context, requestCode: Int, fireAt: Long) {
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile(context).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.execSQL(
                "UPDATE alarms_index SET fire_at_utc = ?, state = 'scheduled' WHERE request_code = ?",
                arrayOf<Any>(fireAt, requestCode)
            )
            db.close()
        } catch (_: Exception) {
        }
    }

    fun markState(context: Context, requestCode: Int, state: String) {
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile(context).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.execSQL(
                "UPDATE alarms_index SET state = ? WHERE request_code = ?",
                arrayOf<Any>(state, requestCode)
            )
            db.close()
        } catch (_: Exception) {
        }
    }

    fun requestCodes(context: Context): List<Int> {
        val out = mutableListOf<Int>()
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile(context).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )
            val c = db.rawQuery(
                "SELECT request_code FROM alarms_index WHERE state = 'scheduled' AND request_code IS NOT NULL",
                null
            )
            while (c.moveToNext()) out.add(c.getInt(0))
            c.close()
            db.close()
        } catch (_: Exception) {
        }
        return out
    }

    fun dueAlarms(context: Context, nowMs: Long): List<Triple<Int, Long, String>> {
        val out = mutableListOf<Triple<Int, Long, String>>()
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile(context).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            val c = db.rawQuery(
                "SELECT request_code, fire_at_utc, source_id FROM alarms_index WHERE state = 'scheduled' AND fire_at_utc <= ?",
                arrayOf(nowMs.toString())
            )
            while (c.moveToNext()) {
                out.add(Triple(c.getInt(0), c.getLong(1), c.getString(2) ?: "Alarm"))
            }
            c.close()
            db.close()
        } catch (_: Exception) {
        }
        return out
    }

    fun rescheduleAll(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for ((rc, at, title) in dueAlarms(context, Long.MAX_VALUE)) {
            if (at <= System.currentTimeMillis()) {
                markState(context, rc, "missed")
                continue
            }
            val intent = PendingIntent.getBroadcast(
                context, rc,
                Intent(context, AlarmReceiver::class.java).apply {
                    putExtra("requestCode", rc)
                    putExtra("title", title)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }
}
