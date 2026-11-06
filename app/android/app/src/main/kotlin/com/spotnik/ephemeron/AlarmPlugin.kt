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
        const val EXTRA_REQUEST_CODE = "requestCode"
        const val EXTRA_TITLE = "title"
        const val EXTRA_PRESET = "preset"
        const val EXTRA_BODY = "body"
        const val EXTRA_KIND = "kind"
        const val EXTRA_FULL_SCREEN = "fullScreen"
        const val EXTRA_SOURCE_TYPE = "sourceType"
        const val EXTRA_SOURCE_ID = "sourceId"
        const val EXTRA_PHASE = "phase"

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

        fun baseSourceId(sourceId: String): String {
            val at = sourceId.indexOf('@')
            if (at >= 0) return sourceId.substring(0, at)
            val hash = sourceId.indexOf('#')
            return if (hash >= 0) sourceId.substring(0, hash) else sourceId
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

        private fun putAlarmExtras(
            intent: Intent,
            requestCode: Int,
            title: String,
            preset: String,
            body: String = "",
            kind: String = "alarm",
            fullScreen: Boolean = true,
            sourceType: String = "",
            sourceId: String = "",
            phase: String? = null,
        ) {
            intent.putExtra(EXTRA_REQUEST_CODE, requestCode)
            intent.putExtra(EXTRA_TITLE, title)
            intent.putExtra(EXTRA_PRESET, preset)
            intent.putExtra(EXTRA_BODY, body)
            intent.putExtra(EXTRA_KIND, kind)
            intent.putExtra(EXTRA_FULL_SCREEN, fullScreen)
            intent.putExtra(EXTRA_SOURCE_TYPE, sourceType)
            intent.putExtra(EXTRA_SOURCE_ID, sourceId)
            if (phase != null) intent.putExtra(EXTRA_PHASE, phase)
        }

        private fun isNumericGoalHabit(context: Context, sourceType: String, sourceId: String): Boolean {
            if (sourceType != "habit" && sourceType != "habit_reminder") return false
            val base = baseSourceId(sourceId)
            if (base.isEmpty()) return false
            return AlarmStore.habitGoalAmount(context, base) > 0.0
        }

        fun buildNotification(
            context: Context,
            requestCode: Int,
            title: String,
            preset: String,
            body: String = "",
            kind: String = "alarm",
            fullScreen: Boolean = true,
            sourceType: String = "",
            sourceId: String = "",
            phase: String? = null,
        ): android.app.Notification {
            val norm = normalizePreset(preset)
            val contentIntent = PendingIntent.getActivity(
                context, requestCode,
                Intent(context, MainActivity::class.java).apply {
                    putExtra("ring", true)
                    putExtra(EXTRA_REQUEST_CODE, requestCode)
                    putExtra(EXTRA_TITLE, title)
                    putExtra(EXTRA_SOURCE_TYPE, sourceType)
                    putExtra(EXTRA_SOURCE_ID, sourceId)
                    putExtra(EXTRA_KIND, kind)
                    if (phase != null) putExtra(EXTRA_PHASE, phase)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            fun broadcastAction(action: String, codeOffset: Int): PendingIntent {
                return PendingIntent.getBroadcast(
                    context, requestCode + codeOffset,
                    Intent(context, AlarmActionReceiver::class.java).apply {
                        this.action = action
                        putAlarmExtras(this, requestCode, title, preset, body, kind, fullScreen, sourceType, sourceId, phase)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            fun activityAction(action: String, codeOffset: Int): PendingIntent {
                return PendingIntent.getActivity(
                    context, requestCode + codeOffset,
                    Intent(context, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        putExtra("alarm_action", action)
                        putAlarmExtras(this, requestCode, title, preset, body, kind, fullScreen, sourceType, sourceId, phase)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val snoozeIntent = broadcastAction(AlarmActionReceiver.ACTION_SNOOZE, 0)
            val dismissIntent = broadcastAction(AlarmActionReceiver.ACTION_DISMISS, 700000)
            val doneBroadcast = broadcastAction(AlarmActionReceiver.ACTION_DONE, 500000)
            val isReminder = kind == "reminder"
            val wantFullScreen = !isReminder && fullScreen && usesFullScreen(norm)
            val defaults = when {
                isReminder || norm == "notification" -> NotificationCompat.DEFAULT_SOUND
                else -> NotificationCompat.DEFAULT_VIBRATE
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

            val st = sourceType
            val isTask = st == "task" || st == "task_reminder" || st == "task_due_tomorrow"
            val isHabit = st == "habit" || st == "habit_reminder"
            val isFocus = st == "focus" || st == "focus_reminder"
            when {
                isFocus -> {
                    if (!isReminder) {
                        val nextPhase = if (phase == "break") "focus" else "break"
                        val nextLabel = if (nextPhase == "break") "Start break" else "Start focus"
                        val nextIntent = PendingIntent.getActivity(
                            context, requestCode + 900000,
                            Intent(context, MainActivity::class.java).apply {
                                putExtra("focusNext", nextPhase)
                                putExtra("sourceId", sourceId)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            },
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        builder.addAction(android.R.drawable.ic_media_play, nextLabel, nextIntent)
                    }
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
                isTask -> {
                    builder.addAction(android.R.drawable.ic_menu_agenda, "Done", activityAction(AlarmActionReceiver.ACTION_DONE, 500000))
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
                isHabit && isNumericGoalHabit(context, st, sourceId) -> {
                    builder.addAction(android.R.drawable.ic_input_add, "+1", activityAction(AlarmActionReceiver.ACTION_PLUS_ONE, 800000))
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
                isHabit -> {
                    builder.addAction(android.R.drawable.ic_menu_agenda, "Done", activityAction(AlarmActionReceiver.ACTION_DONE, 500000))
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
                st.startsWith("event") || st.startsWith("countdown") -> {
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
                else -> {
                    builder.addAction(android.R.drawable.ic_menu_recent_history, "Snooze 10 min", snoozeIntent)
                    builder.addAction(android.R.drawable.ic_menu_agenda, "Done", doneBroadcast)
                    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissIntent)
                }
            }
            if (wantFullScreen) {
                builder.setFullScreenIntent(contentIntent, true)
            }
            return builder.build()
        }

        fun fire(
            context: Context,
            requestCode: Int,
            title: String,
            preset: String,
            body: String = "",
            kind: String = "alarm",
            fullScreen: Boolean = true,
            sourceType: String = "",
            sourceId: String = "",
            phase: String? = null,
        ) {
            notifyChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(
                requestCode,
                buildNotification(
                    context, requestCode, title, preset, body, kind, fullScreen,
                    sourceType, sourceId, phase,
                )
            )
            AlarmStore.markState(context, requestCode, "fired")
            AlarmRingService.start(context, requestCode, title, preset, body, kind, fullScreen, sourceType, sourceId)
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
                val sourceType = call.argument<String>("sourceType") ?: ""
                val sourceId = call.argument<String>("sourceId") ?: ""
                val phase = call.argument<String>("phase")
                val kind = call.argument<String>("kind") ?: "alarm"
                val fullScreen = call.argument<Boolean>("fullScreen")
                    ?: usesFullScreen(preset)
                schedule(rc, at, useClock, title, preset, body, kind, fullScreen, sourceType, sourceId, phase)
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

    private fun schedule(
        rc: Int, at: Long, useClock: Boolean, title: String, preset: String,
        body: String = "", kind: String = "alarm", fullScreen: Boolean = true,
        sourceType: String = "", sourceId: String = "", phase: String? = null,
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = PendingIntent.getBroadcast(
            context, rc,
            Intent(context, AlarmReceiver::class.java).apply {
                putAlarmExtras(this, rc, title, preset, body, kind, fullScreen, sourceType, sourceId, phase)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (useClock) {
            val showIntent = PendingIntent.getActivity(
                context, rc,
                Intent(context, MainActivity::class.java).apply {
                    putExtra("ring", true)
                    putExtra(EXTRA_REQUEST_CODE, rc)
                    putExtra(EXTRA_TITLE, title)
                    putExtra(EXTRA_SOURCE_TYPE, sourceType)
                    putExtra(EXTRA_SOURCE_ID, sourceId)
                    putExtra(EXTRA_KIND, kind)
                    if (phase != null) putExtra(EXTRA_PHASE, phase)
                },
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
        AlarmRingService.stop(context, rc)
        AlarmStore.markState(context, rc, "cancelled")
    }
}

data class AlarmIndexRow(
    val requestCode: Int,
    val fireAtUtc: Long,
    val title: String,
    val sourceType: String,
    val sourceId: String,
    val kind: String,
    val preset: String,
)

object AlarmStore {
    private fun dbFile(context: Context): File {
        return context.getDatabasePath("ephemeron_db")
            ?: File(context.filesDir, "ephemeron_db")
    }

    private fun openOrNull(context: Context, readOnly: Boolean): android.database.sqlite.SQLiteDatabase? {
        return try {
            val file = dbFile(context)
            if (!file.exists()) return null
            android.database.sqlite.SQLiteDatabase.openDatabase(
                file.path, null,
                if (readOnly) android.database.sqlite.SQLiteDatabase.OPEN_READONLY
                else android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
        } catch (_: Exception) {
            null
        }
    }

    fun upsert(context: Context, requestCode: Int, fireAt: Long) {
        val db = openOrNull(context, false) ?: return
        try {
            db.execSQL(
                "UPDATE alarms_index SET fire_at_utc = ?, state = 'scheduled' WHERE request_code = ?",
                arrayOf<Any>(fireAt, requestCode)
            )
        } catch (_: Exception) {
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    fun markState(context: Context, requestCode: Int, state: String) {
        val db = openOrNull(context, false) ?: return
        try {
            db.execSQL(
                "UPDATE alarms_index SET state = ? WHERE request_code = ?",
                arrayOf<Any>(state, requestCode)
            )
        } catch (_: Exception) {
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    fun requestCodes(context: Context): List<Int> {
        val out = mutableListOf<Int>()
        val db = openOrNull(context, true) ?: return out
        try {
            val c = db.rawQuery(
                "SELECT request_code FROM alarms_index WHERE state = 'scheduled' AND request_code IS NOT NULL",
                null
            )
            while (c.moveToNext()) out.add(c.getInt(0))
            c.close()
        } catch (_: Exception) {
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
        return out
    }

    fun rowForRequestCode(context: Context, requestCode: Int): AlarmIndexRow? {
        val db = openOrNull(context, true) ?: return null
        try {
            val c = db.rawQuery(
                "SELECT request_code, fire_at_utc, title, source_type, source_id, kind, preset FROM alarms_index WHERE request_code = ? LIMIT 1",
                arrayOf(requestCode.toString())
            )
            val row = if (c.moveToNext()) {
                AlarmIndexRow(
                    requestCode = c.getInt(0),
                    fireAtUtc = c.getLong(1),
                    title = c.getString(2) ?: "Alarm",
                    sourceType = c.getString(3) ?: "",
                    sourceId = c.getString(4) ?: "",
                    kind = c.getString(5) ?: "alarm",
                    preset = c.getString(6) ?: "notification",
                )
            } else null
            c.close()
            return row
        } catch (_: Exception) {
            return null
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    fun habitGoalAmount(context: Context, habitId: String): Double {
        val db = openOrNull(context, true) ?: return 0.0
        try {
            val c = db.rawQuery(
                "SELECT goal_amount FROM habits WHERE id = ? LIMIT 1",
                arrayOf(habitId)
            )
            val v = if (c.moveToNext() && !c.isNull(0)) c.getDouble(0) else 0.0
            c.close()
            return v
        } catch (_: Exception) {
            return 0.0
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    fun dueAlarms(context: Context, nowMs: Long): List<Triple<Int, Long, String>> {
        val out = mutableListOf<Triple<Int, Long, String>>()
        val db = openOrNull(context, true) ?: return out
        try {
            val c = db.rawQuery(
                "SELECT request_code, fire_at_utc, title FROM alarms_index WHERE state = 'scheduled' AND fire_at_utc <= ?",
                arrayOf(nowMs.toString())
            )
            while (c.moveToNext()) {
                out.add(Triple(c.getInt(0), c.getLong(1), c.getString(2) ?: "Alarm"))
            }
            c.close()
        } catch (_: Exception) {
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
        return out
    }

    fun scheduledRows(context: Context): List<AlarmIndexRow> {
        val out = mutableListOf<AlarmIndexRow>()
        val db = openOrNull(context, true) ?: return out
        try {
            val c = db.rawQuery(
                "SELECT request_code, fire_at_utc, title, source_type, source_id, kind, preset FROM alarms_index WHERE state = 'scheduled' AND request_code IS NOT NULL",
                null
            )
            while (c.moveToNext()) {
                out.add(
                    AlarmIndexRow(
                        requestCode = c.getInt(0),
                        fireAtUtc = c.getLong(1),
                        title = c.getString(2) ?: "Alarm",
                        sourceType = c.getString(3) ?: "",
                        sourceId = c.getString(4) ?: "",
                        kind = c.getString(5) ?: "alarm",
                        preset = c.getString(6) ?: "notification",
                    )
                )
            }
            c.close()
        } catch (_: Exception) {
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
        return out
    }

    fun rescheduleAll(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (row in scheduledRows(context)) {
            if (row.fireAtUtc <= now) {
                markState(context, row.requestCode, "missed")
                continue
            }
            try {
                val fullScreen = row.kind == "alarm" && AlarmPlugin.usesFullScreen(row.preset)
                val intent = PendingIntent.getBroadcast(
                    context, row.requestCode,
                    Intent(context, AlarmReceiver::class.java).apply {
                        putExtra(AlarmPlugin.EXTRA_REQUEST_CODE, row.requestCode)
                        putExtra(AlarmPlugin.EXTRA_TITLE, row.title)
                        putExtra(AlarmPlugin.EXTRA_PRESET, row.preset)
                        putExtra(AlarmPlugin.EXTRA_BODY, "")
                        putExtra(AlarmPlugin.EXTRA_KIND, row.kind)
                        putExtra(AlarmPlugin.EXTRA_FULL_SCREEN, fullScreen)
                        putExtra(AlarmPlugin.EXTRA_SOURCE_TYPE, row.sourceType)
                        putExtra(AlarmPlugin.EXTRA_SOURCE_ID, row.sourceId)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, row.fireAtUtc, intent)
            } catch (_: Exception) {
            }
        }
    }
}
