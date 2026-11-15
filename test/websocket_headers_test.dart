import 'dart:io';

import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

// The certificate and key in test/fixtures are only for this loopback server.
class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = (_, host, _) => host == '127.0.0.1';
}

void main() {
  test('WSS 握手只发送所属站点的自定义 UA 和凭据', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/websocket-test-cert.pem')
      ..usePrivateKey('test/fixtures/websocket-test-key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final plainServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests =
        <
          ({Uri uri, List<String>? ua, String? password, String? authorization})
        >[];
    final serverSockets = <WebSocket>[];
    Future<void> handleRequest(HttpRequest request) async {
      requests.add((
        uri: request.uri,
        ua: request.headers[HttpHeaders.userAgentHeader],
        password: request.headers.value('X-App-Password'),
        authorization: request.headers.value(HttpHeaders.authorizationHeader),
      ));
      final socket = await WebSocketTransformer.upgrade(request);
      serverSockets.add(socket);
      socket.listen((_) {});
    }

    server.listen(handleRequest);
    plainServer.listen(handleRequest);

    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final api = WorkerApi();
        final base = 'https://127.0.0.1:${server.port}/monitor';
        Future<void> connect(LiveConnection connection) async {
          final subscription = connection.events.listen((_) {});
          try {
            await connection.ready;
          } finally {
            await connection.close();
            await subscription.cancel();
          }
        }

        try {
          await connect(
            api.connect(
              MonitorSite(
                id: 'a',
                name: 'A',
                baseUrl: base,
                appPassword: 'password-a',
                userAgent: 'custom-agent/a',
              ),
              token: 'token-a',
            ),
          );
          await connect(
            api.connect(
              MonitorSite(
                id: 'b',
                name: 'B',
                baseUrl: base,
                appPassword: 'password-b',
                userAgent: 'custom-agent/b',
              ),
            ),
          );
          // The SDK's shared default client may have been initialized outside
          // this override, so exercise the no-custom-UA case over plain WS.
          await connect(
            SocketConnection(
              Uri.parse(
                'ws://127.0.0.1:${plainServer.port}/monitor/api/ws?subscribe=all',
              ),
              null,
              null,
              null,
            ),
          );
        } finally {
          api.dispose();
        }
      }, _LoopbackHttpOverrides());

      expect(requests, hasLength(3));
      expect(requests[0].uri.path, '/monitor/api/ws');
      expect(requests[0].uri.queryParameters, {'subscribe': 'all'});
      expect(requests[0].ua, ['custom-agent/a']);
      expect(requests[0].password, 'password-a');
      expect(requests[0].authorization, 'Bearer token-a');
      expect(requests[1].ua, ['custom-agent/b']);
      expect(requests[1].password, 'password-b');
      expect(requests[1].authorization, isNull);
      expect(requests[2].ua, hasLength(1));
      expect(requests[2].ua!.single, startsWith('Dart/'));
      expect(requests[2].password, isNull);
      expect(requests[2].authorization, isNull);
    } finally {
      for (final socket in serverSockets) {
        await socket.close();
      }
      await server.close(force: true);
      await plainServer.close(force: true);
    }
  });
}
