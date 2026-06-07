package com.dangeremergence.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.dangeremergence.security.SecurityProvider
import java.util.HashMap

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.dangeremergence/security"
    private val EVENT_CHANNEL = "com.dangeremergence/mesh_data"

    private var meshEventSink: EventChannel.EventSink? = null
    private var meshReceiver: BroadcastReceiver? = null
    private lateinit var securityProvider: SecurityProvider

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize the security provider with application context
        securityProvider = SecurityProvider(applicationContext)

        // ── MethodChannel Implementation ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                // First try the dedicated SecurityProvider
                if (!securityProvider.handleMethodCall(call, result)) {
                    // If SecurityProvider didn't handle it, try local handlers
                    handleMethodCall(call, result)
                }
            }

        // ── EventChannel Implementation (Mesh Data Loopback) ────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
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
    }

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

    /**
     * Handle method calls not handled by SecurityProvider.
     * Currently empty as all security methods are handled by SecurityProvider.
     * Reserved for future local-only method channel handlers.
     */
    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        result.notImplemented()
    }
}
