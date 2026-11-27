import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;

import 'database_key_store.dart';
import 'recovery_envelope.dart';
import 'web_key_storage.dart';
import 'web_local_storage_binding.dart'
    if (dart.library.io) 'web_local_storage_stub.dart';

/// Web implementation of the database key lifecycle.
///
/// Security model:
/// - The authoritative durable copy of the key is an authenticated
///   [RecoveryEnvelope] (AES-256-GCM + PBKDF2-HMAC-SHA256) stored as JSON.
///   Decrypting it requires the recovery password, which is asked ONLY on
///   the first interaction with the app on a device (vault setup) and for
///   backup recovery (envelope restoration in a clean profile).
/// - Product decision (PIN only on first interaction): after every
///   successful setup/unlock/restore, the resolved DEK is mirrored to
///   localStorage under [deviceKeyStorageKey]. Returning sessions on the
///   same device load the mirrored key and skip the PIN prompt entirely —
///   the gate proceeds straight to the app. This intentionally trades the
///   per-session password prompt for device convenience: possession of the
///   browser profile grants database access. The envelope remains the
///   recovery path and keeps the password requirement for restoration.
/// - Losing browser profile data loses both the device mirror and the
///   envelope, which is documented application behavior; restoring requires
///   the exported envelope + password.
class WebDatabaseKeyStore implements DatabaseKeyStore {
  WebDatabaseKeyStore({WebKeyValueStorage? storage})
    : _storage = storage ?? const LocalStorageKeyValueStorage();

  static const String envelopeStorageKey = 'rnh.db.recoveryEnvelope.v1';

  /// Device key mirror: base64 of the resolved 256-bit DEK, written on every
  /// successful setup/unlock/restore so returning sessions on this device
  /// unlock WITHOUT asking the PIN again (PIN is asked only on first
  /// interaction and for envelope restoration).
  static const String deviceKeyStorageKey = 'rnh.db.deviceKey.v1';

  final WebKeyValueStorage _storage;

  /// Key resolved for the current session (memory only).
  List<int>? _sessionKey;

  /// [DatabaseKeyState] of this session, based on what is stored.
  ///
  /// A returning session (device mirror present) reports [DatabaseKeyState.unlocked]:
  /// the PIN was answered on the first interaction and must not be asked again.
  DatabaseKeyState get state {
    if (_sessionKey != null || _readDeviceKey() != null) {
      return DatabaseKeyState.unlocked;
    }
    if (_storage.getItem(envelopeStorageKey) != null) {
      return DatabaseKeyState.locked;
    }
    return DatabaseKeyState.needsSetup;
  }

  bool get hasStoredEnvelope => _storage.getItem(envelopeStorageKey) != null;

  bool get hasDeviceKey => _readDeviceKey() != null;

  /// Reads the device key mirror, or null when absent. An invalid mirror
  /// (not base64 / wrong length) is removed and treated as absent so the
  /// password unlock fallback remains available.
  List<int>? _readDeviceKey() {
    final stored = _storage.getItem(deviceKeyStorageKey);
    if (stored == null) return null;
    try {
      final key = base64Decode(stored);
      if (key.length != 32) {
        throw const FormatException('device key mirror must be 32 bytes');
      }
      return key;
    } on FormatException {
      _storage.removeItem(deviceKeyStorageKey);
      return null;
    }
  }

  /// Persists the device key mirror (base64) for auto-unlock on the next
  /// session of this device.
  void _mirrorDeviceKey(List<int> key) {
    _storage.setItem(deviceKeyStorageKey, base64Encode(key));
  }

  /// Creates a fresh DEK protected by a new recovery envelope.
  ///
  /// Only valid when nothing is stored yet (fresh profile). Never overwrites
  /// an existing envelope: losing the old envelope would lose the database.
  Future<List<int>> setupWithPassword(String password) async {
    if (_storage.getItem(envelopeStorageKey) != null) {
      throw const DatabaseKeyRecoveryRequiredException(
        'Já existe um cofre de chaves neste navegador. Use o desbloqueio ou '
        'a restauração de envelope; sobrescrever apagaria o acesso ao banco.',
      );
    }
    _validatePasswordOrThrow(password);
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    final envelope = await RecoveryEnvelope.create(
      databaseKey: key,
      recoveryPassword: password,
    );
    _storage.setItem(envelopeStorageKey, envelope.encode());
    _mirrorDeviceKey(key);
    _sessionKey = key;
    return List<int>.of(key);
  }

  /// Explicit unlock: derives the wrapping key from [password] and unwraps
  /// the stored envelope into the session key.
  Future<List<int>> unlockWithPassword(String password) async {
    final envelopeJson = _storage.getItem(envelopeStorageKey);
    if (envelopeJson == null) {
      throw const DatabaseKeyRecoveryRequiredException(
        'Nenhum cofre de chaves está armazenado neste navegador.',
      );
    }
    final RecoveryEnvelope envelope;
    try {
      envelope = RecoveryEnvelope.decode(envelopeJson);
    } on FormatException {
      throw const DatabaseKeyRecoveryRequiredException(
        'O cofre de chaves armazenado está corrompido. Restaure um envelope '
        'de recuperação válido.',
      );
    }
    return _unlockEnvelope(envelope, password);
  }

  /// Restores an envelope exported from another install/profile and unlocks
  /// the session with [password]. Used by the clean-profile recovery flow.
  Future<List<int>> restoreEnvelope(
    String envelopeJson,
    String password,
  ) async {
    final RecoveryEnvelope envelope;
    try {
      envelope = RecoveryEnvelope.decode(envelopeJson);
    } on FormatException {
      throw const DatabaseKeyRecoveryRequiredException(
        'Envelope de recuperação inválido ou corrompido.',
      );
    }
    final key = await _unlockEnvelope(envelope, password);
    _storage.setItem(envelopeStorageKey, envelope.encode());
    return key;
  }

  /// Returns the exported recovery envelope JSON, or null when nothing is
  /// stored. The user must keep this file to be able to restore in a clean
  /// profile; it contains only ciphertext.
  String? exportEnvelopeJson() => _storage.getItem(envelopeStorageKey);

  /// Resolves the session key, loading the device key mirror when the
  /// session has not unlocked explicitly yet (auto-unlock on returning
  /// devices). Throws [DatabaseUnlockRequiredException] only when neither
  /// the session key, the mirror, nor a usable unlock path exists — i.e.
  /// the envelope is stored but the device mirror is gone (password
  /// fallback required).
  List<int>? requireSessionKey() {
    final key = _sessionKey ??= _readDeviceKey();
    if (key == null && hasStoredEnvelope) {
      throw const DatabaseUnlockRequiredException(
        'O banco criptografado precisa ser desbloqueado nesta sessão.',
      );
    }
    return key;
  }

  @override
  Future<List<int>?> readKey() async {
    final key = _sessionKey ??= _readDeviceKey();
    if (key != null) return List<int>.of(key);
    if (hasStoredEnvelope) {
      throw const DatabaseUnlockRequiredException(
        'O banco criptografado precisa ser desbloqueado nesta sessão.',
      );
    }
    return null;
  }

  /// Not supported on web: the durable copy of the key is the
  /// password-protected envelope; use [setupWithPassword] for first use.
  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    throw UnsupportedError(
      'Web stores the key only as a password-protected recovery envelope. '
      'Use setupWithPassword for first use.',
    );
  }

  @override
  Future<void> deleteKey() async {
    _sessionKey = null;
    _storage.removeItem(envelopeStorageKey);
    _storage.removeItem(deviceKeyStorageKey);
  }

  Future<List<int>> _unlockEnvelope(
    RecoveryEnvelope envelope,
    String password,
  ) async {
    if (password.length < 6) {
      throw const DatabaseUnlockWrongPasswordException(
        'A senha de recuperação deve ter pelo menos 6 caracteres.',
      );
    }
    try {
      final key = await envelope.unlock(recoveryPassword: password);
      _mirrorDeviceKey(key);
      _sessionKey = List<int>.of(key);
      return List<int>.of(key);
    } on SecretBoxAuthenticationError {
      throw const DatabaseUnlockWrongPasswordException(
        'Senha de recuperação incorreta. O banco original permanece intacto.',
      );
    } on FormatException {
      rethrow;
    }
  }

  /// Piso do serviço: 6 caracteres. A política de produto (PIN de exatamente
  /// 6 dígitos) é aplicada na UI do gate; senhas legadas (≥12) de cofres
  /// antigos continuam válidas no desbloqueio.
  void _validatePasswordOrThrow(String password) {
    if (password.length < 6) {
      throw ArgumentError(
        'Recovery password must contain at least 6 characters.',
      );
    }
  }
}
