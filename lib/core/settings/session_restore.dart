import 'package:shared_preferences/shared_preferences.dart';

class SessionRestore {
  SessionRestore._();

  static Future<void> saveOpenMenu(String menu, {String? entityId, String? extra}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session.openMenu', menu);
      await prefs.setString('session.openMenuEntityId', entityId ?? '');
      await prefs.setString('session.openMenuExtra', extra ?? '');
    } catch (_) {}
  }

  static Future<void> clearOpenMenu() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session.openMenu', 'none');
      await prefs.setString('session.openMenuEntityId', '');
      await prefs.setString('session.openMenuExtra', '');
    } catch (_) {}
  }

  static Future<void> saveDraftValue(String formType, String? entityId, String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = entityId ?? 'new';
      await prefs.setString('session.draft.$formType.$id.$key', value);
    } catch (_) {}
  }

  static Future<String?> getDraftValue(String formType, String? entityId, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = entityId ?? 'new';
      return prefs.getString('session.draft.$formType.$id.$key');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearDraftValues(String formType, String? entityId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = entityId ?? 'new';
      final keys = prefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('session.draft.$formType.$id.')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }
}
