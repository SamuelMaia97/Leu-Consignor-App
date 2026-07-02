import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLockService {
  static const adminUsername = 'admin';
  static const adminPassword = 'LeuConsignorApp2026!';
  static const defaultUsername = 'yves';
  static const defaultPassword = 'mugi39';
  static const _usersKey = 'app_lock_users_v1';
  static const _seedVersionKey = 'app_lock_seed_version';
  static const _seedVersion = '2';

  // Legacy key kept only so older installations can still unlock with the
  // previous single-password value before an administrator changes users.
  static const _legacyPasswordHashKey = 'app_lock_password_hash';

  final FlutterSecureStorage _storage;

  AppLockService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> verifyAndGetUsername(String username, String password) async {
    final normalizedUsername = _normalizeUsername(username);
    if (normalizedUsername.isEmpty || password.isEmpty) return null;

    final users = await _readUsers();
    final expectedHash = users[normalizedUsername];
    if (expectedHash == null) return null;

    return _hash(password) == expectedHash ? normalizedUsername : null;
  }

  Future<void> upsertUser(String username, String password) async {
    final normalizedUsername = _normalizeUsername(username);
    if (normalizedUsername.isEmpty) {
      throw ArgumentError.value(username, 'username', 'Username is required.');
    }
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'Password is required.');
    }

    final users = await _readUsers();
    users[normalizedUsername] = _hash(password);
    await _writeUsers(users);
  }

  Future<void> removeUser(String username) async {
    final normalizedUsername = _normalizeUsername(username);
    if (normalizedUsername.isEmpty) return;
    if (normalizedUsername == adminUsername) return;

    final users = await _readUsers();
    users.remove(normalizedUsername);
    await _writeUsers(users);
  }

  Future<List<String>> listUsernames() async {
    final users = await _readUsers();
    final names = users.keys.toList()..sort();
    return names;
  }

  Future<bool> verify(String password) async {
    final username = await verifyAndGetUsername(defaultUsername, password);
    if (username != null) return true;

    final legacyHash = await _storage.read(key: _legacyPasswordHashKey);
    return legacyHash != null && _hash(password) == legacyHash;
  }

  Future<void> updatePassword(String password) async {
    await upsertUser(defaultUsername, password);
  }

  Future<Map<String, String>> _readUsers() async {
    final raw = await _storage.read(key: _usersKey);
    if (raw == null || raw.trim().isEmpty) {
      return _seedUsers();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final users = decoded.map(
          (key, value) => MapEntry(
            _normalizeUsername(key.toString()),
            value.toString(),
          ),
        )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
        return _migrateSeedUsers(users);
      }
    } catch (_) {
      // Re-seed corrupt storage rather than blocking all access.
    }

    return _seedUsers();
  }

  Future<Map<String, String>> _seedUsers() async {
    final seeded = <String, String>{
      defaultUsername: _hash(defaultPassword),
      adminUsername: _hash(adminPassword),
    };
    await _writeUsers(seeded);
    await _storage.write(key: _seedVersionKey, value: _seedVersion);
    return seeded;
  }

  Future<Map<String, String>> _migrateSeedUsers(
    Map<String, String> users,
  ) async {
    if (users.isEmpty) return _seedUsers();

    final seedVersion = await _storage.read(key: _seedVersionKey);
    if (seedVersion == _seedVersion) return users;

    var changed = false;
    users.putIfAbsent(defaultUsername, () {
      changed = true;
      return _hash(defaultPassword);
    });
    users.putIfAbsent(adminUsername, () {
      changed = true;
      return _hash(adminPassword);
    });

    if (changed) {
      await _writeUsers(users);
    }
    await _storage.write(key: _seedVersionKey, value: _seedVersion);
    return users;
  }

  Future<void> _writeUsers(Map<String, String> users) async {
    await _storage.write(key: _usersKey, value: jsonEncode(users));
  }

  String _normalizeUsername(String value) => value.trim().toLowerCase();

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
}
