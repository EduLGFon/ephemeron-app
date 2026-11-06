package com.spotnik.ephemeron

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var systemChannel: MethodChannel? = null
    private var pendingSharedText: String? = null
    private var pendingShortcut: String? = null
    private var pendingWidgetAction: String? = null
    private var pendingNotifResult: MethodChannel.Result? = null
    private var pendingAlarmAction: String? = null

    // Home-widget taps arrive as ephemeron://widget/... intents targeted at
    // this activity. The Flutter engine would otherwise treat the intent
    // data as the initial route and show the router error page; the action
    // itself is delivered to Dart through getWidgetAction instead.
    override fun getInitialRoute(): String? {
        val data = intent?.data
        if (data?.scheme == "ephemeron" && data.host == "widget") return null
        return super.getInitialRoute()
    }

    companion object {
        private const val NOTIF_REQUEST_CODE = 1001
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIF_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            // areNotificationsEnabled covers the user turning notifications
            // off in settings even when the runtime permission is granted.
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            pendingNotifResult?.success(granted && nm.areNotificationsEnabled())
            pendingNotifResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmPlugin.registerWith(flutterEngine, this)
        systemChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "ephemeron/system",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    val text = pendingSharedText
                    pendingSharedText = null
                    result.success(text)
                }
                "getLaunchAction" -> {
                    val action = pendingShortcut
                    pendingShortcut = null
                    result.success(action)
                }
                "getWidgetAction" -> {
                    val action = pendingWidgetAction
                    pendingWidgetAction = null
                    result.success(action)
                }
                "getAlarmAction" -> {
                    val action = pendingAlarmAction
                    pendingAlarmAction = null
                    result.success(action)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("ARG", "no url", null)
                    } else {
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                },
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "hasDndAccess" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        result.success(nm.isNotificationPolicyAccessGranted)
                    } else {
                        result.success(true)
                    }
                }
                "openDndSettings" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        startActivity(
                            Intent(
                                android.provider.Settings
                                    .ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS,
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                        )
                    }
                    result.success(null)
                }
                "setDnd" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (Build.VERSION.SDK_INT >= 23) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        if (nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(
                                if (enabled) {
                                    NotificationManager.INTERRUPTION_FILTER_ALARMS
                                } else {
                                    NotificationManager.INTERRUPTION_FILTER_ALL
                                },
                            )
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "startFocusChronometer" -> {
                    val title = call.argument<String>("title") ?: "Focus session"
                    val startUtc = call.argument<Number>("startUtcMs")?.toLong()
                        ?: System.currentTimeMillis()
                    AlarmPlugin.notifyChannels(this)
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                        as NotificationManager
                    val contentIntent = android.app.PendingIntent.getActivity(
                        this, 900001,
                        Intent(this, MainActivity::class.java),
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE,
                    )
                    val notification = NotificationCompat.Builder(this, "focus_ongoing")
                        .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                        .setContentTitle(title)
                        .setContentText("Focusing")
                        .setOngoing(true)
                        .setShowWhen(true)
                        .setUsesChronometer(true)
                        .setWhen(startUtc)
                        .setContentIntent(contentIntent)
                        .build()
                    nm.notify(900001, notification)
                    result.success(null)
                }
                "stopFocusChronometer" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                        as NotificationManager
                    nm.cancel(900001)
                    result.success(null)
                }
                "canPostNotifications" -> {
                    if (Build.VERSION.SDK_INT < 33) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        result.success(nm.areNotificationsEnabled())
                    } else {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        result.success(granted && nm.areNotificationsEnabled())
                    }
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT < 33) {
                        result.success(true)
                    } else if (pendingNotifResult != null) {
                        result.error("BUSY", "request already in flight", null)
                    } else {
                        pendingNotifResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                            NOTIF_REQUEST_CODE,
                        )
                    }
                }
                "openAppSettings" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                "openFullScreenSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 34) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.fromParts("package", packageName, null),
                                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                            )
                        } else {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null),
                                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                            )
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        // A warm widget tap does not always produce a Flutter lifecycle
        // resume event, so push the pending action to Dart immediately.
        val widget = pendingWidgetAction
        if (widget != null && systemChannel != null) {
            pendingWidgetAction = null
            systemChannel?.invokeMethod("widgetAction", widget)
        }
        val alarm = pendingAlarmAction
        if (alarm != null && systemChannel != null) {
            pendingAlarmAction = null
            systemChannel?.invokeMethod("alarmAction", alarm)
        }
    }

    private fun handleIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrEmpty()) pendingSharedText = text
        }
        intent.getStringExtra("shortcut")?.let { pendingShortcut = it }
        intent.getStringExtra("focusNext")?.let { next ->
            if (next == "break" || next == "focus") {
                pendingWidgetAction = "focus_start_$next"
            }
        }
        intent.data?.let { uri ->
            if (uri.scheme == "ephemeron" && uri.host == "widget") {
                // Preserve the full action path so day links such as
                // calendar/2026-11-03 survive the trip to Dart.
                pendingWidgetAction = uri.pathSegments.joinToString("/")
            }
        }
        val alarmAction = intent.getStringExtra("alarm_action")
        if (!alarmAction.isNullOrEmpty()) {
            val rc = intent.getIntExtra(AlarmPlugin.EXTRA_REQUEST_CODE, intent.getIntExtra("requestCode", -1))
            val sourceType = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_TYPE) ?: ""
            val sourceId = intent.getStringExtra(AlarmPlugin.EXTRA_SOURCE_ID) ?: ""
            pendingAlarmAction = "$alarmAction|$rc|$sourceType|$sourceId"
            if (rc >= 0) {
                try {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(rc)
                    AlarmRingService.stop(this, rc)
                } catch (_: Exception) {}
            }
        }
    }
}
