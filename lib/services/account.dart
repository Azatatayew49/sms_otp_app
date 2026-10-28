import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gateway_service.dart';

/// Sign-in with a login and password an admin created in the staff app. The token
/// stays valid until this phone signs out (or an admin removes the account).
class Account {
  Account._();

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); // the background service writes here too
    return p;
  }

  static Future<bool> signedIn() async => (await _prefs()).getString(kPrefAuthToken)?.isNotEmpty ?? false;

  static Future<String> login() async => (await _prefs()).getString(kPrefLogin) ?? '';

  static Future<String> serverUrl() async => (await _prefs()).getString(kPrefUrl) ?? kDefaultUrl;

  /// Phones set up before the domain existed saved the server's IP; move them to the
  /// domain (the app no longer shows or asks for a server address).
  static Future<void> migrateServerUrl() async {
    final prefs = await _prefs();
    final saved = prefs.getString(kPrefUrl);
    if (saved != null && saved.contains('45.39.230.200')) await prefs.setString(kPrefUrl, kDefaultUrl);
  }

  /// This install's stable id (the server knows the phone by it).
  static Future<String> deviceId(SharedPreferences prefs) async {
    var id = prefs.getString(kPrefDeviceId) ?? '';
    if (id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(kPrefDeviceId, id);
    }
    return id;
  }

  /// "Xiaomi Redmi Note 8", shown to admins.
  static Future<String> phoneModel() async {
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      final maker = a.manufacturer.isEmpty ? '' : a.manufacturer[0].toUpperCase() + a.manufacturer.substring(1);
      return a.model.toLowerCase().startsWith(a.manufacturer.toLowerCase()) ? a.model : '$maker ${a.model}'.trim();
    } catch (_) {
      return '';
    }
  }

  /// Signs in; throws a message to show on failure.
  static Future<void> signIn(String url, String login, String password) async {
    final prefs = await _prefs();
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      )).post('$base/api/gateway/login/', data: {
        'login': login.trim(),
        'password': password,
        'device_id': await deviceId(prefs),
        'model': await phoneModel(),
      });
      final d = r.data as Map<String, dynamic>;
      await prefs.setString(kPrefUrl, base);
      await prefs.setString(kPrefAuthToken, d['token'] as String);
      await prefs.setString(kPrefLogin, d['login'] as String);
      await prefs.setString(kPrefDeviceName, d['name'] as String);
      await prefs.setBool(kPrefEnabled, d['enabled'] as bool);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) throw data['detail'].toString();
      throw 'Cannot reach the server. Check the internet connection and the server address.';
    }
  }

  /// Signs out on the server (best effort) and forgets the token.
  static Future<void> signOut() async {
    final prefs = await _prefs();
    final token = prefs.getString(kPrefAuthToken) ?? '';
    final base = prefs.getString(kPrefUrl) ?? kDefaultUrl;
    await GatewayService.stop();
    if (token.isNotEmpty) {
      try {
        await Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)))
            .post('$base/api/gateway/logout/', options: Options(headers: {'Authorization': 'Token $token'}));
      } catch (_) {}
    }
    await clearSession(prefs);
  }
}

Future<void> clearSession(SharedPreferences prefs) async {
  await prefs.remove(kPrefAuthToken);
  await prefs.remove(kPrefEnabled);
}
