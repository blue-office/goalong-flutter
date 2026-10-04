import 'package:shared_preferences/shared_preferences.dart';

/// テストやアプリ独自の保存先に差し替え可能な永続ストレージ。
abstract interface class GoAlongStorage {
  Future<String?> getString(String key);
  Future<bool?> getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

/// 他のプラグイン利用者の prefix やキャッシュを変更しない非同期実装。
class SharedPreferencesGoAlongStorage implements GoAlongStorage {
  SharedPreferencesGoAlongStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);
  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);
  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);
  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

abstract final class StorageKeys {
  static const installationId = 'goalong.installation_id';
  static const installationReported = 'goalong.installation_reported';
  static const referralApplied = 'goalong.referral_applied';
  static const referralOfferingKey = 'goalong.referral_offering_key';
  static const rcAppUserId = 'goalong.rc_app_user_id';
}
