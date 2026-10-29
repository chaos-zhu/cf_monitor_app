import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/core/session.dart';
import 'support.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  final base = DateTime(2026, 10, 29, 12);
  late FakeApi api;
  late MonitorSession session;
  setUp(() {
    api = FakeApi();
    api.dashboardHandler = () async => snapshot([exampleServer(time: base)]);
    session = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      now: () => base,
    );
  });
  tearDown(() async {
    session.dispose();
    await flush();
  });
  LiveUpdate update(int seconds, Map<String, dynamic> data) => LiveUpdate(
    'same-id',
    [MetricSample(base.add(Duration(seconds: seconds)), data)],
  );

  test('保存站点摘要较慢时，列表加载完成且实时连接不等待本机写入', () async {
    final save = Completer<void>();
    final live = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      onSnapshot: (_, _) => save.future,
    );
    try {
      await live.start();
      await flush();
      expect(save.isCompleted, isFalse);
      expect(live.loading, isFalse);
      expect(live.servers, isNotEmpty);
      expect(live.realtime, isTrue);
      expect(api.sockets, hasLength(1));
      save.complete();
      await flush();
    } finally {
      if (!save.isCompleted) save.complete();
      live.dispose();
    }
  });

  test('仅建立当前站点连接，详情订阅切换及暂停恢复正确', () async {
    await session.start();
    await flush();
    expect(api.sockets.length, 1);
    expect(api.sockets.single.sent.last['scope'], 'all');
    session.setServerScope('same-id');
    expect(api.sockets.single.sent.last['ids'], ['same-id']);
    expect(api.sockets.single.sent.last['scope'], 'same-id');
    session.setServerScope(null);
    expect(api.sockets.single.sent.last['scope'], 'all');
    session.suspend();
    await flush();
    expect(api.sockets.single.closed, isTrue);
    expect(session.realtime, isFalse);
    await session.resume();
    await flush();
    expect(api.sockets.length, 2);
    expect(api.sitesRequested.toSet(), {'a'});
  });
  test('乱序增量不回退，0 不丢失，报告时间不使用当前查看时间', () async {
    await session.start();
    await flush();
    session.applyUpdates([
      update(10, {'cpu': 60, 'ram_used': 1200}),
      update(5, {'cpu': 90}),
      update(11, {'cpu': 0}),
    ]);
    final server = session.server('same-id')!;
    expect(server.number('cpu'), 0);
    expect(server.number('ram_used'), 1200);
    expect(server.name, 'TX-香港');
    expect(server.reportTime, base.add(const Duration(seconds: 11)));
    expect(session.recent['same-id']!.length, 3);
    api.sockets.single.emit({
      'type': 'batchUpdate',
      'ts': base.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
      'updates': [
        {
          'serverId': 'same-id',
          'samples': [
            {
              'ts': base
                  .add(const Duration(seconds: 12))
                  .millisecondsSinceEpoch,
              'data': {'cpu': 33},
            },
          ],
        },
      ],
    });
    expect(session.server('same-id')!.number('cpu'), 33);
    expect(
      session.server('same-id')!.reportTime,
      base.add(const Duration(seconds: 20)),
    );
  });
  test('刷新前及刷新中到达的 WS 字段均不被过期 REST 覆盖', () async {
    await session.start();
    await flush();
    session.applyUpdates([
      update(10, {'cpu': 60}),
    ]);
    final pending = Completer<DashboardSnapshot>();
    api.dashboardHandler = () => pending.future;
    final refresh = session.refresh();
    session.applyUpdates([
      update(12, {'ram_used': 1500}),
    ]);
    pending.complete(
      snapshot([
        exampleServer(time: base).merge({'name': '新名称'}),
      ]),
    );
    await refresh;
    final server = session.server('same-id')!;
    expect(server.number('cpu'), 60);
    expect(server.number('ram_used'), 1500);
    expect(server.name, '新名称');
  });
  test('详情保留新静态信息及最新指标，合并详情回放', () async {
    await session.start();
    await flush();
    session.applyUpdates([
      update(10, {'cpu': 65}),
    ]);
    session.mergeDetail(
      exampleServer(time: base).merge({
        'name': '详情名称',
        'cpu_info': '新 CPU',
        'latestReportUpdates': [
          {
            'serverId': 'same-id',
            'reportTs': base
                .add(const Duration(seconds: 12))
                .millisecondsSinceEpoch,
            'samples': [
              {
                'ts': base
                    .add(const Duration(seconds: 12))
                    .millisecondsSinceEpoch,
                'data': {'ram_used': 1600},
              },
            ],
          },
        ],
      }),
    );
    final server = session.server('same-id')!;
    expect(server.name, '详情名称');
    expect(server.text('cpu_info'), '新 CPU');
    expect(server.number('cpu'), 65);
    expect(server.number('ram_used'), 1600);
  });
  test('新 REST 快照后到达的旧帧只保留历史，不回退当前指标', () async {
    await session.start();
    await flush();
    session.applyUpdates([
      update(5, {'cpu': 55}),
    ]);
    api.dashboardHandler = () async => snapshot([
      exampleServer(time: base.add(const Duration(seconds: 30)), cpu: 70),
    ]);
    await session.refresh();
    session.applyUpdates([
      update(15, {'cpu': 45}),
    ]);
    expect(session.server('same-id')!.number('cpu'), 70);
    expect(session.recent['same-id']!.length, 2);
  });
  test('详情不带线路窗口时保留列表窗口，显式空窗口仍可更新', () async {
    await session.start();
    await flush();
    final ping = session.server('same-id')!.data['ping'];
    final loss = session.server('same-id')!.data['loss'];
    final detail = {...exampleServer(time: base).data}
      ..remove('ping')
      ..remove('loss');
    session.mergeDetail(Server(detail));
    expect(session.server('same-id')!.data['ping'], ping);
    expect(session.server('same-id')!.data['loss'], loss);
    session.mergeDetail(Server({...detail, 'ping': [], 'loss': []}));
    expect(session.server('same-id')!.data['ping'], isEmpty);
    expect(session.server('same-id')!.data['loss'], isEmpty);
  });
  test('样本有上限，未知服务器和畸形消息不污染当前站点', () async {
    await session.start();
    await flush();
    session.applyUpdates(
      List.generate(550, (i) => update(i + 1, {'cpu': i % 100})),
    );
    session.applyUpdates([
      LiveUpdate('unknown', [
        MetricSample(base, {'cpu': 99}),
      ]),
    ]);
    api.sockets.single.controller.add('bad json');
    expect(session.recent['same-id']!.length, 500);
    expect(session.servers.length, 1);
    expect(session.recent.containsKey('unknown'), isFalse);
  });
  test('鉴权失效清理登录并关闭实时连接，手动登录可恢复', () async {
    var cleared = false;
    session.dispose();
    session = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      token: jwt(),
      onAuthExpired: () async {
        cleared = true;
      },
    );
    await session.start();
    await flush();
    api.dashboardHandler = () async =>
        throw const ApiFailure('登录失效', kind: FailureKind.authentication);
    await session.refresh();
    await flush();
    expect(session.needsLogin, isTrue);
    expect(session.token, isNull);
    expect(cleared, isTrue);
    expect(api.sockets.single.closed, isTrue);
    api.dashboardHandler = () async => snapshot([exampleServer(time: base)]);
    await session.authorize(publicConfig({'authorization': true}), jwt());
    await flush();
    expect(session.needsLogin, isFalse);
    expect(session.realtime, isTrue);
  });
  test('全局验证拒绝连接，缓存写入失败不阻断数据', () async {
    session.dispose();
    session = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig({'turnstile_enabled': true}),
    );
    await session.start();
    expect(session.unsupported, isTrue);
    expect(api.sockets, isEmpty);
    session.dispose();
    session = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      onSnapshot: (_, _) async => throw StateError('disk'),
    );
    await session.start();
    await flush();
    expect(session.servers, isNotEmpty);
    expect(session.error, isNull);
  });
  test('暂停或销毁后迟到请求不更新状态、不重新连接', () async {
    final pending = Completer<DashboardSnapshot>();
    api.dashboardHandler = () => pending.future;
    final starting = session.start();
    session.suspend();
    pending.complete(snapshot());
    await starting;
    await flush();
    expect(session.servers, isEmpty);
    expect(api.sockets, isEmpty);
  });
  testWidgets('汇总网速每秒统一更新，多服务器推送不会逐条改变显示', (tester) async {
    var current = base;
    api.dashboardHandler = () async => snapshot([
      exampleServer(time: base),
      exampleServer(id: 'second', time: base),
      exampleServer(
        id: 'offline',
        time: base.subtract(const Duration(minutes: 5)),
      ).merge({'net_in_speed': 999999, 'net_out_speed': 999999}),
    ]);
    final live = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      now: () => current,
    );
    await live.start();
    await tester.pump();
    expect(live.summarySpeed, (download: 140.0, upload: 136.0));

    void emit(String id, int millis, double download, double upload) {
      api.sockets.single.emit({
        'type': 'batchUpdate',
        'ts': base.add(Duration(milliseconds: millis)).millisecondsSinceEpoch,
        'updates': [
          {
            'serverId': id,
            'samples': [
              {
                'ts': base
                    .add(Duration(milliseconds: millis))
                    .millisecondsSinceEpoch,
                'data': {'net_in_speed': download, 'net_out_speed': upload},
              },
            ],
          },
        ],
      });
    }

    emit('same-id', 100, 100, 200);
    emit('second', 200, 300, 400);
    emit('same-id', 300, 500, 600);
    expect(live.server('same-id')!.number('net_in_speed'), 500);
    expect(live.recent['same-id'], hasLength(2));
    expect(live.summarySpeed, (download: 140.0, upload: 136.0));
    await tester.pump(const Duration(milliseconds: 999));
    expect(live.summarySpeed, (download: 140.0, upload: 136.0));
    current = base.add(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(live.summarySpeed, (download: 800.0, upload: 1000.0));

    emit('second', 1100, 0, 0);
    emit('same-id', 1200, 0, 0);
    expect(live.summarySpeed, (download: 800.0, upload: 1000.0));
    current = base.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(live.summarySpeed, (download: 0.0, upload: 0.0));

    live.suspend();
    await tester.pump(const Duration(seconds: 2));
    expect(live.summarySpeed, (download: 0.0, upload: 0.0));
    api.dashboardHandler = () async => snapshot([
      exampleServer(time: current),
      exampleServer(id: 'second', time: current),
    ]);
    await live.resume();
    await tester.pump();
    expect(live.summarySpeed, (download: 140.0, upload: 136.0));
    live.dispose();
    await tester.pump();
  });

  testWidgets('下拉刷新立即更新汇总网速，服务器过期离线后下个 tick 清零', (tester) async {
    var current = base;
    final live = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig(),
      now: () => current,
    );
    await live.start();
    await tester.pump();
    expect(live.summarySpeed, (download: 70.0, upload: 68.0));
    api.dashboardHandler = () async => snapshot([
      exampleServer(
        time: base,
      ).merge({'net_in_speed': 100, 'net_out_speed': 200}),
    ]);
    await live.refresh();
    expect(live.summarySpeed, (download: 100.0, upload: 200.0));
    current = base.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(live.online, 0);
    expect(live.summarySpeed, (download: 0.0, upload: 0.0));
    live.dispose();
    await tester.pump();
  });

  testWidgets('心跳格式与站点连接时长限制，恢复前台不自动绕过时限', (tester) async {
    final live = MonitorSession(
      api: api,
      site: siteA,
      config: publicConfig({'frontend_ws_timeout_minutes': 1}),
      now: () => base,
    );
    await live.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 25));
    expect(api.sockets.single.sent.last, {'type': 'ping'});
    api.sockets.single.emit({'type': 'pong'});
    await tester.pump(const Duration(seconds: 35));
    expect(live.lifetimeEnded, isTrue);
    expect(api.sockets.single.closed, isTrue);
    live.suspend();
    await live.resume();
    await tester.pump();
    expect(api.sockets.length, 1);
    live.dispose();
    await tester.pump();
  });
  testWidgets('断线后复核配置，新增全局验证停止重连和轮询', (tester) async {
    final live = MonitorSession(api: api, site: siteA, config: publicConfig());
    await live.start();
    await tester.pump();
    api.settings = publicConfig({'turnstile_enabled': true});
    api.sockets.single.controller.addError(StateError('offline'));
    await tester.pump(const Duration(seconds: 2));
    expect(live.unsupported, isTrue);
    final calls = api.dashboardCalls;
    await tester.pump(const Duration(minutes: 2));
    expect(api.sockets.length, 1);
    expect(api.dashboardCalls, calls);
    live.dispose();
    await tester.pump();
  });
}
