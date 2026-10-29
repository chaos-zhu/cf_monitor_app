import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/app.dart';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/features/dashboard_page.dart';
import 'package:cf_monitor_app/widgets/common.dart';
import 'package:cf_monitor_app/widgets/metric_chart.dart';
import 'support.dart';

Future<void> launch(
  WidgetTester tester,
  FakeApi api,
  MemoryStorage storage, {
  Size size = const Size(390, 844),
  bool dark = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = dark
      ? Brightness.dark
      : Brightness.light;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(api),
        storageProvider.overrideWithValue(storage),
      ],
      child: const MonitorApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点击立即进入列表页，配置与列表统一加载，实时握手不阻塞数据展示', (tester) async {
    final config = Completer<SiteConfig>();
    final data = Completer<DashboardSnapshot>();
    final ready = Completer<void>();
    final api = FakeApi();
    api.configHandler = (_, _) => config.future;
    api.dashboardHandler = () => data.future;
    api.socketFactory = () => FakeSocket(ready: ready.future);
    await launch(tester, api, MemoryStorage([siteA]));
    await tester.tap(find.text('进入站点'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('主监控站'), findsOneWidget);
    expect(find.text('a.example.com'), findsOneWidget);
    expect(find.text('正在加载服务器…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(api.configCalls, 1);
    expect(api.dashboardCalls, 0);

    // Pulling during initial validation must not bypass authorization.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pump(const Duration(seconds: 1));
    expect(api.dashboardCalls, 0);
    config.complete(publicConfig());
    await tester.pump();
    expect(api.dashboardCalls, 1);
    expect(find.text('正在加载服务器…'), findsOneWidget);
    data.complete(snapshot());
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('正在连接'), findsOneWidget);
    expect(find.textContaining('快照'), findsNothing);
    expect(find.textContaining('实时连接暂不可用'), findsNothing);
    expect(api.dashboardCalls, 1);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('实时连接'), findsOneWidget);
    // The post-subscription reconciliation runs in the background.
    expect(api.dashboardCalls, 2);
    expect(api.configCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await finish(tester);
  });

  testWidgets('进入站点时返回，迟到的配置不会继续加载或打开登录页', (tester) async {
    final config = Completer<SiteConfig>();
    final api = FakeApi()..configHandler = (_, _) => config.future;
    await launch(tester, api, MemoryStorage([siteA]));
    await tester.tap(find.text('进入站点'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    config.complete(publicConfig({'is_public': false}));
    await tester.pumpAndSettle();
    expect(find.text('我的站点'), findsOneWidget);
    expect(find.byKey(const Key('password')), findsNothing);
    expect(api.dashboardCalls, 0);
    expect(api.sockets, isEmpty);
    await finish(tester);
  });

  testWidgets('实时握手失败仍显示列表，重试过程中保留刷新提示', (tester) async {
    final ready = Completer<void>();
    final api = FakeApi();
    api.socketFactory = () => FakeSocket(ready: ready.future);
    await launch(tester, api, MemoryStorage([siteA]));
    await click(tester, find.text('进入站点'));
    ready.completeError(StateError('websocket unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('实时连接暂不可用'), findsOneWidget);

    final retry = Completer<void>();
    api.socketFactory = () => FakeSocket(ready: retry.future);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('正在连接'), findsOneWidget);
    expect(find.textContaining('实时连接暂不可用'), findsOneWidget);
    expect(find.byType(ServerCard), findsOneWidget);
    retry.complete();
    await tester.pumpAndSettle();
    expect(find.text('实时连接'), findsOneWidget);
    expect(find.textContaining('实时连接暂不可用'), findsNothing);
    await finish(tester);
  });

  testWidgets('菜单设置默认主页，下次启动自动进入，系统返回留在站点管理且可取消', (tester) async {
    final storage = MemoryStorage([siteA, siteB]);
    final api = FakeApi();
    await launch(tester, api, storage);
    await click(tester, find.byTooltip('编辑实验室'));
    await click(tester, find.text('设为默认主页站点'));
    expect(storage.defaultSiteId, 'b');
    expect(find.byTooltip('默认主页站点'), findsOneWidget);
    expect(find.byType(ServerCard), findsNothing);
    expect(api.sockets, isEmpty);
    await finish(tester);

    final restarted = FakeApi();
    await launch(tester, restarted, storage);
    expect(find.byType(ServerCard), findsOneWidget);
    expect(restarted.sitesRequested.toSet(), {'b'});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的站点'), findsOneWidget);
    expect(restarted.sockets.single.closed, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ServerCard), findsNothing);
    await click(tester, find.byTooltip('编辑实验室'));
    await click(tester, find.text('取消默认主页站点'));
    expect(storage.defaultSiteId, isNull);
    expect(find.byTooltip('默认主页站点'), findsNothing);
    await finish(tester);

    final cancelled = FakeApi();
    await launch(tester, cancelled, storage);
    expect(find.text('我的站点'), findsOneWidget);
    expect(cancelled.configCalls, 0);
    await finish(tester);
  });

  testWidgets('默认主页 iOS 右滑返回管理页，不会再次自动进入', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final storage = MemoryStorage([siteA])..defaultSiteId = 'a';
    final api = FakeApi();
    await launch(tester, api, storage);
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.dragFrom(const Offset(2, 450), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('我的站点'), findsOneWidget);
    expect(api.sockets.single.closed, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ServerCard), findsNothing);
    await finish(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('私有默认站点复用有效凭据，凭据过期进入登录并可返回管理', (tester) async {
    final storage = MemoryStorage([siteA])
      ..defaultSiteId = 'a'
      ..tokens['a'] = jwt();
    final api = FakeApi()..settings = publicConfig({'is_public': false});
    await launch(tester, api, storage);
    expect(find.byType(ServerCard), findsOneWidget);
    expect(api.loginCalls, 0);
    await finish(tester);

    storage.tokens['a'] = jwt(expired: true);
    final expired = FakeApi()..settings = publicConfig({'is_public': false});
    await launch(tester, expired, storage);
    expect(find.byKey(const Key('password')), findsOneWidget);
    expect(expired.sockets, isEmpty);
    expect(storage.tokens['a'], isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的站点'), findsOneWidget);
    expect(find.byKey(const Key('password')), findsNothing);
    expect(storage.defaultSiteId, 'a');
    await finish(tester);
  });

  testWidgets('默认站点连接失败或需要验证时留在管理页，允许进入其他站点', (tester) async {
    for (final failure in [
      const ApiFailure('无法连接站点', kind: FailureKind.network),
      const ApiFailure('站点需要验证', kind: FailureKind.unsupported),
    ]) {
      final storage = MemoryStorage([siteA, siteB])..defaultSiteId = 'a';
      final api = FakeApi()
        ..configHandler = (site, _) async {
          if (site.id == 'a') throw failure;
          return publicConfig();
        };
      await launch(tester, api, storage);
      expect(find.text('我的站点'), findsOneWidget);
      expect(find.text(failure.message), findsOneWidget);
      expect(api.sockets, isEmpty);
      expect(api.configCalls, 1);
      await click(tester, find.text('进入站点').last);
      expect(find.byType(ServerCard), findsOneWidget);
      expect(api.sitesRequested.toSet(), {'b'});
      await finish(tester);
    }
  });

  testWidgets('删除默认站点后启动留在管理页，失效默认 ID 不发起连接', (tester) async {
    final storage = MemoryStorage([siteA, siteB]);
    await launch(tester, FakeApi(), storage);
    await click(tester, find.byTooltip('编辑主监控站'));
    await click(tester, find.text('设为默认主页站点'));
    await click(tester, find.byTooltip('编辑主监控站'));
    await click(tester, find.text('从本机删除'));
    await click(tester, find.text('删除'));
    expect(storage.defaultSiteId, isNull);
    expect(storage.sites.single.id, 'b');
    await finish(tester);

    storage.defaultSiteId = 'deleted';
    final api = FakeApi();
    await launch(tester, api, storage);
    expect(find.text('我的站点'), findsOneWidget);
    expect(api.configCalls, 0);
    await finish(tester);
  });

  testWidgets('空状态添加公开站点，首页条形列表进入详情、切换信息与长历史权限提示', (tester) async {
    final api = FakeApi();
    final storage = MemoryStorage();
    await launch(tester, api, storage);
    expect(find.text('还没有添加站点'), findsOneWidget);
    await click(tester, find.text('添加第一个站点'));
    await tester.enterText(find.byKey(const Key('site-name')), '主监控站');
    await tester.enterText(
      find.byKey(const Key('site-url')),
      'https://a.example.com',
    );
    await click(tester, find.byKey(const Key('connect-site')));
    expect(storage.sites.single.name, '主监控站');
    expect(find.byType(ServerCard), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('实时连接'), findsOneWidget);
    await click(tester, find.byType(ServerCard));
    expect(find.text('CPU 使用率'), findsOneWidget);
    expect(api.historyCalls, 1);
    await click(tester, find.text('7D'));
    expect(find.text('查看超过 24 小时的历史数据需要登录'), findsOneWidget);
    await click(tester, find.text('网络质量'));
    expect(find.text('网络速度'), findsOneWidget);
    await click(tester, find.text('系统信息'));
    expect(find.text('系统信息'), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('两个站点独立展示相同 ID 服务器，返回即关闭所属连接', (tester) async {
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA, siteB]));
    await click(tester, find.text('进入站点').first);
    expect(api.sitesRequested.toSet(), {'a'});
    expect(api.sockets.length, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(api.sockets.first.closed, isTrue);
    await click(tester, find.text('进入站点').last);
    expect(api.sitesRequested.last, 'b');
    expect(find.byType(ServerCard), findsOneWidget);
    await finish(tester);
    expect(api.sockets.last.closed, isTrue);
  });
  testWidgets('私有站点普通登录并保存凭据，不持久化密码', (tester) async {
    final api = FakeApi()..settings = publicConfig({'is_public': false});
    final storage = MemoryStorage([siteA]);
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点'));
    expect(find.byKey(const Key('password')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('password')),
      'private-password',
    );
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.loginCalls, 1);
    expect(storage.tokens['a'], isNotNull);
    expect(find.byType(ServerCard), findsOneWidget);
    expect(
      storage.sites.single.toJson().toString(),
      isNot(contains('private-password')),
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('全局 Turnstile 显示受限原因且不建立实时连接', (tester) async {
    final api = FakeApi()..settings = publicConfig({'turnstile_enabled': true});
    await launch(tester, api, MemoryStorage([siteA]));
    await click(tester, find.text('进入站点'));
    expect(find.textContaining('该站点启用了全局人机验证'), findsOneWidget);
    expect(api.sockets, isEmpty);
    expect(api.loginCalls, 0);
    await finish(tester);
  });
  testWidgets('320 宽深色大字体：站点、登录、条形列表无布局溢出', (tester) async {
    final api = FakeApi();
    await launch(
      tester,
      api,
      MemoryStorage([siteA]),
      size: const Size(320, 900),
      dark: true,
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await click(tester, find.text('进入站点'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await click(tester, find.byType(ServerCard));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('地区和历史范围保持单行，窄屏可横向选择末尾项目', (tester) async {
    final api = FakeApi()
      ..dashboardHandler = () async => snapshot([
        for (final region in ['HK', 'SG', 'KR', 'JP', 'GB', 'DE', 'FR', 'US'])
          exampleServer(id: region).merge({'region': region}),
      ]);
    await launch(
      tester,
      api,
      MemoryStorage([siteA]),
      size: const Size(320, 900),
    );
    await click(tester, find.text('进入站点'));
    expect(
      tester.getTopLeft(find.text('全部 8')).dy,
      tester.getTopLeft(find.textContaining('US 1')).dy,
    );
    final regionList = find.byKey(const Key('region-filters'));
    final regionScroll = tester.state<ScrollableState>(
      find.descendant(of: regionList, matching: find.byType(Scrollable)),
    );
    expect(regionScroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(regionList, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(regionScroll.position.pixels, greaterThan(0));
    await tester.drag(regionList, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(regionScroll.position.pixels, 0);
    for (var i = 0; i < 4; i++) {
      await tester.drag(regionList, const Offset(-240, 0));
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('US 1'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    await click(tester, find.byType(ServerCard));
    expect(
      tester.getTopLeft(find.text('10M').first).dy,
      tester.getTopLeft(find.text('7D')).dy,
    );
    await click(tester, find.text('7D'));
    expect(find.text('查看超过 24 小时的历史数据需要登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('图表当前值右对齐，图例与展开收起可用', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MetricChartCard(
              title: 'CPU',
              unit: '%',
              current: '0%',
              samples: [
                MetricSample(now, {'cpu': 0}),
              ],
              lines: [
                ChartLine.field('CPU', 'cpu'),
                ChartLine.field('缺失', 'absent'),
              ],
              initiallyExpanded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('放大图表'), findsNothing);
    final cardRight = tester.getRect(find.byType(AppPanel)).right;
    expect(tester.getRect(find.text('0%')).right, closeTo(cardRight - 40, 2));
    await click(tester, find.text('缺失'));
    await click(tester, find.text('CPU').first);
    expect(find.byType(MetricChart), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('窄屏大字体下图表长数值不换行或改变卡片高度', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const longValue = 'R 2.7 KB/s / W 50.9 KB/s';
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Column(
              children: [
                MetricChartCard(
                  title: '磁盘 IO · 吞吐',
                  unit: 'B/s',
                  current: longValue,
                  samples: const [],
                  lines: [ChartLine.field('读取', 'disk_read_bps')],
                ),
                MetricChartCard(
                  title: '磁盘 IO · 吞吐',
                  unit: 'B/s',
                  current: 'R 0 B/s',
                  samples: const [],
                  lines: [ChartLine.field('读取', 'disk_read_bps')],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cards = find.byType(MetricChartCard);
    expect(
      tester.getSize(cards.first).height,
      tester.getSize(cards.last).height,
    );
    final text = tester.renderObject<RenderParagraph>(find.text(longValue));
    expect(
      text
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: longValue.length),
          )
          .length,
      1,
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('详情加载历史时页签位置稳定，完成后保持一致', (tester) async {
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA]));
    await click(tester, find.text('进入站点'));
    await click(tester, find.byType(ServerCard));
    final initial = tester.getTopLeft(find.text('资源指标')).dy;
    final pending = Completer<List<MetricSample>>();
    api.historyHandler = (_) => pending.future;
    await tester.tap(find.text('30M'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.getTopLeft(find.text('资源指标')).dy, initial);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('资源指标')).dy, initial);
    await finish(tester);
  });

  testWidgets('下拉可刷新两页，公开站点仍可从长历史提示登录', (tester) async {
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA]));
    await click(tester, find.text('进入站点'));
    final dashboardCalls = api.dashboardCalls;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(api.dashboardCalls, greaterThan(dashboardCalls));
    await click(tester, find.byType(ServerCard));
    final historyCalls = api.historyCalls;
    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(api.historyCalls, greaterThan(historyCalls));
    await click(tester, find.text('7D'));
    await click(tester, find.text('登录站点'));
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.loginCalls, 1);
    expect(find.text('查看超过 24 小时的历史数据需要登录'), findsNothing);
    expect(find.text('资源指标'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('两页无顶部导航，右滑返回并释放当前站点连接', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA]));
    expect(find.text('点击 ··· 编辑'), findsNothing);
    await click(tester, find.text('进入站点'));
    expect(find.byType(AppBar), findsNothing);
    final status = find.ancestor(
      of: find.text('实时连接'),
      matching: find.byType(StatusPill),
    );
    expect(
      tester.getRect(status).right,
      closeTo(tester.getRect(find.byType(AppPanel).first).right, 1),
    );
    final latency = find.text('57ms 延迟');
    await tester.ensureVisible(latency);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(latency).right,
      closeTo(tester.getRect(find.byType(LatencyPanel)).center.dx - 3.5, 1),
    );
    expect(
      tester.getRect(find.text('0.0% 丢包').first).right,
      closeTo(tester.getRect(find.byType(LatencyPanel)).right - 10, 1),
    );
    await click(tester, find.byType(ServerCard));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('快照'), findsNothing);
    await tester.dragFrom(const Offset(2, 450), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.dragFrom(const Offset(2, 450), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('我的站点'), findsOneWidget);
    expect(api.sockets.single.closed, isTrue);
    await finish(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
