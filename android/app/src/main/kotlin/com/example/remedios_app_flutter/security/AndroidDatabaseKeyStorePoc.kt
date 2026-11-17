package com.example.remedios_app_flutter.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.io.RandomAccessFile
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Isolated Android-only proof of concept. It is deliberately not registered
 * with Flutter or used by DatabaseService.
 *
 * A random DEK is wrapped by a non-exportable Android Keystore AES key. The
 * wrapped DEK is stored in noBackupFilesDir via AtomicFile. A JVM lock
 * serializes threads/instances in this process; an OS file lock serializes
 * cooperating processes using the same app-private lock file.
 *
 * This class is not production-approved. In particular, multiprocess tests,
 * device/OS lifecycle tests, and independent security review are still needed.
 */
internal class AndroidDatabaseKeyStorePoc(
    context: Context,
    private val namespace: String,
) {
    private val appContext = context.applicationContext
    private val directory = File(appContext.noBackupFilesDir, "database-key-poc")
    private val envelopeFile = File(directory, "$namespace.dek")
    private val lockFile = File(directory, "$namespace.lock")
    private val atomicFile = AtomicFile(envelopeFile)
    private val keyAlias = "remedios-db-key-poc-$namespace"

    init {
        require(namespace.matches(Regex("[a-zA-Z0-9_-]{1,48}"))) {
            "Invalid key-store namespace."
        }
    }

    /** Returns null only when both the wrapped DEK and its Keystore key are absent. */
    fun readKey(): ByteArray? = withExclusiveLock {
        ensureSupportedPlatform()
        val envelope = readEnvelopeOrNull()
        val wrappingKeyExists = containsWrappingKey()

        if (envelope == null && !wrappingKeyExists) return@withExclusiveLock null
        if (envelope == null || !wrappingKeyExists) {
            throw KeyRecoveryRequiredException(
                "The local database key is incomplete. Restore the recovery envelope.",
            )
        }
        decrypt(envelope)
    }

    /**
     * Stores a 32-byte DEK only if absent. Returns false when a valid key
     * already exists. It never replaces an existing key.
     */
    fun createKeyIfAbsent(candidate: ByteArray): Boolean = withExclusiveLock {
        ensureSupportedPlatform()
        require(candidate.size == DEK_LENGTH) {
            "Database key must contain exactly 32 bytes."
        }

        val envelope = readEnvelopeOrNull()
        val wrappingKeyExists = containsWrappingKey()

        if (envelope != null && wrappingKeyExists) {
            decrypt(envelope) // Verify integrity before reporting an existing key.
            return@withExclusiveLock false
        }
        if (envelope != null || wrappingKeyExists) {
            throw KeyRecoveryRequiredException(
                "The local database key is incomplete. Restore the recovery envelope.",
            )
        }

        val wrappingKey = createWrappingKey()
        val encrypted = encrypt(candidate, wrappingKey)
        writeEnvelopeAtomically(encrypted)
        true
    }

    private fun ensureSupportedPlatform() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw UnsupportedOperationException(
                "Android Keystore AES-GCM requires Android 6.0 (API 23) or later.",
            )
        }
    }

    private fun withExclusiveLock(block: () -> ByteArray?): ByteArray? {
        TODO("placeholder")
    }

    private fun containsWrappingKey(): Boolean = loadKeyStore().containsAlias(keyAlias)

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun createWrappingKey(): SecretKey {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun getWrappingKey(): SecretKey {
        val key = loadKeyStore().getKey(keyAlias, null)
        return key as? SecretKey
            ?: throw KeyRecoveryRequiredException(
                "The Android Keystore key is unavailable. Restore the recovery envelope.",
            )
    }

    private fun encrypt(dek: ByteArray, wrappingKey: SecretKey): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        val iv = cipher.iv
        val ciphertextAndTag = cipher.doFinal(dek)
        if (iv.size != GCM_IV_LENGTH || ciphertextAndTag.size != DEK_LENGTH + GCM_TAG_LENGTH) {
            throw GeneralSecurityException("Unexpected AES-GCM output size.")
        }
        return byteArrayOf(FORMAT_VERSION) + iv + ciphertextAndTag
    }

    private fun decrypt(envelope: ByteArray): ByteArray {
        if (envelope.size != ENVELOPE_LENGTH || envelope[0] != FORMAT_VERSION) {
            throw KeyRecoveryRequiredException(
                "The local database key envelope is invalid. Restore a recovery copy.",
            )
        }
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getWrappingKey(),
                GCMParameterSpec(GCM_TAG_LENGTH * 8, envelope.copyOfRange(1, 1 + GCM_IV_LENGTH)),
            )
            return cipher.doFinal(envelope.copyOfRange(1 + GCM_IV_LENGTH, envelope.size))
                .also {
                    if (it.size != DEK_LENGTH) {
                        throw KeyRecoveryRequiredException(
                            "The recovered database key has an invalid length.",
                        )
                    }
                }
        } catch (error: AEADBadTagException) {
            throw KeyRecoveryRequiredException(
                "The local database key failed authentication. Restore a recovery copy.",
            )
        } catch (error: KeyRecoveryRequiredException) {
            throw error
        } catch (error: GeneralSecurityException) {
            throw KeyRecoveryRequiredException(
                "The local database key cannot be opened. Restore a recovery copy.",
            )
        }
    }

    private fun readEnvelopeOrNull(): ByteArray? {
        return try {
            atomicFile.openRead().use { it.readBytes() }
        } catch (_: FileNotFoundException) {
            null
        }
    }

    private fun writeEnvelopeAtomically(bytes: ByteArray) {
        directory.mkdirs()
        var stream = atomicFile.startWrite()
        try {
            stream.write(bytes)
            stream.fd.sync()
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            atomicFile.failWrite(stream)
            throw error
        }
    }

    private fun <T> withExclusiveLock(block: () -> T): T {
        directory.mkdirs()
        val path = lockFile.absolutePath
        val processLock = processLocks.computeIfAbsent(path) { ReentrantLock() }
        return processLock.withLockCompat {
            RandomAccessFile(lockFile, "rw").channel.use { channel ->
                channel.lock().use { block() }
            }
        }
    }

    /** Test-only cleanup. Never call this from application flows. */
    fun destroyForTesting() = withExclusiveLock {
        val keyStore = loadKeyStore()
        if (keyStore.containsAlias(keyAlias)) keyStore.deleteEntry(keyAlias)
        atomicFile.delete()
        lockFile.delete()
        Unit
    }

    private inline fun <T> ReentrantLock.withLockCompat(block: () -> T): T {
        lock()
        try {
            return block()
        } finally {
            unlock()
        }
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val DEK_LENGTH = 32
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH = 16
        private const val FORMAT_VERSION: Byte = 1
        private const val ENVELOPE_LENGTH = 1 + GCM_IV_LENGTH + DEK_LENGTH + GCM_TAG_LENGTH
        private val processLocks = ConcurrentHashMap<String, ReentrantLock>()
    }
}

internal class KeyRecoveryRequiredException(message: String) : Exception(message)
