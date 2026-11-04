import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

abstract class SiteStorage {
  Future<List<MonitorSite>> load();
  Future<void> save(List<MonitorSite> sites);
  Future<String?> readToken(String id);
  Future<void> writeToken(String id, String? token);
  Future<String?> readDefaultSiteId();
  Future<void> writeDefaultSiteId(String? id);
  Future<bool> readCompactLayout() => Future.value(false);
  Future<void> writeCompactLayout(bool compact) => Future.value();
  Future<Map<String, dynamic>?> readRates() => Future.value(null);
  Future<void> writeRates(Map<String, dynamic> rates) => Future.value();
}

class DeviceSiteStorage extends SiteStorage {
  static const _sitesKey = 'cf_monitor.sites.v1';
  static const _ratesKey = 'cf_monitor.rates.v1';
  static const _defaultSiteKey = 'cf_monitor.default_site.v1';
  static const _compactLayoutKey = 'cf_monitor.compact_layout.v1';
  final _secure = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  @override
  Future<List<MonitorSite>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_sitesKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('站点存储格式错误');
    return decoded.map((v) => MonitorSite.fromJson(jsonMap(v))).toList();
  }

  @override
  Future<void> save(List<MonitorSite> sites) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      _sitesKey,
      jsonEncode(sites.map((s) => s.toJson()).toList()),
    );
    if (!ok) throw StateError('保存站点失败');
  }

  @override
  Future<String?> readDefaultSiteId() async =>
      (await SharedPreferences.getInstance()).getString(_defaultSiteKey);

  @override
  Future<bool> readCompactLayout() async =>
      (await SharedPreferences.getInstance()).getBool(_compactLayoutKey) ??
      false;

  @override
  Future<void> writeCompactLayout(bool compact) async {
    final ok = await (await SharedPreferences.getInstance()).setBool(
      _compactLayoutKey,
      compact,
    );
    if (!ok) throw StateError('保存布局失败');
  }

  @override
  Future<void> writeDefaultSiteId(String? id) async {
    final preferences = await SharedPreferences.getInstance();
    final ok = id == null
        ? await preferences.remove(_defaultSiteKey)
        : await preferences.setString(_defaultSiteKey, id);
    if (!ok) throw StateError('保存默认主页失败');
  }

  @override
  Future<String?> readToken(String id) =>
      _secure.read(key: 'cf_monitor.token.$id');
  @override
  Future<void> writeToken(String id, String? token) => token == null
      ? _secure.delete(key: 'cf_monitor.token.$id')
      : _secure.write(key: 'cf_monitor.token.$id', value: token);
  @override
  Future<Map<String, dynamic>?> readRates() async {
    final raw = (await SharedPreferences.getInstance()).getString(_ratesKey);
    if (raw == null) return null;
    try {
      return jsonMap(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeRates(Map<String, dynamic> rates) async {
    await (await SharedPreferences.getInstance()).setString(
      _ratesKey,
      jsonEncode(rates),
    );
  }
}

class SiteController extends ChangeNotifier {
  SiteController(this.storage);
  final SiteStorage storage;
  List<MonitorSite> _sites = [];
  List<MonitorSite> get sites => List.unmodifiable(_sites);
  String? _defaultSiteId;
  String? get defaultSiteId => _defaultSiteId;
  MonitorSite? get defaultSite =>
      _sites.where((site) => site.id == _defaultSiteId).firstOrNull;
  bool loading = true;
  bool _compactLayout = false;
  bool get compactLayout => _compactLayout;
  String? error;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  Future<void> _write(Future<void> Function() operation) {
    final result = Completer<void>();
    _writes = _writes.then((_) async {
      try {
        await operation();
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      _sites = await storage.load();
      _compactLayout = await storage.readCompactLayout();
      final defaultId = await storage.readDefaultSiteId();
      _defaultSiteId = _sites.any((site) => site.id == defaultId)
          ? defaultId
          : null;
    } catch (_) {
      error = '无法读取本机站点，请重试';
    }
    loading = false;
    _notify();
  }

  Future<String?> token(String id) async {
    final token = await storage.readToken(id);
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final payload = jsonMap(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
      );
      final exp = metricNumber(payload['exp']);
      if (exp == null || DateTime.now().millisecondsSinceEpoch >= exp * 1000) {
        await storage.writeToken(id, null);
        return null;
      }
      return token;
    } on FormatException {
      await storage.writeToken(id, null);
      return null;
    }
  }

  Future<void> save(
    MonitorSite site, {
    String? token,
    bool replaceToken = false,
  }) => _write(() async {
    final previous = _sites.where((s) => s.id == site.id).firstOrNull;
    if (previous != null && previous.baseUrl != site.baseUrl) {
      await storage.writeToken(site.id, null);
    }
    if (replaceToken) await storage.writeToken(site.id, token);
    final index = _sites.indexWhere((s) => s.id == site.id);
    final next = [..._sites];
    if (index < 0) {
      next.add(site);
    } else {
      next[index] = site;
    }
    await storage.save(next);
    _sites = next;
    _notify();
  });

  Future<void> setDefaultSite(String? id) => _write(() async {
    if (id != null && !_sites.any((site) => site.id == id)) {
      throw StateError('默认主页站点不存在');
    }
    await storage.writeDefaultSiteId(id);
    _defaultSiteId = id;
    _notify();
  });

  Future<void> remove(MonitorSite site) => _write(() async {
    await storage.writeToken(site.id, null);
    if (_defaultSiteId == site.id) {
      await storage.writeDefaultSiteId(null);
      _defaultSiteId = null;
      _notify();
    }
    final next = _sites.where((s) => s.id != site.id).toList();
    await storage.save(next);
    _sites = next;
    _notify();
  });

  Future<void> clearToken(String id) => storage.writeToken(id, null);

  Future<void> setCompactLayout(bool compact) => _write(() async {
    await storage.writeCompactLayout(compact);
    _compactLayout = compact;
    _notify();
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
