import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/io.dart';
import 'models.dart';
import 'installation.dart';

enum FailureKind {
  network,
  authentication,
  permission,
  unsupported,
  protocol,
  server,
}

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status, this.kind = FailureKind.server});
  final String message;
  final int? status;
  final FailureKind kind;
  @override
  String toString() => message;
}

abstract interface class LiveConnection {
  Future<void> get ready;
  Stream<Object?> get events;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

class SocketConnection implements LiveConnection {
  SocketConnection(
    Uri url,
    String? token,
    String? appPassword,
    String? userAgent,
  ) : _channel = IOWebSocketChannel.connect(
        url,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'X-App-Password': ?appPassword,
          'User-Agent': ?userAgent,
        },
        connectTimeout: const Duration(seconds: 15),
      );
  final IOWebSocketChannel _channel;
  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<Object?> get events => _channel.stream;
  @override
  void send(Map<String, dynamic> message) =>
      _channel.sink.add(jsonEncode(message));
  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

abstract class MonitorApi {
  Future<SiteConfig> config(MonitorSite site, {String? token});
  Future<void> validateAppPassword(MonitorSite site);
  Future<String> login(MonitorSite site, String username, String password);
  Future<DashboardSnapshot> dashboard(
    MonitorSite site, {
    String? token,
    bool forceRefresh = false,
  });
  Future<Server> detail(MonitorSite site, String id, {String? token});
  Future<String> addServer(
    MonitorSite site, {
    required String token,
    required String name,
    String group = '',
  });
  Future<Server> serverForEdit(
    MonitorSite site,
    String id, {
    required String token,
  });
  Future<Map<String, dynamic>> editorSettings(
    MonitorSite site, {
    required String token,
  });
  Future<void> editServer(
    MonitorSite site,
    String id,
    Map<String, dynamic> fields, {
    required String token,
  });
  Future<void> deleteServer(
    MonitorSite site,
    String id, {
    required String token,
  });
  Future<InstallParameters> installParameters(
    MonitorSite site, {
    required String token,
  });
  Future<List<MetricSample>> history(
    MonitorSite site,
    String id,
    HistoryRange range, {
    String? token,
  });
  LiveConnection connect(MonitorSite site, {String? token});
  Future<Map<String, double>?> exchangeRates() => Future.value(null);
  void dispose() {}
}

class WorkerApi extends MonitorApi {
  WorkerApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 15),
              followRedirects: false,
              validateStatus: (status) => true,
            ),
          );
  final Dio _dio;
  static Uri endpoint(
    MonitorSite site,
    String path, [
    Map<String, dynamic>? query,
  ]) => Uri.parse(
    '${site.baseUrl}$path',
  ).replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));

  Future<Object?> _request(
    MonitorSite site,
    String path, {
    String? token,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _dio.requestUri<Object?>(
        endpoint(site, path, query),
        data: body,
        options: Options(
          method: body == null ? 'GET' : 'POST',
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
            if (site.appPassword != null) 'X-App-Password': site.appPassword,
            if (site.userAgent != null) 'User-Agent': site.userAgent,
          },
        ),
      );
      final status = response.statusCode ?? 0;
      Object? data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } on FormatException {
          /* Error pages are handled below. */
        }
      }
      if (status < 200 || status >= 300) {
        final json = jsonMap(data);
        final code = '${json['message'] ?? json['error'] ?? ''}';
        final message = switch (status) {
          400 when code == 'invalidServerName' => '服务器名称不符合站点要求，请修改后重试',
          400 when code == 'invalidPingNodeFormat' => '探测节点格式无效，请检查主机及端口',
          400 when code == 'invalidNetworkInterface' => '网络接口格式无效，请检查后重试',
          400 when code == 'invalidTrafficCorrection' => '流量修正值无效，请检查后重试',
          401 => '登录已失效或当前数据需要登录，请重新登录',
          403 => '请求被站点验证或防护拦截，当前版本不支持人机验证',
          404 => '未找到站点接口或服务器，服务器可能已被删除',
          409 =>
            code == 'historyPartitionNotAssigned'
                ? '该服务器尚未分配历史分区，请在 Web 后台处理'
                : '站点数据库需要维护，请在 Web 后台处理',
          503 => '实时服务暂不可用，请稍后重试',
          >= 300 && < 400 => '站点发生重定向，请填写最终的 HTTPS 地址',
          _ => '站点请求失败（$status），请稍后重试',
        };
        throw ApiFailure(
          message,
          status: status,
          kind: switch (status) {
            401 => FailureKind.authentication,
            403 => FailureKind.unsupported,
            _ => FailureKind.server,
          },
        );
      }
      if (data is! Map && data is! List) {
        throw const ApiFailure(
          '站点未返回有效的监控数据，请检查地址与版本',
          kind: FailureKind.protocol,
        );
      }
      return data;
    } on DioException catch (e) {
      if (e.error is ApiFailure) throw e.error!;
      throw const ApiFailure('无法连接站点，请检查地址、证书与网络', kind: FailureKind.network);
    }
  }

  @override
  Future<void> validateAppPassword(MonitorSite site) async {
    try {
      await _request(
        site,
        '/api/history/all',
        query: {'id': '__cf_monitor_password_check__', 'hours': 48},
      );
    } on ApiFailure catch (e) {
      if (e.status == 404) return;
      if (e.status == 401 || e.status == 403) {
        throw const ApiFailure(
          'App 访问口令无效或请求被站点防护拦截',
          kind: FailureKind.authentication,
        );
      }
      rethrow;
    }
  }

  @override
  Future<SiteConfig> config(MonitorSite site, {String? token}) async {
    final json = jsonMap(await _request(site, '/api/config', token: token));
    if (!json.containsKey('is_public') || !json.containsKey('authorization')) {
      throw const ApiFailure(
        '此地址未识别为 CF Server Monitor 站点',
        kind: FailureKind.protocol,
      );
    }
    return SiteConfig(json);
  }

  @override
  Future<String> login(
    MonitorSite site,
    String username,
    String password,
  ) async {
    final cfg = await config(site);
    ensureSupported(cfg, login: true, hasAppPassword: site.appPassword != null);
    final Map<String, dynamic> result;
    try {
      result = jsonMap(
        await _request(
          site,
          '/admin/api',
          body: {'action': 'login', 'username': username, 'password': password},
        ),
      );
    } on ApiFailure catch (e) {
      if (e.status == 403 && cfg.loginChallenge && site.appPassword != null) {
        throw const ApiFailure(
          '登录验证失败：请检查 App 访问口令、站点防护及服务端版本',
          status: 403,
          kind: FailureKind.unsupported,
        );
      }
      rethrow;
    }
    final token = result['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiFailure('站点未返回登录凭证', kind: FailureKind.protocol);
    }
    return token;
  }

  static void ensureSupported(
    SiteConfig cfg, {
    bool login = false,
    bool hasAppPassword = false,
  }) {
    if (cfg.globalChallenge && !hasAppPassword && !login) {
      throw const ApiFailure(
        '该站点启用了全局人机验证，当前版本暂不支持连接',
        kind: FailureKind.unsupported,
      );
    }
    if (login && cfg.loginChallenge && !hasAppPassword) {
      throw const ApiFailure(
        '该站点启用了登录验证，当前版本暂不支持登录',
        kind: FailureKind.unsupported,
      );
    }
  }

  @override
  Future<DashboardSnapshot> dashboard(
    MonitorSite site, {
    String? token,
    bool forceRefresh = false,
  }) async {
    try {
      // Mutations invalidate only the Worker isolate that handled them. Read an
      // authoritative roster when returning from management, as Web does.
      DashboardSnapshot? roster;
      if (forceRefresh && token != null) {
        roster = DashboardSnapshot.fromJson(
          jsonMap(
            await _request(
              site,
              '/admin/api',
              token: token,
              body: {'action': 'list', 'refresh': true},
            ),
          ),
        );
      }
      final snapshot = DashboardSnapshot.fromJson(
        jsonMap(await _request(site, '/api/servers', token: token)),
      );
      if (roster == null) return snapshot;
      final byId = {for (final server in snapshot.servers) server.id: server};
      return DashboardSnapshot(
        servers: roster.servers
            .map(
              (server) => Server({...?byId[server.id]?.data, ...server.data}),
            )
            .toList(),
        config: snapshot.config,
        reports: snapshot.reports,
      );
    } on FormatException {
      throw const ApiFailure('服务器列表格式不受支持', kind: FailureKind.protocol);
    }
  }

  @override
  Future<String> addServer(
    MonitorSite site, {
    required String token,
    required String name,
    String group = '',
  }) async {
    if (token.isEmpty) {
      throw const ApiFailure('请先登录此站点', kind: FailureKind.authentication);
    }
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {
          'action': 'add',
          'name': name.trim(),
          'server_group': group.trim(),
        },
      ),
    );
    final id = result['id'];
    if (result['success'] != true || id is! String || id.isEmpty) {
      throw const ApiFailure('新增服务器未成功，请刷新列表确认后重试', kind: FailureKind.protocol);
    }
    return id;
  }

  @override
  Future<Server> serverForEdit(
    MonitorSite site,
    String id, {
    required String token,
  }) async {
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {'action': 'list', 'refresh': true},
      ),
    );
    final servers = result['servers'];
    if (servers is! List) {
      throw const ApiFailure('无法读取服务器配置', kind: FailureKind.protocol);
    }
    for (final item in servers) {
      final data = jsonMap(item);
      if (data['id'] == id) return Server(data);
    }
    throw const ApiFailure('未找到服务器，可能已被删除', status: 404);
  }

  @override
  Future<Map<String, dynamic>> editorSettings(
    MonitorSite site, {
    required String token,
  }) async {
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {'action': 'get_settings'},
      ),
    );
    if (result['settings'] is! Map) {
      throw const ApiFailure('无法读取站点设置', kind: FailureKind.protocol);
    }
    final settings = jsonMap(result['settings']);
    return {
      for (final key in [
        'wss_report_enabled',
        'tg_bot_token',
        'tg_notify',
        'custom_ct',
        'custom_cu',
        'custom_cm',
        'custom_bd',
        'node_1',
        'node_2',
        'node_3',
        'node_4',
        'custom_ct_name',
        'custom_cu_name',
        'custom_cm_name',
        'custom_bd_name',
        'node_1_name',
        'node_2_name',
        'node_3_name',
        'node_4_name',
      ])
        key: settings[key],
    };
  }

  @override
  Future<void> editServer(
    MonitorSite site,
    String id,
    Map<String, dynamic> fields, {
    required String token,
  }) async {
    if (token.isEmpty) {
      throw const ApiFailure('请先登录此站点', kind: FailureKind.authentication);
    }
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {...fields, 'action': 'edit', 'id': id},
      ),
    );
    if (result['success'] != true) {
      throw const ApiFailure('保存服务器失败，请重试', kind: FailureKind.protocol);
    }
  }

  @override
  Future<void> deleteServer(
    MonitorSite site,
    String id, {
    required String token,
  }) async {
    if (token.isEmpty) {
      throw const ApiFailure('请先登录此站点', kind: FailureKind.authentication);
    }
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {'action': 'delete', 'id': id},
      ),
    );
    if (result['success'] != true) {
      throw const ApiFailure('删除服务器未成功，请刷新列表确认后重试', kind: FailureKind.protocol);
    }
  }

  @override
  Future<InstallParameters> installParameters(
    MonitorSite site, {
    required String token,
  }) async {
    if (token.isEmpty) {
      throw const ApiFailure('请先登录此站点', kind: FailureKind.authentication);
    }
    final result = jsonMap(
      await _request(
        site,
        '/admin/api',
        token: token,
        body: {'action': 'get_settings'},
      ),
    );
    final secret = result['api_secret'];
    if (result['success'] == false || secret is! String || secret.isEmpty) {
      throw const ApiFailure('无法获取安装密钥，请重试获取安装命令', kind: FailureKind.protocol);
    }
    return InstallParameters(
      secret: secret,
      userAgent: '${jsonMap(result['settings'])['ua'] ?? ''}',
    );
  }

  @override
  Future<Server> detail(MonitorSite site, String id, {String? token}) async {
    final json = jsonMap(
      await _request(site, '/api/server', token: token, query: {'id': id}),
    );
    if (json['id'] == null) {
      throw const ApiFailure('服务器详情格式不受支持', kind: FailureKind.protocol);
    }
    return Server(json);
  }

  @override
  Future<List<MetricSample>> history(
    MonitorSite site,
    String id,
    HistoryRange range, {
    String? token,
  }) async {
    if (!HistoryRange.values.any((r) => r.hours == range.hours)) {
      throw const ApiFailure('不支持的历史时间范围', kind: FailureKind.protocol);
    }
    if (range.hours > 24 && token == null && site.appPassword == null) {
      throw const ApiFailure(
        '查看超过 24 小时的历史数据需要登录',
        kind: FailureKind.permission,
      );
    }
    final result = await _request(
      site,
      '/api/history/all',
      token: token,
      query: {'id': id, 'hours': range.hours},
    );
    if (result is! List) {
      throw const ApiFailure('历史数据格式不受支持', kind: FailureKind.protocol);
    }
    return result
        .map((row) {
          final data = jsonMap(row);
          final time = metricTime(data['timestamp']);
          return time == null ? null : MetricSample(time, Server(data).data);
        })
        .whereType<MetricSample>()
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  LiveConnection connect(MonitorSite site, {String? token}) {
    final url = endpoint(site, '/api/ws', {
      'subscribe': 'all',
    }).replace(scheme: 'wss');
    return SocketConnection(url, token, site.appPassword, site.userAgent);
  }

  @override
  Future<Map<String, double>?> exchangeRates() async {
    // A separate client never receives any site's authorization headers.
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        followRedirects: false,
      ),
    );
    try {
      for (final url in [
        'https://api.frankfurter.dev/v1/latest?base=CNY',
        'https://open.er-api.com/v6/latest/CNY',
      ]) {
        try {
          final result = await client.get<Object?>(url);
          final raw = jsonMap(jsonMap(result.data)['rates']);
          final rates = <String, double>{
            for (final e in raw.entries)
              if ((metricNumber(e.value) ?? 0) > 0)
                e.key: metricNumber(e.value)!,
          };
          if (rates.isNotEmpty) return {...rates, 'CNY': 1};
        } on DioException {
          continue;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() => _dio.close(force: true);
}
