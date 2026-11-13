import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'support.dart';

class StubAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Object? Function(RequestOptions) reply = (_) => {
    'is_public': true,
    'authorization': false,
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late StubAdapter transport;
  late WorkerApi api;
  setUp(() {
    transport = StubAdapter();
    api = WorkerApi(dio: Dio()..httpClientAdapter = transport);
  });
  tearDown(() => api.dispose());
  test('App 口令按站点发送，受保护历史可用，错误口令被拒绝', () async {
    final protectedSite = siteA.copyWith(
      appPassword: '1234567890abcdef',
      userAgent: 'custom-agent/1',
    );
    transport.status = 404;
    await api.validateAppPassword(protectedSite);
    expect(
      transport.requests.single.headers['X-App-Password'],
      '1234567890abcdef',
    );
    expect(transport.requests.single.uri.queryParameters['hours'], '48');
    expect(transport.requests.single.headers['User-Agent'], 'custom-agent/1');
    transport.status = 401;
    await expectLater(
      api.validateAppPassword(protectedSite),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.authentication,
        ),
      ),
    );
    transport.status = 200;
    transport.reply = (_) => [];
    await api.history(protectedSite, 'server', HistoryRange.values.last);
    expect(
      transport.requests.last.headers['X-App-Password'],
      '1234567890abcdef',
    );
    transport.reply = (_) => {'is_public': true, 'authorization': false};
    await api.config(siteB);
    expect(
      transport.requests.last.headers.containsKey('X-App-Password'),
      isFalse,
    );
    expect(transport.requests.last.headers.containsKey('User-Agent'), isFalse);
    WorkerApi.ensureSupported(
      publicConfig({'turnstile_enabled': true}),
      hasAppPassword: true,
    );
    expect(
      () => WorkerApi.ensureSupported(
        publicConfig({'turnstile_enabled': true}),
        login: true,
        hasAppPassword: true,
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('删除使用所属站点凭据和服务器 ID，失败响应不当作成功', () async {
    transport.reply = (_) => {'success': true};
    await api.deleteServer(siteB, 'server-id', token: 'token-b');
    expect(
      transport.requests.single.uri.toString(),
      'https://b.example.com/admin/api',
    );
    expect(transport.requests.single.method, 'POST');
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer token-b',
    );
    expect(transport.requests.single.data, {
      'action': 'delete',
      'id': 'server-id',
    });
    transport.reply = (_) => {'success': false};
    await expectLater(
      api.deleteServer(siteA, 'server-id', token: 'a'),
      throwsA(isA<ApiFailure>()),
    );
    transport.status = 401;
    await expectLater(
      api.deleteServer(siteA, 'server-id', token: 'a'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.authentication,
        ),
      ),
    );
  });

  test('强制刷新以管理接口返回的服务器名单为准，补齐新增并排除已删除的缓存记录', () async {
    transport.reply = (request) => request.path.endsWith('/admin/api')
        ? {
            'servers': [
              {'id': 'existing', 'name': 'new-name'},
              {'id': 'created', 'name': 'added', 'last_updated': 0},
            ],
          }
        : {
            'servers': [
              {
                'id': 'existing',
                'name': 'old-name',
                'ping': [
                  {'ct': 58},
                ],
              },
              {'id': 'deleted', 'name': 'stale'},
            ],
            'sysConfig': {'show_price': false},
          };
    final data = await api.dashboard(siteA, token: 'a', forceRefresh: true);
    expect(transport.requests.first.data, {'action': 'list', 'refresh': true});
    expect(transport.requests.first.headers['Authorization'], 'Bearer a');
    expect(data.servers.map((s) => s.id), ['existing', 'created']);
    expect(data.servers.first.name, 'new-name');
    expect(data.servers.first.data['ping'], isNotEmpty);
    expect(data.servers.last.isOnline(), isFalse);
    expect(data.config['show_price'], isFalse);
  });
  test('安装参数从所属站点获取，保留密钥和 UA，缺少密钥不生成命令', () async {
    final prefixed = siteA.copyWith(
      baseUrl: 'https://a.example.com:8443/monitor',
    );
    transport.reply = (_) => {
      'success': true,
      'api_secret': 'test-secret',
      'settings': {'ua': 'custom-agent', 'site_title': 'ignored'},
    };
    final parameters = await api.installParameters(prefixed, token: 'token-a');
    expect(parameters.secret, 'test-secret');
    expect(parameters.userAgent, 'custom-agent');
    expect(
      transport.requests.single.uri.toString(),
      'https://a.example.com:8443/monitor/admin/api',
    );
    expect(transport.requests.single.data, {'action': 'get_settings'});
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer token-a',
    );
    expect(transport.requests.single.followRedirects, isFalse);
    transport.reply = (_) => {'is_public': true, 'authorization': false};
    await api.config(siteB);
    expect(
      transport.requests.last.headers.containsKey('Authorization'),
      isFalse,
    );
    transport.reply = (_) => {'success': true, 'settings': {}};
    await expectLater(
      api.installParameters(siteA, token: 'token-a'),
      throwsA(isA<ApiFailure>()),
    );
    transport.status = 401;
    await expectLater(
      api.installParameters(siteA, token: 'token-a'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.authentication,
        ),
      ),
    );
  });
  test('新增服务器使用所属站点管理接口和独立凭据，严格校验创建结果', () async {
    transport.reply = (_) => {
      'success': true,
      'id': 'new-id',
      'message': 'serverAdded',
    };
    final prefixed = siteA.copyWith(
      baseUrl: 'https://a.example.com:8443/monitor',
    );
    expect(
      await api.addServer(
        prefixed,
        token: 'token-a',
        name: ' 香港 ',
        group: ' Asia ',
      ),
      'new-id',
    );
    final request = transport.requests.single;
    expect(
      request.uri.toString(),
      'https://a.example.com:8443/monitor/admin/api',
    );
    expect(request.method, 'POST');
    expect(request.headers['Authorization'], 'Bearer token-a');
    expect(request.data, {
      'action': 'add',
      'name': '香港',
      'server_group': 'Asia',
    });
    expect(request.followRedirects, isFalse);
    transport.reply = (_) => {'is_public': true, 'authorization': false};
    await api.config(siteB);
    expect(
      transport.requests.last.headers.containsKey('Authorization'),
      isFalse,
    );
    transport.reply = (_) => {'success': false, 'error': 'serverAddFailed'};
    await expectLater(
      api.addServer(siteA, token: 'a', name: 'HK'),
      throwsA(isA<ApiFailure>()),
    );
    transport.status = 401;
    await expectLater(
      api.addServer(siteA, token: 'a', name: 'HK'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.authentication,
        ),
      ),
    );
  });
  test('反代路径、端口及查询保留，Bearer 凭据按请求隔离且禁止重定向', () async {
    final prefixed = siteA.copyWith(
      baseUrl: 'https://a.example.com:8443/monitor',
    );
    await api.config(prefixed, token: 'token-a');
    await api.config(siteB);
    expect(
      transport.requests.first.uri.toString(),
      'https://a.example.com:8443/monitor/api/config',
    );
    expect(transport.requests.first.headers['Authorization'], 'Bearer token-a');
    expect(
      transport.requests.last.headers.containsKey('Authorization'),
      isFalse,
    );
    expect(transport.requests.first.followRedirects, isFalse);
    expect(
      WorkerApi.endpoint(prefixed, '/api/server', {
        'id': 'a b/?',
      }).queryParameters['id'],
      'a b/?',
    );
  });
  test('普通登录精确提交接口，验证站点不提交密码', () async {
    transport.reply = (r) => r.path.endsWith('/admin/api')
        ? {'token': 'valid-jwt'}
        : {'is_public': false, 'authorization': false};
    expect(await api.login(siteA, 'admin', 'secret'), 'valid-jwt');
    expect(transport.requests.last.method, 'POST');
    expect(transport.requests.last.data, {
      'action': 'login',
      'username': 'admin',
      'password': 'secret',
    });
    transport.requests.clear();
    transport.reply = (_) => {
      'is_public': false,
      'authorization': false,
      'turnstile_login_enabled': true,
    };
    await expectLater(
      api.login(siteA, 'admin', 'secret'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.unsupported,
        ),
      ),
    );
    expect(transport.requests.length, 1);
  });
  test('匿名长历史在本机拒绝，短历史排序、零值与缺失保留', () async {
    await expectLater(
      api.history(siteA, 'id', HistoryRange.values.last),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.permission),
      ),
    );
    expect(transport.requests, isEmpty);
    transport.reply = (_) => [
      {'timestamp': 1700000002, 'cpu': 0},
      {'timestamp': 1700000001, 'ram_used': 20},
      {'cpu': 100},
    ];
    final samples = await api.history(siteA, 'id', HistoryRange.values.first);
    expect(samples.length, 2);
    expect(samples.first.value('cpu'), isNull);
    expect(samples.last.value('cpu'), 0);
    expect(transport.requests.single.uri.queryParameters['hours'], '0.167');
  });
  test('认证、验证、重定向及非监控站点返回可识别错误', () async {
    for (final pair in [
      (401, FailureKind.authentication),
      (403, FailureKind.unsupported),
      (302, FailureKind.server),
    ]) {
      transport.status = pair.$1;
      await expectLater(
        api.config(siteA),
        throwsA(isA<ApiFailure>().having((e) => e.kind, 'kind', pair.$2)),
      );
    }
    transport.status = 200;
    transport.reply = (_) => '<html>not worker</html>';
    await expectLater(
      api.config(siteA),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
      ),
    );
  });
}
