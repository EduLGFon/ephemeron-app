package com.spotnik.ephemeron

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import java.io.File

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
