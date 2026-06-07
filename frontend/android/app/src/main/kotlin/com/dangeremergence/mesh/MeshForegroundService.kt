package com.dangeremergence.mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.IOException
import java.util.UUID

/**
 * Foreground service for maintaining mesh network connectivity.
 *
 * This service runs in the foreground with a persistent notification
 * to prevent the OS from killing it during mesh communication.
 * It manages Bluetooth RFCOMM server sockets for peer discovery
 * and data relay within the mesh network.
 */
class MeshForegroundService : Service() {
    companion object {
        private const val TAG = "MeshForegroundService"
        private const val CHANNEL_ID = "mesh_foreground_channel"
        private const val NOTIFICATION_ID = 1001
        private const val SERVICE_UUID = "00001101-0000-1000-8000-00805F9B34FB"
        private const val SERVICE_NAME = "DangerEmergenceMesh"

        // RFCOMM server socket for incoming connections
        private var serverSocket: BluetoothServerSocket? = null
        private var isRunning = false
    }

    private lateinit var powerManager: PowerManager
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        powerManager = getSystemService(POWER_SERVICE) as PowerManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Mesh foreground service starting...")

        // Acquire partial wake lock to keep CPU awake for mesh processing
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "DangerEmergence:MeshWakeLock"
        )
        wakeLock?.acquire(30 * 60 * 1000L) // 30 minute timeout

        // Build foreground notification
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)

        // Start Bluetooth server socket in background thread
        if (!isRunning) {
            isRunning = true
            Thread(null, { runBluetoothServer() }, "MeshBluetoothServer").start()
        }

        // Restart if killed
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.e(TAG, "Error closing server socket", e)
        }
        wakeLock?.release()
        Log.d(TAG, "Mesh foreground service destroyed")
    }

    /**
     * Runs a Bluetooth RFCOMM server socket that accepts incoming
     * mesh peer connections and relays data.
     */
    private fun runBluetoothServer() {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            Log.w(TAG, "Bluetooth not available or not enabled")
            isRunning = false
            return
        }

        try {
            // Listen for incoming RFCOMM connections using SPP UUID
            serverSocket = bluetoothAdapter.listenUsingRfcommWithServiceRecord(
                SERVICE_NAME,
                UUID.fromString(SERVICE_UUID)
            )

            Log.d(TAG, "Bluetooth server socket listening...")

            while (isRunning) {
                try {
                    val socket: BluetoothSocket = serverSocket!!.accept()
                    Log.d(TAG, "Accepted connection from: ${socket.remoteDevice.address}")

                    // Handle the connection in a new thread
                    Thread(null, {
                        handleBluetoothConnection(socket)
                    }, "MeshConnection-${socket.remoteDevice.address}").start()

                } catch (e: IOException) {
                    if (isRunning) {
                        Log.e(TAG, "Error accepting Bluetooth connection", e)
                    }
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Error creating Bluetooth server socket", e)
        } finally {
            try {
                serverSocket?.close()
            } catch (e: IOException) {
                // Ignore
            }
            isRunning = false
        }
    }

    /**
     * Handles an incoming Bluetooth connection by reading data
     * from the input stream and relaying it to the Flutter engine
     * via a platform channel (or local broadcast).
     */
    private fun handleBluetoothConnection(socket: BluetoothSocket) {
        val device = socket.remoteDevice
        val inputStream = socket.inputStream
        val buffer = ByteArray(4096)

        try {
            while (isRunning && socket.isConnected) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead > 0) {
                    val data = buffer.copyOf(bytesRead)
                    Log.d(TAG, "Received ${bytesRead} bytes from ${device.address}")

                    // TODO: Relay data to Flutter via MethodChannel or EventChannel
                    // For now, we log the receipt. The Flutter-side MeshManager
                    // will poll or receive via a callback mechanism.
                    onMeshDataReceived(device.address, data)
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Connection error with ${device.address}", e)
        } finally {
            try {
                socket.close()
            } catch (e: IOException) {
                // Ignore
            }
        }
    }

    /**
     * Callback when mesh data is received over Bluetooth.
     * Broadcasts an intent to the MainActivity to be picked up by the EventChannel.
     */
    private fun onMeshDataReceived(deviceAddress: String, data: ByteArray) {
        val intent = Intent("com.dangeremergence.MESH_DATA_RECEIVED").apply {
            putExtra("address", deviceAddress)
            putExtra("data", data)
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d(TAG, "Broadcast mesh data from $deviceAddress: ${data.size} bytes")
    }

    /**
     * Creates the notification channel for Android 8.0+.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mesh Network Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Maintains mesh network connectivity for emergency communication"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Builds the persistent foreground notification.
     */
    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Danger Emergence")
            .setContentText("Mesh network active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
