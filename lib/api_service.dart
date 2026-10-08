import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

const apiBase = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://192.168.1.110:8080/api',
);
const storage = FlutterSecureStorage();
const deviceChannel = MethodChannel('dharmaj/device');
bool get isAndroidDevice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get isIosDevice => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
final dio = Dio(
  BaseOptions(
    baseUrl: apiBase,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);

class ApiService {
  Future<String> fingerprint(String productCode) async {
    var installation = await storage.read(key: 'installationId');
    if (installation == null) {
      installation = base64Url.encode(
        List<int>.generate(24, (_) => Random.secure().nextInt(256)),
      );
      await storage.write(key: 'installationId', value: installation);
    }
    String androidId = 'web-client',
        model = 'browser',
        manufacturer = 'unknown';
    if (isAndroidDevice) {
      final d = await DeviceInfoPlugin().androidInfo;
      androidId = await deviceChannel.invokeMethod<String>('androidId') ?? d.id;
      model = d.model;
      manufacturer = d.manufacturer;
    } else if (isIosDevice) {
      final d = await DeviceInfoPlugin().iosInfo;
      androidId = d.identifierForVendor ?? installation;
      model = d.utsname.machine;
      manufacturer = 'Apple';
    }
    final source = '$productCode|$androidId|$model|$manufacturer|$installation';
    return sha256.convert(utf8.encode(source)).toString();
  }

  Future<Map<String, dynamic>> requestActivation(
    int productId,
    String productCode,
  ) async {
    final id = await fingerprint(productCode);
    return (await dio.post(
          '/activations/request',
          data: {
            'productId': productId,
            'sno': isIosDevice ? 'IOS' : 'ANDROID',
            'ano': productCode,
            'cpuId': id,
            'biosId': isIosDevice ? 'IOS' : 'ANDROID',
            'diskId': isIosDevice ? 'IOS' : 'ANDROID',
            'baseId': isIosDevice ? 'IOS' : 'ANDROID',
            'videoId': isIosDevice ? 'IOS' : 'ANDROID',
            'macId': isIosDevice ? 'IOS' : 'ANDROID',
          },
        )).data
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getActivationStatus(
    int productId,
    String productCode,
  ) async {
    final id = await fingerprint(productCode);
    return (await dio.get(
          '/activations/status',
          queryParameters: {
            'productId': productId,
            'cpuId': id,
            'biosId': isIosDevice ? 'IOS' : 'ANDROID',
            'diskId': isIosDevice ? 'IOS' : 'ANDROID',
            'baseId': isIosDevice ? 'IOS' : 'ANDROID',
            'videoId': isIosDevice ? 'IOS' : 'ANDROID',
            'macId': isIosDevice ? 'IOS' : 'ANDROID',
          },
        )).data
        as Map<String, dynamic>;
  }

  Future<bool> requestNotificationPermission() async =>
      await deviceChannel.invokeMethod<bool>('requestNotificationPermission') ??
      false;

  Future<void> showNotification(
    String title,
    String body, {
    String? status,
    int? productId,
    String? productCode,
  }) => deviceChannel.invokeMethod<void>('showActivationNotification', {
    'title': title,
    'body': body,
    'status': status,
    'productId': productId,
    'productCode': productCode,
  });
}
