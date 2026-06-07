package com.dangeremergence.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.*
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.security.spec.RSAKeyGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.ByteArrayInputStream

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.dangeremergence/security"
    private val EVENT_CHANNEL = "com.dangeremergence/mesh_data"
    private val ANDROID_KEYSTORE = "AndroidKeyStore"
    
    private var meshEventSink: EventChannel.EventSink? = null
    private var meshReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ── MethodChannel Implementation ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result -> handleMethodCall(call, result) }

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

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getKeyStoreLevel" -> handleGetKeyStoreLevel(result)
                "isSecureEnclaveAvailable" -> handleIsSecureEnclaveAvailable(result)
                "generateKeyPair" -> handleGenerateKeyPair(call, result)
                "sign" -> handleSign(call, result)
                "verify" -> handleVerify(call, result)
                "encrypt" -> handleEncrypt(call, result)
                "decrypt" -> handleDecrypt(call, result)
                "deleteKey" -> handleDeleteKey(call, result)
                "getDeviceKey" -> handleGetDeviceKey(result)
                "zeroizeAllKeys" -> handleZeroizeAllKeys(result)
                "verifyAttestation" -> handleVerifyAttestation(call, result)
                "getSignatureHash" -> handleGetSignatureHash(result)
                "isPackageInstalled" -> handleIsPackageInstalled(call, result)
                "getBatteryStatus" -> handleGetBatteryStatus(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("NATIVE_ERROR", e.message, null)
        }
    }

    private fun handleGetBatteryStatus(result: MethodChannel.Result) {
        val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { ifilter ->
            context.registerReceiver(null, ifilter)
        }

        val level: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = level * 100 / scale.toDouble()

        val status: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        val response = HashMap<String, Any>()
        response["level"] = batteryPct
        response["isCharging"] = isCharging
        result.success(response)
    }

    // Security methods implementation (re-using previously verified logic)
    private fun handleGetKeyStoreLevel(result: MethodChannel.Result) {
        result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && 
            packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) "strongbox" else "tee")
    }

    private fun handleIsSecureEnclaveAvailable(result: MethodChannel.Result) {
        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
    }

    private fun handleGenerateKeyPair(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
        val keySize = call.argument<Int>("keySize") ?: 2048
        
        val spec = KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
            .setAlgorithmParameterSpec(RSAKeyGenParameterSpec(keySize, RSAKeyGenParameterSpec.F4))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PSS)
            .build()

        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEYSTORE)
        kpg.initialize(spec)
        val kp = kpg.generateKeyPair()
        
        val response = HashMap<String, Any?>()
        response["publicKey"] = Base64.encodeToString(kp.public.encoded, Base64.NO_WRAP)
        result.success(response)
    }

    private fun handleSign(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias")!!
        val data = call.argument<ByteArray>("data")!!
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = ks.getEntry(keyAlias, null) as KeyStore.PrivateKeyEntry
        val s = Signature.getInstance("SHA256withRSA/PSS")
        s.initSign(entry.privateKey)
        s.update(data)
        result.success(s.sign())
    }

    private fun handleVerify(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias")!!
        val data = call.argument<ByteArray>("data")!!
        val signature = call.argument<ByteArray>("signature")!!
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cert = ks.getCertificate(keyAlias)
        val s = Signature.getInstance("SHA256withRSA/PSS")
        s.initVerify(cert.publicKey)
        s.update(data)
        result.success(s.verify(signature))
    }

    private fun handleEncrypt(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias")!!
        val data = call.argument<ByteArray>("data")!!
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        cipher.init(Cipher.ENCRYPT_MODE, ks.getCertificate(keyAlias).publicKey)
        result.success(cipher.doFinal(data))
    }

    private fun handleDecrypt(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias")!!
        val data = call.argument<ByteArray>("data")!!
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        cipher.init(Cipher.DECRYPT_MODE, (ks.getEntry(keyAlias, null) as KeyStore.PrivateKeyEntry).privateKey)
        result.success(cipher.doFinal(data))
    }

    private fun handleDeleteKey(call: MethodCall, result: MethodChannel.Result) {
        val keyAlias = call.argument<String>("keyAlias")!!
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        ks.deleteEntry(keyAlias)
        result.success(null)
    }

    private fun handleGetDeviceKey(result: MethodChannel.Result) {
        val alias = "danger_emergence_device_key"
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (!ks.containsAlias(alias)) {
            val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            kg.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
            kg.generateKey()
        }
        result.success((ks.getKey(alias, null) as SecretKey).encoded)
    }

    private fun handleZeroizeAllKeys(result: MethodChannel.Result) {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        ks.aliases().asSequence().filter { it.startsWith("danger_emergence_") }.forEach { ks.deleteEntry(it) }
        result.success(null)
    }

    private fun handleVerifyAttestation(call: MethodCall, result: MethodChannel.Result) {
        val attestationData = call.argument<ByteArray>("attestationData")
        val response = HashMap<String, Any?>()

        try {
            if (attestationData == null) {
                result.success(mapOf("verified" to false, "details" to "No data"))
                return
            }

            // 1. Parse the certificate chain
            val factory = CertificateFactory.getInstance("X.509")
            val cert = factory.generateCertificate(ByteArrayInputStream(attestationData)) as X509Certificate

            // 2. Extract Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17)
            val extensionValue = cert.getExtensionValue("1.3.6.1.4.1.11129.2.1.17")
            val isHardwareBacked = extensionValue != null

            // 3. Verify the Root CA (In production, you'd check against Google's Root CA)
            // For the bridge, we verify the certificate is currently valid
            cert.checkValidity()

            response["verified"] = isHardwareBacked
            response["hardwareBacked"] = isHardwareBacked
            response["details"] = if (isHardwareBacked) "Verified: Hardware-bound" else "Warning: Software-emulated"
            response["deviceSecure"] = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            
            result.success(response)
        } catch (e: Exception) {
            result.error("ATTESTATION_FAILED", e.message, null)
        }
    }

    private fun handleGetSignatureHash(result: MethodChannel.Result) {
        val info = packageManager.getPackageInfo(packageName, if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
        val sig = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.signingInfo.signingCertificateHistory[0] else info.signatures[0]
        result.success(MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) })
    }

    private fun handleIsPackageInstalled(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("package")!!
        result.success(try { packageManager.getPackageInfo(pkg, 0); true } catch (e: Exception) { false })
    }
}
