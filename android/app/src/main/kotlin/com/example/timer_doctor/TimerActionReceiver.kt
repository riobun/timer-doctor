package com.example.timer_doctor

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives notification action button taps and writes the action id into
 * Flutter's SharedPreferences so the background-service actionPoller can pick
 * it up within one second.
 *
 * Flutter's shared_preferences plugin stores values under the key prefix
 * "flutter." inside the "FlutterSharedPreferences" file.
 */
class TimerActionReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_ACTION_ID = "action_id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val actionId = intent.getStringExtra(EXTRA_ACTION_ID) ?: return
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        prefs.edit().putString("flutter.pending_action", actionId).apply()
        // Dismiss the notification immediately on button tap
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(1)
    }
}
