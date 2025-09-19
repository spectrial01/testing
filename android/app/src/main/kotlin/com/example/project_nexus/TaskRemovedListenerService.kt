package com.example.project_nexus

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

class TaskRemovedListenerService : Service() {

    override fun onBind(intent: Intent): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent) {
        Log.d("TaskRemovedListener", "TASK REMOVED - Checking if service should restart...")

        // ENHANCED: Check if background service was permanently disabled during logout
        val sharedPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isPermanentlyDisabled = sharedPrefs.getBoolean("flutter.background_service_permanently_disabled", false)
        val disableTimestamp = sharedPrefs.getLong("flutter.background_service_disable_timestamp", 0)
        val currentTime = System.currentTimeMillis()

        // ENHANCED: Also check if user is logged out by checking for credentials
        val hasToken = sharedPrefs.getString("flutter.token", null) != null
        val hasDeploymentCode = sharedPrefs.getString("flutter.deploymentCode", null) != null
        val isLoggedIn = hasToken && hasDeploymentCode

        // If service was disabled OR user is logged out, don't restart
        if (isPermanentlyDisabled && (currentTime - disableTimestamp) < 600000) {
            Log.d("TaskRemovedListener", "🚫 Service permanently disabled, NOT restarting!")
            stopSelf()
            super.onTaskRemoved(rootIntent)
            return
        }

        if (!isLoggedIn) {
            Log.d("TaskRemovedListener", "🚫 User not logged in, NOT restarting service!")
            stopSelf()
            super.onTaskRemoved(rootIntent)
            return
        }

        Log.d("TaskRemovedListener", "✅ Service not disabled and user logged in, restarting Flutter service...")

        // This code restarts your flutter_background_service
        val intent = Intent(this, BackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
}
