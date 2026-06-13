package com.dangeremergence.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.dangeremergence.security.SecurityProvider
import com.dangeremergence.location.LocationService
import java.util.HashMap

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_SECURITY = "com.dangeremergence/security"
        private const val CHANNEL_LOCATION = "com.dangeremergence/location"
        private const val CHANNEL_MESH = "com.dangeremergence/mesh"
        private const val CHANNEL_DEVICE = "com.dangeremergence/device"
        private const val EVENT_MESH_DATA = "com.dangeremergence/mesh_data"
        private const val EVENT_LOCATION = "com.dangeremergence/location_updates"
        private const val EVENT_HARDWARE_TRIGGERS = "com.dangeremergence/hardware_triggers"
        private const val PANIC_EVENT = "panic_sequence_detected"

        // Volume button panic detection: both buttons pressed within this window (ms)
        private const val PANIC_WINDOW_MS = 500L
    }

    private var meshEventSink: EventChannel.EventSink? = null
    private var locationEventSink: EventChannel.EventSink? = null
    private var hardwareEventSink: EventChannel.EventSink? = null
    private var meshReceiver: BroadcastReceiver? = null
    private var hardwareReceiver: BroadcastReceiver? = null
    private lateinit var securityProvider: SecurityProvider

    // Volume button panic detection state
    private var lastVolumeUpTime = 0L
    private var lastVolumeDownTime = 0L
    private var volumePressCount = 0
    private var firstVolumePressTime = 0L

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize the security provider with application context
        securityProvider = SecurityProvider(applicationContext)

        // ── Security MethodChannel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SECURITY)
            .setMethodCallHandler { call, result ->
                if (!securityProvider.handleMethodCall(call, result)) {
                    handleMethodCall(call, result)
                }
            }

        // ── Location MethodChannel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_LOCATION)
            .setMethodCallHandler { call, result ->
                handleLocationCall(call, result)
            }

        // ── Mesh MethodChannel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MESH)
            .setMethodCallHandler { call, result ->
                handleMeshCall(call, result)
            }

        // ── Device Info MethodChannel ───────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_DEVICE)
            .setMethodCallHandler { call, result ->
                handleDeviceCall(call, result)
            }

        // ── Mesh Data EventChannel ──────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_MESH_DATA)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    meshEventSink = events
                    registerMeshReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterMeshReceiver()
                    meshEventSink = null
                }
            })

        // ── Location Updates EventChannel ───────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_LOCATION)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    locationEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    locationEventSink = null
                }
            })

        // ── Hardware Triggers EventChannel (Stealth Mode SOS) ────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_HARDWARE_TRIGGERS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    hardwareEventSink = events
                    registerHardwareReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterHardwareReceiver()
                    hardwareEventSink = null
                }
            })
    }

    // ── Location Channel Handlers ────────────────────────────────────────────

    private fun handleLocationCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTracking" -> {
                val sosMode = call.argument<Boolean>("sosMode") ?: false
                val intent = Intent(this, LocationService::class.java).apply {
                    putExtra("sos_mode", sosMode)
                    action = "START_TRACKING"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                result.success(true)
            }
            "stopTracking" -> {
                val intent = Intent(this, LocationService::class.java).apply {
                    action = "STOP_TRACKING"
                }
                startService(intent)
                result.success(true)
            }
            "getTrackingStatus" -> {
                result.success(LocationService.isRunning)
            }
            "updateInterval" -> {
                val intervalMs = call.argument<Long>("intervalMs") ?: 30000L
                val intent = Intent(this, LocationService::class.java).apply {
                    putExtra("interval_ms", intervalMs)
                    action = "UPDATE_INTERVAL"
                }
                startService(intent)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ── Mesh Channel Handlers ────────────────────────────────────────────────

    private fun handleMeshCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMeshService" -> {
                val intent = Intent(this, com.dangeremergence.mesh.MeshForegroundService::class.java).apply {
                    action = "START_MESH"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                result.success(true)
            }
            "stopMeshService" -> {
                val intent = Intent(this, com.dangeremergence.mesh.MeshForegroundService::class.java).apply {
                    action = "STOP_MESH"
                }
                startService(intent)
                result.success(true)
            }
            "sendMeshData" -> {
                val deviceAddress = call.argument<String>("deviceAddress")
                val data = call.argument<ByteArray>("data")
                if (deviceAddress != null && data != null) {
                    val intent = Intent("com.dangeremergence.SEND_MESH_DATA").apply {
                        putExtra("address", deviceAddress)
                        putExtra("data", data)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "deviceAddress and data required", null)
                }
            }
            "getConnectedPeers" -> {
                // Return connected peers from mesh service
                result.success(listOf<String>())
            }
            else -> result.notImplemented()
        }
    }

    // ── Device Info Channel Handlers ─────────────────────────────────────────

    private fun handleDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBatteryLevel" -> {
                val batteryStatus = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                    registerReceiver(null, filter)
                }
                val level = batteryStatus?.getIntExtra("level", -1) ?: -1
                val scale = batteryStatus?.getIntExtra("scale", -1) ?: -1
                val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else -1
                result.success(batteryPct)
            }
            "isCharging" -> {
                val batteryStatus = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                    registerReceiver(null, filter)
                }
                val status = batteryStatus?.getIntExtra("status", -1) ?: -1
                val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == android.os.BatteryManager.BATTERY_STATUS_FULL
                result.success(isCharging)
            }
            "isPowerSaverMode" -> {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                val isPowerSaveMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    powerManager.isPowerSaveMode
                } else false
                result.success(isPowerSaveMode)
            }
            "getDeviceInfo" -> {
                val info = HashMap<String, Any?>()
                info["manufacturer"] = Build.MANUFACTURER
                info["model"] = Build.MODEL
                info["androidVersion"] = Build.VERSION.RELEASE
                info["sdkInt"] = Build.VERSION.SDK_INT
                info["device"] = Build.DEVICE
                info["product"] = Build.PRODUCT
                result.success(info)
            }
            else -> result.notImplemented()
        }
    }

    // ── Mesh Receiver ────────────────────────────────────────────────────────

    private fun registerMeshReceiver() {
        if (meshReceiver == null) {
            meshReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    val address = intent?.getStringExtra("address")
                    val data = intent?.getByteArrayExtra("data")

                    val event = HashMap<String, Any?>()
                    event["address"] = address
                    event["data"] = data

                    meshEventSink?.success(event)
                }
            }
            val filter = IntentFilter("com.dangeremergence.MESH_DATA_RECEIVED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(meshReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(meshReceiver, filter)
            }
        }
    }

    private fun unregisterMeshReceiver() {
        meshReceiver?.let {
            unregisterReceiver(it)
            meshReceiver = null
        }
    }

    // ── Hardware Trigger Receiver (Stealth Mode SOS) ─────────────────────────

    private fun registerHardwareReceiver() {
        if (hardwareReceiver == null) {
            hardwareReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        "com.dangeremergence.PANIC_TRIGGERED" -> {
                            hardwareEventSink?.success(PANIC_EVENT)
                        }
                    }
                }
            }
            val filter = IntentFilter("com.dangeremergence.PANIC_TRIGGERED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(hardwareReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(hardwareReceiver, filter)
            }
        }
    }

    private fun unregisterHardwareReceiver() {
        hardwareReceiver?.let {
            unregisterReceiver(it)
            hardwareReceiver = null
        }
    }

    /**
     * Detect volume button panic sequence (Volume Up + Volume Down pressed
     * simultaneously, or 5 rapid presses of either volume button within 2 seconds).
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val now = System.currentTimeMillis()

        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                // Check if Volume Down was pressed within the panic window
                if (now - lastVolumeDownTime < PANIC_WINDOW_MS) {
                    triggerPanic()
                    return true
                }
                lastVolumeUpTime = now
                trackVolumePress(now)
                return true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                // Check if Volume Up was pressed within the panic window
                if (now - lastVolumeUpTime < PANIC_WINDOW_MS) {
                    triggerPanic()
                    return true
                }
                lastVolumeDownTime = now
                trackVolumePress(now)
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    /**
     * Track rapid volume button presses (5 presses within 2 seconds triggers panic).
     */
    private fun trackVolumePress(now: Long) {
        if (now - firstVolumePressTime > 2000) {
            // Reset counter if more than 2 seconds have passed
            volumePressCount = 1
            firstVolumePressTime = now
        } else {
            volumePressCount++
            if (volumePressCount >= 5) {
                triggerPanic()
                volumePressCount = 0
            }
        }
    }

    /**
     * Trigger panic SOS by sending a broadcast that the hardware receiver picks up,
     * which then forwards the event to Flutter via the EventChannel.
     */
    private fun triggerPanic() {
        val panicIntent = Intent("com.dangeremergence.PANIC_TRIGGERED")
        sendBroadcast(panicIntent)
        // Also directly notify the sink if already listening
        hardwareEventSink?.success(PANIC_EVENT)
    }

    /**
     * Handle method calls not handled by SecurityProvider.
     * Reserved for future local-only method channel handlers.
     */
    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        result.notImplemented()
    }
}
