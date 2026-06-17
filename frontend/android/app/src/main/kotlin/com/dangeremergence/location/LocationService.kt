package com.dangeremergence.location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.view.FlutterCallbackInformation
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Foreground service for continuous background location tracking
 * during SOS events and mesh network operations.
 *
 * This service runs with a persistent notification to prevent the OS
 * from killing it during critical location tracking scenarios.
 * It provides location updates via EventChannel to the Dart layer.
 */
class LocationService : Service() {

    companion object {
        private const val TAG = "LocationService"
        private const val CHANNEL_ID = "location_foreground_channel"
        private const val NOTIFICATION_ID = 1002

        // Location update intervals
        private const val UPDATE_INTERVAL_MS = 5000L       // 5 seconds normal
        private const val FASTEST_INTERVAL_MS = 2000L      // 2 seconds when moving
        private const val SOS_UPDATE_INTERVAL_MS = 1000L   // 1 second during SOS
        private const val MIN_DISTANCE_METERS = 5f          // 5 meters

        // Event channel for streaming location updates to Dart
        const val LOCATION_EVENT_CHANNEL = "com.dangeremergence/location_updates"

        // Actions
        const val ACTION_START_SOS_TRACKING = "com.dangeremergence.action.START_SOS_TRACKING"
        const val ACTION_STOP_SOS_TRACKING = "com.dangeremergence.action.STOP_SOS_TRACKING"
        const val ACTION_UPDATE_INTERVAL = "com.dangeremergence.action.UPDATE_INTERVAL"

        // Extras
        const val EXTRA_UPDATE_INTERVAL = "update_interval_ms"
        const val EXTRA_IS_SOS_MODE = "is_sos_mode"
        const val EXTRA_IS_COVERT_MODE = "is_covert_mode"

        // Current state
        var isRunning = false
            private set
        var isSosMode = false
            private set
        var isCovertMode = false
            private set
        var currentLocation: Location? = null
            private set

        // Event sink for streaming location to Dart
        var locationEventSink: EventChannel.EventSink? = null
            internal set
    }

    private lateinit var locationManager: LocationManager
    private lateinit var powerManager: PowerManager
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentIntervalMs: Long = UPDATE_INTERVAL_MS
    private val scheduler = Executors.newSingleThreadScheduledExecutor()

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            currentLocation = location
            broadcastLocation(location)
        }

        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
            Log.d(TAG, "Location provider $provider status changed to $status")
        }

        override fun onProviderEnabled(provider: String) {
            Log.d(TAG, "Location provider $provider enabled")
        }

        override fun onProviderDisabled(provider: String) {
            Log.d(TAG, "Location provider $provider disabled")
            // Try to use another provider
            trySwitchProvider()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        powerManager = getSystemService(POWER_SERVICE) as PowerManager
        Log.d(TAG, "Location service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_SOS_TRACKING -> {
                val isSos = intent.getBooleanExtra(EXTRA_IS_SOS_MODE, false)
                val isCovert = intent.getBooleanExtra(EXTRA_IS_COVERT_MODE, false)
                startTracking(isSos, isCovert)
            }
            ACTION_STOP_SOS_TRACKING -> {
                stopTracking()
            }
            ACTION_UPDATE_INTERVAL -> {
                val interval = intent.getLongExtra(EXTRA_UPDATE_INTERVAL, UPDATE_INTERVAL_MS)
                updateInterval(interval)
            }
            else -> {
                // Default: start with normal tracking
                if (!isRunning) {
                    startTracking(false)
                }
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopTracking()
        scheduler.shutdown()
        Log.d(TAG, "Location service destroyed")
    }

    /**
     * Start location tracking in foreground.
     */
    private fun startTracking(sosMode: Boolean, covertMode: Boolean = false) {
        if (isRunning) return

        isRunning = true
        isSosMode = sosMode
        isCovertMode = covertMode
        currentIntervalMs = if (sosMode) SOS_UPDATE_INTERVAL_MS else UPDATE_INTERVAL_MS

        // Acquire wake lock for consistent location updates
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "DangerEmergence:LocationWakeLock"
        )
        wakeLock?.acquire(10 * 60 * 1000L) // 10 minute timeout

        // Build foreground notification
        val notification = buildNotification(sosMode, covertMode)
        startForeground(NOTIFICATION_ID, notification)

        // Register location listeners
        registerLocationListeners()

        Log.d(TAG, "Location tracking started (sosMode=$sosMode, interval=${currentIntervalMs}ms)")
    }

    /**
     * Stop location tracking and remove foreground state.
     */
    private fun stopTracking() {
        if (!isRunning) return

        isRunning = false
        isSosMode = false
        isCovertMode = false

        // Remove location listeners
        try {
            locationManager.removeUpdates(locationListener)
        } catch (e: SecurityException) {
            Log.w(TAG, "Failed to remove location updates", e)
        }

        // Release wake lock
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null

        // Stop foreground and notification
        stopForeground(true)

        // Notify Dart layer that tracking stopped
        val stoppedData = HashMap<String, Any?>()
        stoppedData["event"] = "tracking_stopped"
        stoppedData["timestamp"] = System.currentTimeMillis()
        locationEventSink?.success(stoppedData)

        Log.d(TAG, "Location tracking stopped")
    }

    /**
     * Update the location update interval.
     */
    private fun updateInterval(intervalMs: Long) {
        if (!isRunning) return

        currentIntervalMs = intervalMs.coerceIn(1000L, 60000L)

        // Re-register listeners with new interval
        try {
            locationManager.removeUpdates(locationListener)
        } catch (e: SecurityException) {
            Log.w(TAG, "Failed to remove updates during interval change", e)
        }
        registerLocationListeners()

        Log.d(TAG, "Location update interval changed to ${currentIntervalMs}ms")
    }

    /**
     * Register location listeners with the best available provider.
     */
    private fun registerLocationListeners() {
        try {
            // Try GPS first (most accurate)
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    currentIntervalMs,
                    MIN_DISTANCE_METERS,
                    locationListener
                )
                Log.d(TAG, "GPS location listener registered")
            }

            // Also register for Network provider (fallback, less accurate)
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    currentIntervalMs * 2, // Less frequent for network
                    MIN_DISTANCE_METERS * 2,
                    locationListener
                )
                Log.d(TAG, "Network location listener registered")
            }

            // Get last known location immediately
            val lastGps = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val lastNetwork = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            val bestLocation = lastGps ?: lastNetwork
            if (bestLocation != null) {
                currentLocation = bestLocation
                broadcastLocation(bestLocation)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission not granted", e)
            val errorData = HashMap<String, Any?>()
            errorData["event"] = "permission_error"
            errorData["message"] = "Location permission not granted"
            locationEventSink?.error("PERMISSION_DENIED", "Location permission not granted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register location listeners", e)
        }
    }

    /**
     * Try to switch to an alternative location provider if current one fails.
     */
    private fun trySwitchProvider() {
        try {
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    currentIntervalMs,
                    MIN_DISTANCE_METERS,
                    locationListener
                )
                Log.d(TAG, "Switched to Network provider")
            } else if (locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.PASSIVE_PROVIDER,
                    currentIntervalMs,
                    MIN_DISTANCE_METERS,
                    locationListener
                )
                Log.d(TAG, "Switched to Passive provider")
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Failed to switch provider", e)
        }
    }

    /**
     * Broadcast a location update to the Dart layer via EventChannel.
     */
    private fun broadcastLocation(location: Location) {
        val locationData = HashMap<String, Any?>()
        locationData["event"] = "location_update"
        locationData["latitude"] = location.latitude
        locationData["longitude"] = location.longitude
        locationData["accuracy"] = location.accuracy.toDouble()
        locationData["altitude"] = location.altitude
        locationData["speed"] = location.speed.toDouble()
        locationData["bearing"] = location.bearing.toDouble()
        locationData["timestamp"] = location.time
        locationData["provider"] = location.provider
        locationData["isSosMode"] = isSosMode

        // Add battery-safe flag for power-aware inference
        locationData["isCharging"] = isDeviceCharging()

        locationEventSink?.success(locationData)
    }

    /**
     * Check if the device is currently charging.
     */
    private fun isDeviceCharging(): Boolean {
        try {
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { ifilter ->
                registerReceiver(null, ifilter)
            }
            val status: Int = batteryStatus?.getIntExtra(
                android.os.BatteryManager.EXTRA_STATUS, -1
            ) ?: -1
            return status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == android.os.BatteryManager.BATTERY_STATUS_FULL
        } catch (e: Exception) {
            return false
        }
    }

    // ──────────────────────────────────────────────
    // Notification
    // ──────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background location tracking for SOS and mesh services"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(sosMode: Boolean, covertMode: Boolean = false): Notification {
        val title = when {
            covertMode -> "📍 Location Service Active"
            sosMode -> "🚨 SOS Active — Tracking Location"
            else -> "📍 Location Tracking"
        }
        val description = when {
            covertMode -> "Background location tracking active."
            sosMode -> "Emergency services can see your location. Updates every second."
            else -> "Background location tracking for mesh network and zone alerts."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(description)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
