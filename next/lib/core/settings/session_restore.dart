import 'package:ephemeron/core/settings/shared_preferences_provider.dart';

class SessionRestore {
  SessionRestore._();

  static Future<void> saveOpenMenu(String menu,
      {String? entityId, String? extra}) async {
    try {
      await sharedPrefs.setString('session.openMenu', menu);
      await sharedPrefs.setString('session.openMenuEntityId', entityId ?? '');
      await sharedPrefs.setString('session.openMenuExtra', extra ?? '');
    } catch (_) {}
  }

  static Future<void> clearOpenMenu() async {
    try {
      await sharedPrefs.setString('session.openMenu', 'none');
      await sharedPrefs.setString('session.openMenuEntityId', '');
      await sharedPrefs.setString('session.openMenuExtra', '');
    } catch (_) {}
  }

  static Future<void> saveDraftValue(
      String formType, String? entityId, String key, String value) async {
    try {
      final id = entityId ?? 'new';
      await sharedPrefs.setString('session.draft.$formType.$id.$key', value);
    } catch (_) {}
  }

  static Future<String?> getDraftValue(
      String formType, String? entityId, String key) async {
    try {
      final id = entityId ?? 'new';
      return sharedPrefs.getString('session.draft.$formType.$id.$key');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearDraftValues(
      String formType, String? entityId) async {
    try {
      final id = entityId ?? 'new';
      final keys = sharedPrefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('session.draft.$formType.$id.')) {
          await sharedPrefs.remove(k);
        }
      }
    } catch (_) {}
  }
}
