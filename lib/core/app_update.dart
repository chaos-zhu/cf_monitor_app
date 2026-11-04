import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

enum UpdateSource { github, appStore }

enum UpdateStatus { available, upToDate, notPublished, unsupported }

class UpdateResult {
  const UpdateResult({
    required this.status,
    this.source,
    this.version,
    this.url,
  });

  final UpdateStatus status;
  final UpdateSource? source;
  final String? version;
  final Uri? url;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException();
}

class AppUpdateService {
  AppUpdateService({Dio? dio, TargetPlatform? platform})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ),
      platform = platform ?? defaultTargetPlatform;

  static final easyNodeUrl = Uri.https('github.com', '/chaos-zhu/easynode');
  static const _repository = 'chaos-zhu/cf_monitor_app';

  final Dio _dio;
  final TargetPlatform platform;

  Future<UpdateResult> check(
    PackageInfo installed, {
    String countryCode = 'us',
  }) async {
    try {
      return switch (platform) {
        TargetPlatform.android => await _android(installed),
        TargetPlatform.iOS => await _ios(installed, countryCode),
        _ => const UpdateResult(status: UpdateStatus.unsupported),
      };
    } on DioException {
      throw const UpdateCheckException();
    } on FormatException {
      throw const UpdateCheckException();
    }
  }

  Future<Response<String>> _get(Uri url) => _dio.getUri<String>(
    url,
    options: Options(
      // Apple's lookup endpoint can return JSON as text/javascript.
      responseType: ResponseType.plain,
      validateStatus: (status) => true,
      headers: {'Accept': 'application/json'},
    ),
  );

  Map<String, dynamic> _object(Response<String> response) {
    if (response.statusCode != 200) throw const UpdateCheckException();
    final data = jsonDecode(response.data ?? '');
    if (data is! Map<String, dynamic>) throw const UpdateCheckException();
    return data;
  }

  Future<UpdateResult> _android(PackageInfo installed) async {
    final response = await _get(
      Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
    );
    if (response.statusCode == 404) {
      return const UpdateResult(
        status: UpdateStatus.notPublished,
        source: UpdateSource.github,
      );
    }
    final release = _object(response);
    final tag = release['tag_name'];
    final assets = release['assets'];
    if (tag is! String ||
        release['draft'] != false ||
        release['prerelease'] != false ||
        assets is! List) {
      throw const UpdateCheckException();
    }
    final version = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
    if (version.isPreRelease) throw const UpdateCheckException();
    final hasApk = assets.any(
      (asset) =>
          asset is Map &&
          asset['name'] is String &&
          (asset['name'] as String).endsWith('.apk') &&
          asset['state'] == 'uploaded',
    );
    if (!hasApk) {
      return const UpdateResult(
        status: UpdateStatus.notPublished,
        source: UpdateSource.github,
      );
    }
    return UpdateResult(
      status: version > Version.parse(installed.version)
          ? UpdateStatus.available
          : UpdateStatus.upToDate,
      source: UpdateSource.github,
      version: version.toString(),
      // The release page lets the user choose the APK for their architecture.
      url: Uri.https('github.com', '/$_repository/releases/tag/$tag'),
    );
  }

  Future<UpdateResult> _ios(PackageInfo installed, String countryCode) async {
    final response = await _get(
      Uri.https('itunes.apple.com', '/lookup', {
        'bundleId': installed.packageName,
        'country': countryCode.toLowerCase(),
        'entity': 'software',
      }),
    );
    final data = _object(response);
    final results = data['results'];
    if (data['resultCount'] is! int || results is! List) {
      throw const UpdateCheckException();
    }
    if (data['resultCount'] == 0 && results.isEmpty) {
      return const UpdateResult(
        status: UpdateStatus.notPublished,
        source: UpdateSource.appStore,
      );
    }
    for (final app in results) {
      if (app is! Map || app['bundleId'] != installed.packageName) continue;
      final versionString = app['version'];
      final urlString = app['trackViewUrl'];
      if (versionString is! String || urlString is! String) {
        throw const UpdateCheckException();
      }
      final version = Version.parse(versionString);
      final url = Uri.tryParse(urlString);
      if (url == null ||
          url.scheme != 'https' ||
          !const ['apps.apple.com', 'itunes.apple.com'].contains(url.host)) {
        throw const UpdateCheckException();
      }
      return UpdateResult(
        status: version > Version.parse(installed.version)
            ? UpdateStatus.available
            : UpdateStatus.upToDate,
        source: UpdateSource.appStore,
        version: versionString,
        url: url,
      );
    }
    throw const UpdateCheckException();
  }

  void dispose() => _dio.close(force: true);
}
