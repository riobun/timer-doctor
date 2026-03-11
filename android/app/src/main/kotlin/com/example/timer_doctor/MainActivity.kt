package com.example.timer_doctor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "timer_doctor/overlay"
    private var windowManager: WindowManager? = null
    private var overlayView: TextView? = null
    // Current style (so we can rebuild overlay if needed)
    private var curFontSize = 14f
    private var curTextColor = Color.WHITE
    private var curBgColor = Color.parseColor("#141414")
    private var curBgAlpha = (0.5f * 255).toInt()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 电池优化豁免 channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.timer_doctor/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestIgnoreBatteryOptimizations") {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !pm.isIgnoringBatteryOptimizations(packageName)
                    ) {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                        )
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // 原生通知 channel：绕过 flutter_local_notifications 的 action button 机制，
        // 直接用 BroadcastReceiver 响应按钮点击，写入 SharedPreferences 供 actionPoller 读取。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_doctor/notification")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showTimerComplete" -> {
                        val snoozeMinutes = call.argument<Int>("snoozeMinutes") ?: 5
                        showTimerCompleteNotification(snoozeMinutes)
                        result.success(null)
                    }
                    "cancelTimerNotification" -> {
                        cancelTimerNotification()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val text = call.argument<String>("text") ?: ""
                        showOverlay(text)
                        result.success(null)
                    }
                    "hide" -> {
                        hideOverlay()
                        result.success(null)
                    }
                    "updateText" -> {
                        val text = call.argument<String>("text") ?: ""
                        overlayView?.let {
                            it.text = text
                            it.isSelected = true   // restart marquee after text change
                        }
                        result.success(null)
                    }
                    "updateStyle" -> {
                        val fontSize = call.argument<Double>("fontSize") ?: 14.0
                        val textColorRaw = call.getLong("textColor", 0xFFFFFFFFL)
                        val bgColorRaw = call.getLong("bgColor", 0xFF141414L)
                        val bgOpacity = call.argument<Double>("bgOpacity") ?: 0.5

                        curFontSize = fontSize.toFloat()
                        curTextColor = argbLongToColor(textColorRaw)
                        curBgColor = argbLongToColor(bgColorRaw)
                        curBgAlpha = (bgOpacity * 255).toInt()

                        applyStyleToView(overlayView)
                        result.success(null)
                    }
                    "checkPermission" -> {
                        result.success(canDrawOverlays())
                    }
                    "requestPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                Settings.canDrawOverlays(this)

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
        }
    }

    private fun showOverlay(text: String) {
        if (!canDrawOverlays()) return
        hideOverlay()

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        // Marquee triggers only when text overflows the view width.
        // Cap the view at 82% of screen width; WRAP_CONTENT below the cap.
        val maxW = (resources.displayMetrics.widthPixels * 0.82).toInt()

        val tv = TextView(applicationContext).apply {
            this.text = text
            gravity = Gravity.CENTER
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1   // loop forever
            isSelected = true         // triggers marquee on non-focused views
            maxWidth = maxW
        }
        applyStyleToView(tv)
        overlayView = tv

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = 80
        }

        tv.setOnTouchListener(object : View.OnTouchListener {
            private var startRawX = 0f
            private var startRawY = 0f
            private var startParamX = 0
            private var startParamY = 0

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startRawX = event.rawX
                        startRawY = event.rawY
                        startParamX = params.x
                        startParamY = params.y
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = startParamX + (event.rawX - startRawX).toInt()
                        params.y = startParamY + (event.rawY - startRawY).toInt()
                        wm.updateViewLayout(v, params)
                    }
                }
                return true
            }
        })

        wm.addView(tv, params)
    }

    private fun hideOverlay() {
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
            overlayView = null
        }
    }

    private fun applyStyleToView(tv: TextView?) {
        tv ?: return
        tv.setTextColor(curTextColor)
        tv.textSize = curFontSize
        tv.setPadding(
            dpToPx(12), dpToPx(5),
            dpToPx(12), dpToPx(5)
        )
        tv.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(100).toFloat()
            setColor(curBgColor)
            alpha = curBgAlpha
        }
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).toInt()

    // Flutter encodes large ints (>INT32_MAX) as Long, smaller ones as Int.
    private fun MethodCall.getLong(key: String, default: Long): Long =
        when (val v = argument<Any>(key)) {
            is Int  -> v.toLong()
            is Long -> v
            else    -> default
        }

    // Extract RGB from ARGB long (ignore original alpha; opacity is separate).
    private fun argbLongToColor(argb: Long): Int {
        val r = ((argb shr 16) and 0xFF).toInt()
        val g = ((argb shr 8) and 0xFF).toInt()
        val b = (argb and 0xFF).toInt()
        return Color.rgb(r, g, b)
    }

    // ── 原生 Timer-Complete 通知 ────────────────────────────────────────────────

    private val kTimerNotifChannelId = "timer_doctor_channel"
    private val kTimerNotifId = 1

    private fun showTimerCompleteNotification(snoozeMinutes: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 确保 channel 存在（高优先级，可弹出）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                kTimerNotifChannelId,
                "Timer Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { enableVibration(true) }
            nm.createNotificationChannel(ch)
        }

        fun broadcastIntent(actionId: String): PendingIntent {
            val intent = Intent(this, TimerActionReceiver::class.java).apply {
                putExtra(TimerActionReceiver.EXTRA_ACTION_ID, actionId)
            }
            return PendingIntent.getBroadcast(
                this, actionId.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val notification = NotificationCompat.Builder(this, kTimerNotifChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⏰ 时间到！")
            .setContentText("休息一下，或者继续专注？")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .addAction(0, "立刻开始", broadcastIntent("action_start_now"))
            .addAction(0, "休息 $snoozeMinutes 分钟", broadcastIntent("action_snooze"))
            .build()

        nm.notify(kTimerNotifId, notification)
    }

    private fun cancelTimerNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(kTimerNotifId)
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }
}
