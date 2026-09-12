package com.example.virusdownloader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }

        // Check if auto-start is enabled in Flutter shared preferences
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val settingsJson = prefs.getString("flutter.vdownloader_settings", null)

        var autoStart = false
        var runInBackground = false

        if (settingsJson != null) {
            try {
                val json = JSONObject(settingsJson)
                autoStart = json.optBoolean("autoStartOnBoot", false)
                runInBackground = json.optBoolean("runInBackground", false)
            } catch (_: Exception) {}
        }

        if (autoStart) {
            if (runInBackground) {
                DownloadForegroundService.start(context)
            } else {
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (launchIntent != null) {
                    context.startActivity(launchIntent)
                }
            }
        }
    }
}

