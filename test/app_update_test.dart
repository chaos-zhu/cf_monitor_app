import 'package:cf_monitor_app/core/app_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_test.dart' show StubAdapter;

PackageInfo installedVersion(String version) => PackageInfo(
  appName: 'CF Monitor',
  packageName: 'dev.cfmonitor.cfMonitorApp',
  version: version,
  buildNumber: '50',
);

Map<String, Object?> release(String tag) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'assets': [
    {'name': 'app-arm64-v8a-release.apk', 'state': 'uploaded'},
  ],
};

Map<String, Object?> storeApp(String version) => {
  'resultCount': 1,
  'results': [
    {
      'bundleId': installedVersion(version).packageName,
      'version': version,
      'trackViewUrl': 'https://apps.apple.com/us/app/cf-monitor/id123456789',
    },
  ],
};

void main() {
  late StubAdapter transport;
  late AppUpdateService service;

  AppUpdateService create(TargetPlatform platform) =>
      service = AppUpdateService(
        dio: Dio()..httpClientAdapter = transport,
        platform: platform,
      );

  setUp(() => transport = StubAdapter());
  tearDown(() => service.dispose());

  test('Android 比较语义版本，忽略不同构建渠道的 build number', () async {
    create(TargetPlatform.android);
    transport.reply = (_) => release('v1.10.0');
    final result = await service.check(installedVersion('1.9.0'));
    expect(result.status, UpdateStatus.available);
    expect(result.source, UpdateSource.github);
    expect(result.version, '1.10.0');
    expect(
      result.url.toString(),
      'https://github.com/chaos-zhu/cf_monitor_app/releases/tag/v1.10.0',
    );
    expect(
      transport.requests.single.uri.toString(),
      'https://api.github.com/repos/chaos-zhu/cf_monitor_app/releases/latest',
    );
    for (final version in ['1.10.0', '1.11.0']) {
      expect(
        (await service.check(installedVersion(version))).status,
        UpdateStatus.upToDate,
      );
    }
    expect(
      (await service.check(installedVersion('1.10.0-beta.1'))).status,
      UpdateStatus.available,
    );
  });

  test('Android 没有 Release 或已上传 APK 时不误报最新版本', () async {
    create(TargetPlatform.android);
    transport.status = 404;
    expect(
      (await service.check(installedVersion('1.0.0'))).status,
      UpdateStatus.notPublished,
    );
    transport.status = 200;
    for (final assets in [
      <Object?>[],
      [
        {'name': 'app.ipa', 'state': 'uploaded'},
      ],
      [
        {'name': 'app.apk', 'state': 'new'},
      ],
    ]) {
      transport.reply = (_) => release('v2.0.0')..['assets'] = assets;
      expect(
        (await service.check(installedVersion('1.0.0'))).status,
        UpdateStatus.notPublished,
      );
    }
  });

  test('Android 拒绝草稿、预发布和格式错误的响应，限流可以重试', () async {
    create(TargetPlatform.android);
    for (final response in [
      release('v2.0.0')..['draft'] = true,
      release('v2.0.0')..['prerelease'] = true,
      release('v2.0.0-beta.1'),
      release('not-a-version'),
      {'tag_name': 'v2.0.0'},
      'not an object',
    ]) {
      transport.reply = (_) => response;
      await expectLater(
        service.check(installedVersion('1.0.0')),
        throwsA(isA<UpdateCheckException>()),
      );
    }
    transport.status = 429;
    await expectLater(
      service.check(installedVersion('1.0.0')),
      throwsA(isA<UpdateCheckException>()),
    );
    transport.status = 200;
    transport.reply = (_) => release('v2.0.0');
    expect(
      (await service.check(installedVersion('1.0.0'))).status,
      UpdateStatus.available,
    );
  });

  test('iOS 使用运行时 Bundle ID 和地区查询 App Store，返回商店入口', () async {
    create(TargetPlatform.iOS);
    transport.reply = (_) => storeApp('1.10.0');
    final result = await service.check(
      installedVersion('1.9.0'),
      countryCode: 'CN',
    );
    expect(result.status, UpdateStatus.available);
    expect(result.source, UpdateSource.appStore);
    expect(result.url?.host, 'apps.apple.com');
    final request = transport.requests.single;
    expect(request.uri.host, 'itunes.apple.com');
    expect(request.uri.queryParameters, {
      'bundleId': installedVersion('1.9.0').packageName,
      'country': 'cn',
      'entity': 'software',
    });
    expect(request.headers.containsKey('Authorization'), isFalse);
    for (final version in ['1.10.0', '1.11.0']) {
      expect(
        (await service.check(installedVersion(version))).status,
        UpdateStatus.upToDate,
      );
    }
    expect(
      transport.requests.every((r) => r.uri.host != 'api.github.com'),
      true,
    );
  });

  test('iOS 审核期间未上架与错误响应分开处理', () async {
    create(TargetPlatform.iOS);
    transport.reply = (_) => {'resultCount': 0, 'results': []};
    final result = await service.check(installedVersion('1.0.0'));
    expect(result.status, UpdateStatus.notPublished);
    expect(result.source, UpdateSource.appStore);
    expect(result.url, isNull);
    for (final response in [
      {'results': []},
      {'resultCount': 1, 'results': []},
      {
        'resultCount': 1,
        'results': [
          {
            'bundleId': 'another.app',
            'version': '9.0.0',
            'trackViewUrl': 'https://apps.apple.com/app/id123',
          },
        ],
      },
      {
        'resultCount': 1,
        'results': [
          {
            'bundleId': installedVersion('1.0.0').packageName,
            'version': '9.0.0',
            'trackViewUrl': 'https://example.com/app',
          },
        ],
      },
    ]) {
      transport.reply = (_) => response;
      await expectLater(
        service.check(installedVersion('1.0.0')),
        throwsA(isA<UpdateCheckException>()),
      );
    }
  });

  test('桌面平台不请求移动端更新源', () async {
    create(TargetPlatform.macOS);
    expect(
      (await service.check(installedVersion('1.0.0'))).status,
      UpdateStatus.unsupported,
    );
    expect(transport.requests, isEmpty);
  });
}
