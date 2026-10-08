import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthSession extends ChangeNotifier {
  String token = '';
  Map<String, dynamic> user = {};
  Map<String, dynamic> permissions = {};
  DateTime? expiresAt;
  bool ready = false;
  Timer? _expiryTimer;
  bool get signedIn =>
      token.isNotEmpty &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
  bool get isAdmin =>
      _claims(
            token,
          )['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ==
          'Admin' ||
      _claims(token)['role'] == 'Admin';

  Map<String, dynamic> _claims(String value) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(value.split('.')[1])),
              ),
            )
            as Map,
      );
    } catch (_) {
      return {};
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    if (signedIn) {
      _expiryTimer = Timer(
        expiresAt!.difference(DateTime.now()),
        () => signOut(),
      );
    }
  }

  Future<void> restore() async {
    try {
      final saved = await storage.read(key: 'androidLoginSession');
      if (saved != null) {
        final data = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        token = data['token'] as String? ?? '';
        final expiry = _claims(token)['exp'];
        expiresAt =
            expiry is num
                ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt() * 1000)
                : null;
        user = Map<String, dynamic>.from(data['user'] as Map? ?? {});
        permissions = Map<String, dynamic>.from(
          data['permissions'] as Map? ?? {},
        );
      }
      if (!signedIn) {
        token = '';
        user = {};
        permissions = {};
        expiresAt = null;
        await storage.delete(key: 'androidLoginSession');
      }
      _scheduleExpiry();
    } catch (_) {
      token = '';
      user = {};
      permissions = {};
      expiresAt = null;
    }
    if (!signedIn) {
      try {
        await deviceChannel.invokeMethod<void>('stopRequestMonitor');
      } catch (_) {
        /* Monitoring is Android only. */
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> signIn(String name, String password) async {
    final machineId = await ApiService().fingerprint('DHARMAJ-ACCOUNT-LOGIN');
    final result = await request(
      'POST',
      '/auth/login',
      authenticated: false,
      data: {
        'userName': name,
        'password': password,
        'machineId': machineId,
        'machineName': isIosDevice ? 'iOS device' : 'Android device',
      },
    );
    final data = Map<String, dynamic>.from(result as Map);
    final nextToken = data['token']?.toString() ?? '';
    final expiry = _claims(nextToken)['exp'];
    if (expiry is! num ||
        expiry * 1000 <= DateTime.now().millisecondsSinceEpoch) {
      throw const ApiFailure('The login session is invalid. Please try again.');
    }
    final nextUser = Map<String, dynamic>.from(data['user'] as Map? ?? {});
    final nextPermissions = Map<String, dynamic>.from(
      data['permissions'] as Map? ?? {},
    );
    await storage.write(
      key: 'androidLoginSession',
      value: jsonEncode({
        'token': nextToken,
        'user': nextUser,
        'permissions': nextPermissions,
      }),
    );
    token = nextToken;
    expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry.toInt() * 1000);
    user = nextUser;
    permissions = nextPermissions;
    _scheduleExpiry();
    notifyListeners();
  }

  Future<void> signOut() async {
    _expiryTimer?.cancel();
    token = '';
    user = {};
    permissions = {};
    expiresAt = null;
    notifyListeners();
    await storage.delete(key: 'androidLoginSession');
    try {
      await deviceChannel.invokeMethod<void>('stopRequestMonitor');
    } catch (_) {
      /* Other platforms may not have the Android monitor. */
    }
  }

  Future<void> checkExpiry() async {
    if (token.isNotEmpty && !signedIn) await signOut();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? data,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) async {
    final requestToken = token;
    if (authenticated && !signedIn) {
      await signOut();
      throw const ApiFailure('Your session expired. Please sign in again.');
    }
    try {
      final response = await dio.request(
        path,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers:
              authenticated ? {'Authorization': 'Bearer $requestToken'} : {},
        ),
      );
      final envelope = response.data;
      if (envelope is! Map) {
        throw const ApiFailure('The server returned an unexpected response.');
      }
      if (envelope['success'] != true) {
        throw ApiFailure(
          envelope['message']?.toString() ??
              'The operation could not be completed.',
        );
      }
      return envelope['data'];
    } on DioException catch (error) {
      if (authenticated &&
          error.response?.statusCode == 401 &&
          token == requestToken) {
        await signOut();
      }
      final body = error.response?.data;
      final message = body is Map ? body['message']?.toString() : null;
      throw ApiFailure(
        message ??
            (error.response?.statusCode == 403
                ? 'You do not have permission for this action.'
                : error.response?.statusCode == 401
                ? 'Please sign in again.'
                : 'Could not connect to the server. Check your network connection.'),
      );
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
