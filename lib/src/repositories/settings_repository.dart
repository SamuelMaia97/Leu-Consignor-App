import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';
import '../storage/local_store.dart';

class SettingsRepository {
  static const _tokenKey = 'api_bearer_token';
  static const _settingsKey = 'app_settings';
  final _box = LocalStore.instance.getBox(LocalStore.settingsBox);
  final _secureStorage = const FlutterSecureStorage();

  AppSettings loadSettings() {
    final raw = _box.get(_settingsKey);
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveSettings(AppSettings settings) => _box.put(_settingsKey, settings.toJson());

  Future<String> loadToken() async => (await _secureStorage.read(key: _tokenKey)) ?? '';

  Future<void> saveToken(String token) => _secureStorage.write(key: _tokenKey, value: token);
}
