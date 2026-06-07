package com.dangeremergence.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Broadcast receiver that restarts the mesh foreground service
 * after a device reboot.
 *
 * This ensures the mesh network service is always running,
 * even after the device is restarted.
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Device boot completed — restarting mesh foreground service")

            try {
                val serviceIntent = Intent(context, com.dangeremergence.mesh.MeshForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.d(TAG, "Mesh foreground service started after boot")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start mesh service after boot", e)
            }
        }
    }
}
