package com.example.remedios_app_flutter

import androidx.annotation.NonNull
import com.example.remedios_app_flutter.security.AndroidDatabaseKeyStore
import com.example.remedios_app_flutter.security.KeyRecoveryRequiredException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Database key store channel: the Dart layer generates the 256-bit
        // DEK with a CSPRNG and this side wraps it with a non-exportable
        // Android Keystore AES-GCM key. The raw DEK is never persisted or
        // logged here; only the wrapped envelope is stored.
        val keyStore = AndroidDatabaseKeyStore(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DATABASE_KEY_STORE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    METHOD_READ_KEY -> {
                        val key = keyStore.readKey()
                        if (key == null) {
                            result.success(null)
                        } else {
                            result.success(key.toHex())
                        }
                    }
                    METHOD_CREATE_KEY_IF_ABSENT -> {
                        val keyHex = call.argument<String>(ARG_KEY_HEX)
                        if (keyHex == null || keyHex.length != 64) {
                            result.error(
                                "invalid_argument",
                                "keyHex must contain exactly 64 hex characters.",
                                null,
                            )
                        } else {
                            result.success(
                                keyStore.createKeyIfAbsent(keyHex.fromHex()),
                            )
                        }
                    }
                    METHOD_DELETE_KEY -> {
                        keyStore.deleteKey()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: KeyRecoveryRequiredException) {
                result.error("key_recovery_required", error.message, null)
            } catch (error: Exception) {
                result.error("key_store_error", error.message, null)
            }
        }
    }

    private fun ByteArray.toHex(): String =
        joinToString(separator = "") { byte ->
            ((byte.toInt() and 0xFF)).toString(16).padStart(2, '0')
        }

    private fun String.fromHex(): ByteArray =
        ByteArray(length / 2) { index ->
            substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }

    companion object {
        private const val DATABASE_KEY_STORE_CHANNEL =
            "remedios_app/database_key_store"
        private const val METHOD_READ_KEY = "readKey"
        private const val METHOD_CREATE_KEY_IF_ABSENT = "createKeyIfAbsent"
        private const val METHOD_DELETE_KEY = "deleteKey"
        private const val ARG_KEY_HEX = "keyHex"
    }
}
