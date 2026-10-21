import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _sessionTokenKey = 'abhishare_session_token';
  static const String _userIdKey = 'abhishare_user_id';

  Future<void> saveSession({
    required String sessionToken,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_sessionTokenKey, sessionToken);
    await prefs.setString(_userIdKey, userId);
  }

  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<Map<String, String>?> getSession() async {
    final token = await getSessionToken();
    final uid = await getUserId();
    if (token == null || uid == null) return null;
    return {'sessionToken': token, 'userId': uid};
  }

  Future<bool> isLoggedIn() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_userIdKey);
  }
}
