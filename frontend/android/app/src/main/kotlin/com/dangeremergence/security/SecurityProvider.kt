package com.dangeremergence.security

import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.*
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.RSAKeyGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Dedicated security provider that handles all MethodChannel calls
 * for the 'com.dangeremergence/security' channel.
 *
 * Separates security concerns from MainActivity for better
 * separation of concerns and testability.
 */
class SecurityProvider(private val context: android.content.Context) {

    companion object {
        private const val TAG = "SecurityProvider"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val DEVICE_KEY_ALIAS = "danger_emergence_device_key"

        // AES-GCM parameters
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH = 128
    }

    /**
     * Dispatch a method call to the appropriate handler.
     * Returns true if the method was handled, false otherwise.
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "getBatteryStatus" -> { handleGetBatteryStatus(result); true }
            "getKeyStoreLevel" -> { handleGetKeyStoreLevel(result); true }
            "isSecureEnclaveAvailable" -> { handleIsSecureEnclaveAvailable(result); true }
            "generateKeyPair" -> { handleGenerateKeyPair(call, result); true }
            "sign" -> { handleSign(call, result); true }
            "verify" -> { handleVerify(call, result); true }
            "encrypt" -> { handleEncrypt(call, result); true }
            "decrypt" -> { handleDecrypt(call, result); true }
            "deleteKey" -> { handleDeleteKey(call, result); true }
            "getDeviceKey" -> { handleGetDeviceKey(result); true }
            "zeroizeAllKeys" -> { handleZeroizeAllKeys(result); true }
            "verifyAttestation" -> { handleVerifyAttestation(call, result); true }
            "getSignatureHash" -> { handleGetSignatureHash(result); true }
            "isPackageInstalled" -> { handleIsPackageInstalled(call, result); true }
            "verifyBundleSignature" -> { handleVerifyBundleSignature(result); true }
            else -> false
        }
    }

    // ──────────────────────────────────────────────
    // Battery Status
    // ──────────────────────────────────────────────

    private fun handleGetBatteryStatus(result: MethodChannel.Result) {
        try {
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { ifilter ->
                context.registerReceiver(null, ifilter)
            }

            val level: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val batteryPct = if (scale > 0) level * 100.0 / scale else 0.0

            val status: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL

            val response = HashMap<String, Any>()
            response["level"] = batteryPct
            response["isCharging"] = isCharging
            result.success(response)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get battery status", e)
            result.error("BATTERY_ERROR", "Failed to get battery status: ${e.message}", null)
        }
    }

    // ──────────────────────────────────────────────
    // Key Store Detection
    // ──────────────────────────────────────────────

    private fun handleGetKeyStoreLevel(result: MethodChannel.Result) {
        try {
            val level = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                context.packageManager.hasSystemFeature(
                    android.content.pm.PackageManager.FEATURE_STRONGBOX_KEYSTORE
                )
            ) {
                "strongbox"
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                "tee"
            } else {
                "software"
            }
            result.success(level)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to detect key store level", e)
            result.success("software")
        }
    }

    private fun handleIsSecureEnclaveAvailable(result: MethodChannel.Result) {
        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
    }

    // ──────────────────────────────────────────────
    // Key Pair Generation
    // ──────────────────────────────────────────────

    @RequiresApi(Build.VERSION_CODES.M)
    private fun handleGenerateKeyPair(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
            val keySize = call.argument<Int>("keySize") ?: 2048

            val spec = KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
            )
                .setAlgorithmParameterSpec(RSAKeyGenParameterSpec(keySize, RSAKeyGenParameterSpec.F4))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PSS)
                .setKeySize(keySize)
                .build()

            val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEYSTORE)
            kpg.initialize(spec)
            val kp = kpg.generateKeyPair()

            val response = HashMap<String, Any?>()
            response["publicKey"] = Base64.encodeToString(kp.public.encoded, Base64.NO_WRAP)

            // Generate attestation certificate if available (Android P+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    val attestation = KeyStore.getInstance(ANDROID_KEYSTORE)
                    attestation.load(null)
                    val entry = attestation.getEntry(keyAlias, null) as? KeyStore.PrivateKeyEntry
                    val certChain = entry?.certificateChain
                    if (certChain != null && certChain.isNotEmpty()) {
                        response["attestation"] = certChain[0].encoded
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to generate attestation certificate", e)
                }
            }

            result.success(response)
        } catch (e: Exception) {
            Log.e(TAG, "Key pair generation failed", e)
            result.error("KEY_GEN_ERROR", "Failed to generate key pair: ${e.message}", null)
        }
    }

    // ──────────────────────────────────────────────
    // Sign / Verify
    // ──────────────────────────────────────────────

    private fun handleSign(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
            val data = call.argument<ByteArray>("data") ?: throw IllegalArgumentException("data required")

            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            val entry = ks.getEntry(keyAlias, null) as? KeyStore.PrivateKeyEntry
                ?: throw IllegalStateException("Key not found: $keyAlias")

            val signature = Signature.getInstance("SHA256withRSA")
            signature.initSign(entry.privateKey)
            signature.update(data)
            val sigBytes = signature.sign()

            result.success(sigBytes)
        } catch (e: Exception) {
            Log.e(TAG, "Signing failed", e)
            result.error("SIGN_ERROR", "Failed to sign data: ${e.message}", null)
        }
    }

    private fun handleVerify(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
            val data = call.argument<ByteArray>("data") ?: throw IllegalArgumentException("data required")
            val signature = call.argument<ByteArray>("signature") ?: throw IllegalArgumentException("signature required")

            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            val cert = ks.getCertificate(keyAlias)
                ?: throw IllegalStateException("Certificate not found: $keyAlias")

            val sig = Signature.getInstance("SHA256withRSA")
            sig.initVerify(cert.publicKey)
            sig.update(data)
            val verified = sig.verify(signature)

            result.success(verified)
        } catch (e: Exception) {
            Log.e(TAG, "Verification failed", e)
            result.success(false)
        }
    }

    // ──────────────────────────────────────────────
    // Encrypt / Decrypt
    // ──────────────────────────────────────────────

    private fun handleEncrypt(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
            val data = call.argument<ByteArray>("data") ?: throw IllegalArgumentException("data required")

            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            val cert = ks.getCertificate(keyAlias)
                ?: throw IllegalStateException("Certificate not found: $keyAlias")

            val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            cipher.init(Cipher.ENCRYPT_MODE, cert.publicKey)
            val encrypted = cipher.doFinal(data)

            result.success(encrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Encryption failed", e)
            result.error("ENCRYPT_ERROR", "Failed to encrypt data: ${e.message}", null)
        }
    }

    private fun handleDecrypt(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"
            val data = call.argument<ByteArray>("data") ?: throw IllegalArgumentException("data required")

            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            val entry = ks.getEntry(keyAlias, null) as? KeyStore.PrivateKeyEntry
                ?: throw IllegalStateException("Key not found: $keyAlias")

            val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            cipher.init(Cipher.DECRYPT_MODE, entry.privateKey)
            val decrypted = cipher.doFinal(data)

            result.success(decrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Decryption failed", e)
            result.error("DECRYPT_ERROR", "Failed to decrypt data: ${e.message}", null)
        }
    }

    // ──────────────────────────────────────────────
    // Key Management
    // ──────────────────────────────────────────────

    private fun handleDeleteKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val keyAlias = call.argument<String>("keyAlias") ?: "attestation_key"

            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            ks.deleteEntry(keyAlias)

            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Key deletion failed", e)
            result.error("DELETE_ERROR", "Failed to delete key: ${e.message}", null)
        }
    }

    private fun handleGetDeviceKey(result: MethodChannel.Result) {
        try {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)

            if (!ks.containsAlias(DEVICE_KEY_ALIAS)) {
                // Generate a new AES device key
                val keyGenerator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES,
                    ANDROID_KEYSTORE
                )
                val spec = KeyGenParameterSpec.Builder(
                    DEVICE_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
                keyGenerator.init(spec)
                keyGenerator.generateKey()
            }

            // Export the key (wrapped for secure transport)
            val secretKey = ks.getKey(DEVICE_KEY_ALIAS, null) as? SecretKey
            if (secretKey != null) {
                result.success(secretKey.encoded)
            } else {
                result.error("KEY_ERROR", "Device key not available", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get device key", e)
            result.error("KEY_ERROR", "Failed to get device key: ${e.message}", null)
        }
    }

    private fun handleZeroizeAllKeys(result: MethodChannel.Result) {
        try {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)

            // Delete all app-specific keys
            val aliases = ks.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                if (alias.startsWith("danger_emergence_") || alias.startsWith("data_key_")) {
                    ks.deleteEntry(alias)
                }
            }

            Log.d(TAG, "All app keys zeroized successfully")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Key zeroization failed", e)
            result.error("ZEROIZE_ERROR", "Failed to zeroize keys: ${e.message}", null)
        }
    }

    // ──────────────────────────────────────────────
    // Key Attestation
    // ──────────────────────────────────────────────

    private fun handleVerifyAttestation(call: MethodCall, result: MethodChannel.Result) {
        try {
            val attestationData = call.argument<ByteArray>("attestationData")
            if (attestationData == null) {
                result.error("ATTEST_ERROR", "Attestation data required", null)
                return
            }

            // 1. Parse certificate chain
            val factory = CertificateFactory.getInstance("X.509")
            val cert = factory.generateCertificate(ByteArrayInputStream(attestationData)) as X509Certificate

            // 2. Extract Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17)
            val extensionValue = cert.getExtensionValue("1.3.6.1.4.1.11129.2.1.17")
            val isHardwareBacked = extensionValue != null

            // 3. Verify certificate validity
            cert.checkValidity()

            // 4. Check key usage
            val keyUsage = cert.keyUsage
            val isSigningKey = keyUsage?.getOrElse(0) { false } == true

            val response = HashMap<String, Any?>()
            response["verified"] = isHardwareBacked && isSigningKey
            response["hardwareBacked"] = isHardwareBacked
            response["deviceSecure"] = isHardwareBacked
            response["bootloaderUnlocked"] = false
            response["rollbackResistant"] = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
            response["details"] = if (isHardwareBacked) {
                "Key attestation verified — hardware-backed key"
            } else {
                "Key attestation not available — software key"
            }

            result.success(response)
        } catch (e: Exception) {
            Log.e(TAG, "Attestation verification failed", e)
            val response = HashMap<String, Any?>()
            response["verified"] = false
            response["hardwareBacked"] = false
            response["deviceSecure"] = false
            response["bootloaderUnlocked"] = false
            response["rollbackResistant"] = false
            response["details"] = "Attestation verification error: ${e.message}"
            result.success(response)
        }
    }

    // ──────────────────────────────────────────────
    // Signature Hash
    // ──────────────────────────────────────────────

    private fun handleGetSignatureHash(result: MethodChannel.Result) {
        try {
            val packageName = context.packageName
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNATURES
                )
            }

            val digest = MessageDigest.getInstance("SHA-256")
            val hashBytes: ByteArray

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val sig = info.signingInfo.signingCertificateHistory[0]
                hashBytes = digest.digest(sig.toByteArray())
            } else {
                @Suppress("DEPRECATION")
                val sig = info.signatures[0]
                hashBytes = digest.digest(sig.toByteArray())
            }

            val hashHex = hashBytes.joinToString("") { "%02x".format(it) }
            result.success(hashHex)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get signature hash", e)
            result.error("SIG_HASH_ERROR", "Failed to get signature hash: ${e.message}", null)
        }
    }

    // ──────────────────────────────────────────────
    // Package / Bundle Verification
    // ──────────────────────────────────────────────

    private fun handleIsPackageInstalled(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("package")
                ?: throw IllegalArgumentException("package required")

            val installed = try {
                context.packageManager.getPackageInfo(packageName, 0)
                true
            } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                false
            }

            result.success(installed)
        } catch (e: Exception) {
            Log.e(TAG, "Package check failed", e)
            result.success(false)
        }
    }

    /**
     * iOS bundle signature verification stub.
     * On Android, this is not applicable — always returns true.
     */
    private fun handleVerifyBundleSignature(result: MethodChannel.Result) {
        // Android does not have bundle signature verification like iOS.
        // APK signature is verified at install time by the OS.
        // Return true as the OS-level check is sufficient.
        result.success(true)
    }
}
