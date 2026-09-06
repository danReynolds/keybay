package dev.keybay.securityharness

import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.Process
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

/**
 * Host-side oracle used only by the repository's device-security harness.
 *
 * Keybay reaches Android Keystore through its own pure-FFI JNI shim. Reading
 * the same key through ordinary Kotlin APIs gives the tests an independent
 * implementation with which to check Keybay's interpretation of KeyInfo.
 * This is deliberately kept in the example app; it is not part of the
 * package's production API.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_SECURITY_CHANNEL,
        ).setMethodCallHandler(::handleDeviceSecurityCall)
    }

    private fun handleDeviceSecurityCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "lifecyclePhase" -> result.success(
                    intent.getStringExtra("keybayLifecyclePhase")
                        ?.takeIf { it in setOf("seed", "mutate", "reopen", "cleanup") },
                )
                "keyInfo" -> result.success(readKeyInfo(testAlias(call)))
                "noBackupFilesDir" -> result.success(noBackupFilesDir.absolutePath)
                "hostFacts" -> result.success(
                    mapOf(
                        "packageName" to packageName,
                        "processName" to Application.getProcessName(),
                        "uid" to Process.myUid(),
                        "cacheDir" to cacheDir.absolutePath,
                        "noBackupFilesDir" to noBackupFilesDir.absolutePath,
                    ),
                )
                "deleteAlias" -> {
                    requireDebuggable()
                    result.success(deleteAlias(testAlias(call)))
                }
                "replaceAliasWithFreshAesKey" -> {
                    requireDebuggable()
                    result.success(replaceAliasWithFreshAesKey(testAlias(call)))
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(
                "DEVICE_SECURITY_ORACLE_FAILED",
                "${error.javaClass.name}: ${error.message ?: "no detail"}",
                null,
            )
        }
    }

    private fun readKeyInfo(alias: String): Map<String, Any> {
        val keyStore = androidKeyStore()
        if (!keyStore.containsAlias(alias)) {
            return mapOf("present" to false)
        }

        val key = keyStore.getKey(alias, null) as? SecretKey
            ?: error("alias is present but is not a SecretKey")
        val factory = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
        val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
        return mapOf(
            "present" to true,
            "algorithm" to key.algorithm,
            "keySize" to info.keySize,
            "origin" to info.origin,
            "purposes" to info.purposes,
            "blockModes" to info.blockModes.toList(),
            "encryptionPaddings" to info.encryptionPaddings.toList(),
            "userAuthenticationRequired" to info.isUserAuthenticationRequired,
            "securityLevel" to info.securityLevel,
            "securityLevelName" to securityLevelName(info.securityLevel),
        )
    }

    /** Test cleanup and future key-loss challenges; never enabled in release builds. */
    private fun deleteAlias(alias: String): Boolean {
        val keyStore = androidKeyStore()
        val existed = keyStore.containsAlias(alias)
        if (existed) keyStore.deleteEntry(alias)
        return existed
    }

    /** Replaces the fixed alias without access to Keybay's provider state. */
    private fun replaceAliasWithFreshAesKey(alias: String): Boolean {
        val keyStore = androidKeyStore()
        val existed = keyStore.containsAlias(alias)
        if (existed) keyStore.deleteEntry(alias)

        val parameters = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(false)
            .build()
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).apply {
            init(parameters)
            generateKey()
        }
        return existed
    }

    private fun androidKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun testAlias(call: MethodCall): String {
        val alias = call.argument<String>("alias")
            ?: throw IllegalArgumentException("alias is required")
        require(TEST_ALIAS_PREFIXES.any(alias::startsWith)) {
            "oracle is restricted to the device-security test namespace"
        }
        return alias
    }

    private fun requireDebuggable() {
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        check(debuggable) { "mutating oracle methods require a debuggable harness build" }
    }

    private fun securityLevelName(level: Int): String =
        when (level) {
            KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
            KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trustedEnvironment"
            KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongBox"
            KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "unknownSecure"
            else -> "unknown($level)"
        }

    private companion object {
        const val DEVICE_SECURITY_CHANNEL =
            "dev.keybay.securityharness/keybay_device_security"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        val TEST_ALIAS_PREFIXES = listOf(
            "com.example.keybayDeviceSecurity.",
            "keybay.v2.",
        )
    }
}
