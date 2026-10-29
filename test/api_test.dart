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
