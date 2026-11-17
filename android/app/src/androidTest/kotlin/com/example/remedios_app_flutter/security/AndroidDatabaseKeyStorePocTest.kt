package com.example.remedios_app_flutter.security

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidDatabaseKeyStorePocTest {
    private lateinit var context: Context
    private lateinit var namespace: String
    private lateinit var store: AndroidDatabaseKeyStorePoc

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        namespace = "test-${UUID.randomUUID()}"
        store = AndroidDatabaseKeyStorePoc(context, namespace)
    }

    @After
    fun tearDown() {
        store.destroyForTesting()
    }

    @Test
    fun missingKeyIsReportedWithoutGeneratingAReplacement() {
        assertNull(store.readKey())
        assertNull(store.readKey())
    }

    @Test
    fun createsOnceAndReturnsTheOriginalKey() {
        val original = ByteArray(32) { it.toByte() }
        val replacement = ByteArray(32) { (it + 40).toByte() }

        assertTrue(store.createKeyIfAbsent(original))
        assertFalse(store.createKeyIfAbsent(replacement))
        assertArrayEquals(original, store.readKey())
    }

    @Test
    fun concurrentInstancesHaveExactlyOneWinner() {
        val candidates = (0 until 16).map { index ->
            ByteArray(32) { index.toByte() }
        }
        val executor = Executors.newFixedThreadPool(candidates.size)
        try {
            val futures = candidates.map { candidate ->
                executor.submit(Callable {
                    AndroidDatabaseKeyStorePoc(context, namespace)
                        .createKeyIfAbsent(candidate)
                })
            }
            val results = futures.map { it.get() }
            assertEquals(1, results.count { it })
            assertEquals(candidates.size - 1, results.count { !it })

            val stored = store.readKey()
            assertTrue(candidates.any { it.contentEquals(stored) })
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun missingWrappedKeyWithExistingKeystoreAliasFailsClosed() {
        val original = ByteArray(32) { 7 }
        assertTrue(store.createKeyIfAbsent(original))
        store.deleteEnvelopeForTesting()

        try {
            store.readKey()
            throw AssertionError("Expected recovery-required failure.")
        } catch (_: KeyRecoveryRequiredException) {
            // Expected: an orphaned Keystore key must not trigger replacement.
        }
    }

    @Test
    fun missingKeystoreAliasWithExistingEnvelopeFailsClosed() {
        val original = ByteArray(32) { 9 }
        assertTrue(store.createKeyIfAbsent(original))
        store.deleteWrappingKeyForTesting()

        try {
            store.readKey()
            throw AssertionError("Expected recovery-required failure.")
        } catch (_: KeyRecoveryRequiredException) {
            // Expected: an orphaned envelope must not trigger replacement.
        }
    }

    @Test
    fun rejectsWrongLengthWithoutCreatingAnyKey() {
        try {
            store.createKeyIfAbsent(ByteArray(31))
            throw AssertionError("Expected invalid-key failure.")
        } catch (_: IllegalArgumentException) {
            // Expected.
        }
        assertNull(store.readKey())
    }
}
