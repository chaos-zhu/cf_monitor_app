import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/app.dart';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/core/installation.dart';
import 'package:cf_monitor_app/features/dashboard_page.dart';
import 'package:cf_monitor_app/widgets/common.dart';
import 'package:cf_monitor_app/widgets/metric_chart.dart';
import 'package:cf_monitor_app/widgets/server_list_tile.dart';
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

Future<void> finishInstallation(WidgetTester tester) async {
  final button = find.byKey(const Key('finish-server'));
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('server-installation')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await click(tester, button);
}

void main() {
  testWidgets('切换列表不额外请求或重连，首屏展示多台且保留详情和长按菜单', (tester) async {
    final api = FakeApi();
    api.dashboardHandler = () async => snapshot([
      for (var i = 0; i < 6; i++)
        exampleServer(id: 'server-$i').merge({'name': '服务器 $i'}),
    ]);
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    await launch(tester, api, storage);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    await click(tester, find.text('进入站点'));
    final calls = api.dashboardCalls;
    final sockets = api.sockets.length;
    final summaryRect = tester.getRect(find.byType(AppPanel).first);
    final filtersRect = tester.getRect(find.byKey(const Key('region-filters')));
    final toggle = find.byKey(const Key('toggle-server-layout'));
    expect(
      tester.getCenter(toggle).dx,
      greaterThan(tester.getCenter(find.byKey(const Key('add-server'))).dx),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(api.dashboardCalls, calls);
    expect(api.sockets, hasLength(sockets));
    expect(find.byType(ServerCard), findsNothing);
    expect(storage.compactLayout, isTrue);
    expect(tester.getRect(find.byType(AppPanel).first), summaryRect);
    expect(
      tester.getRect(find.byKey(const Key('region-filters'))),
      filtersRect,
    );
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('a:server-1'))).dy,
      lessThanOrEqualTo(810),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('a:server-2'))).dy,
      lessThan(810),
    );
    expect(find.text('CPU'), findsAtLeastNWidgets(2));
    final sampleTime = DateTime.now()
        .add(const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    api.sockets.single.emit({
      'type': 'batchUpdate',
      'ts': sampleTime,
      'updates': [
        {
          'serverId': 'server-0',
          'samples': [
            {
              'ts': sampleTime,
              'data': {'cpu': 94.7},
            },
          ],
        },
      ],
    });
    await tester.pump();
    expect(find.text('94.7%'), findsOneWidget);
    await tester.longPress(find.byType(ServerListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await click(tester, find.text('安装命令'));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      contains("-id='server-0'"),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await click(tester, find.byType(ServerListTile).first);
    expect(find.text('系统信息'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerListTile), findsWidgets);
    await tester.scrollUntilVisible(
      toggle,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await click(tester, toggle);
    expect(find.byType(ServerListTile), findsNothing);
    expect(find.byType(ServerCard), findsWidgets);
    expect(storage.compactLayout, isFalse);
    await finish(tester);
  });

  testWidgets('列表布局在切换站点和重启后保留，仍只展示当前站点服务器', (tester) async {
    final storage = MemoryStorage([siteA, siteB]);
    final api = FakeApi();
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点').first);
    await click(tester, find.byKey(const Key('toggle-server-layout')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await click(tester, find.text('进入站点').last);
    expect(find.byKey(const ValueKey('b:same-id')), findsOneWidget);
    expect(find.byKey(const ValueKey('a:same-id')), findsNothing);
    expect(find.byType(ServerListTile), findsOneWidget);
    await finish(tester);
    await launch(tester, FakeApi(), storage);
    await click(tester, find.text('进入站点').first);
    expect(find.byType(ServerListTile), findsOneWidget);
    await finish(tester);
  });

  testWidgets('紧凑列表窄屏深色大字体保留 IP 标识和操作，长线路名称可横滑', (tester) async {
    final api = FakeApi();
    api.settings = publicConfig({'custom_ct_name': '非常长的自定义线路名称'});
    api.dashboardHandler = () async => snapshot([
      exampleServer().merge({
        'name': '很长的服务器名称需要截断并保留IPv4和IPv6标识',
        'ip_v6': '1',
        'net_in_speed': 9876543210123,
        'net_out_speed': 8765432101234,
      }),
    ]);
    final storage = MemoryStorage([siteA.copyWith(name: '很长的站点名称需要省略显示')])
      ..compactLayout = true;
    await launch(
      tester,
      api,
      storage,
      size: const Size(320, 900),
      scale: 1.5,
      dark: true,
    );
    await click(tester, find.text('进入站点'));
    expect(find.text('IPv4/6'), findsOneWidget);
    expect(find.byKey(const Key('add-server')).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('toggle-server-layout')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(ServerListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('返回列表强制刷新新服务器，长按可再次进入安装命令页', (tester) async {
    final api = FakeApi();
    api.dashboardHandler = () async => snapshot([
      exampleServer(),
      if (api.forcedRefreshes.where((force) => force).length >= 2)
        Server({'id': 'new-server-id', 'name': '新增机器'}),
    ]);
    await launch(tester, api, MemoryStorage([siteA])..tokens['a'] = jwt());
    await click(tester, find.text('进入站点'));
    await click(tester, find.byKey(const Key('add-server')));
    await tester.enterText(find.byKey(const Key('server-name')), '新增机器');
    await click(tester, find.byKey(const Key('submit-server')));
    expect(api.forcedRefreshes.where((force) => force).length, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(api.forcedRefreshes.where((force) => force).length, 2);
    final card = find.byKey(const ValueKey('a:new-server-id'));
    await tester.scrollUntilVisible(
      card,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.longPressAt(tester.getTopLeft(card) + const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await click(tester, find.text('安装命令'));
    expect(find.text('服务器已创建'), findsNothing);
    final command = tester
        .widget<SelectableText>(find.byKey(const Key('install-command')))
        .data!;
    expect(command, contains("-id='new-server-id'"));
    expect(api.addedServers, hasLength(1));
    expect(api.installRequests, hasLength(2));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CustomScrollView), findsOneWidget);
    await finish(tester);
  });

  testWidgets('长按安装命令未登录先登录，取消不读取安装密钥', (tester) async {
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA]));
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('安装命令'));
    expect(find.byKey(const Key('password')), findsOneWidget);
    expect(api.installRequests, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('安装命令'));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.installRequests.single.siteId, 'a');
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      contains("-id='same-id'"),
    );
    expect(api.addedServers, isEmpty);
    await finish(tester);
  });
  testWidgets('编辑页立即显示并在读取服务器详情时展示加载状态', (tester) async {
    final detail = Completer<Server>();
    final api = FakeApi()..serverForEditHandler = () => detail.future;
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('编辑服务器'), findsOneWidget);
    expect(find.text('正在加载服务器配置'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    detail.complete(exampleServer(id: 'same-id'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-name')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('编辑表单展示站点默认节点提示且保存时不覆盖继承值', (tester) async {
    final api = FakeApi()
      ..editableServer = Server({'id': 'same-id', 'name': 'Original'})
      ..editSettings = {
        'wss_report_enabled': true,
        'custom_ct': 'site.example.com:443',
        'custom_cu': '',
        'node_1': 'node.example.com',
      };
    await launch(tester, api, MemoryStorage([siteA])..tokens['a'] = jwt());
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('编辑'));
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('server-edit-form')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-custom_ct')),
      400,
      scrollable: scrollable,
    );
    TextFormField field(String key) =>
        tester.widget<TextFormField>(find.byKey(Key('edit-$key')));
    String? hint(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key('edit-$key')),
            matching: find.byType(TextField),
          ),
        )
        .decoration!
        .hintText;
    expect(hint('custom_ct'), 'site.example.com:443');
    expect(field('custom_ct').controller!.text, isEmpty);
    expect(hint('custom_cu'), 'gd-cu-dualstack.ip.zstaticcdn.com');
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-node_1')),
      300,
      scrollable: scrollable,
    );
    expect(hint('node_1'), 'node.example.com');
    await click(tester, find.byKey(const Key('save-server-edit')));
    expect(api.edits.single['custom_ct'], isEmpty);
    expect(api.edits.single['node_1'], isEmpty);
    await finish(tester);
  });

  testWidgets('长按编辑读取完整配置，保存后刷新且保留未修改字段', (tester) async {
    final api = FakeApi()
      ..editableServer = Server({
        'id': 'same-id',
        'name': 'Original',
        'server_group': 'Asia',
        'region': 'US',
        'region_override': 'CN',
        'traffic_limit': '500',
        'traffic_alert_percent': 75,
        'custom_ct': 'example.com:443',
        'auto_update': '1',
        'is_hidden': '1',
        'reset_day': 12,
      });
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('编辑'));
    expect(find.byKey(const Key('edit-name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit-name')), 'Updated');
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-billing_cycle')),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('server-edit-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await click(tester, find.byKey(const Key('edit-billing_cycle')));
    await click(tester, find.text('年').last);
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-server-edit')),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('server-edit-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await click(tester, find.byKey(const Key('save-server-edit')));
    expect(api.edits, hasLength(1));
    expect(api.edits.single['name'], 'Updated');
    expect(api.edits.single['billing_cycle'], 'year');
    expect(api.edits.single['region'], 'CN');
    expect(api.edits.single['traffic_limit'], '500');
    expect(api.edits.single['traffic_alert_percent'], 75);
    expect(api.edits.single['custom_ct'], 'example.com:443');
    expect(api.edits.single['auto_update'], '1');
    expect(api.edits.single['is_hidden'], '1');
    expect(api.edits.single['reset_day'], 12);
    expect(api.edits.single['site'], 'a');
    expect(api.forcedRefreshes.last, isTrue);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('编辑保存时登录失效保留草稿，重新登录后提交', (tester) async {
    final api = FakeApi();
    var attempts = 0;
    api.editServerHandler = () async {
      attempts++;
      if (attempts == 1) {
        throw const ApiFailure(
          '登录失效',
          status: 401,
          kind: FailureKind.authentication,
        );
      }
    };
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    await launch(tester, api, storage, size: const Size(320, 900), scale: 1.3);
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('编辑'));
    await tester.enterText(find.byKey(const Key('edit-name')), 'Updated');
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-server-edit')),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('server-edit-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await click(tester, find.byKey(const Key('save-server-edit')));
    expect(find.text('重新登录并保存'), findsOneWidget);
    await click(tester, find.byKey(const Key('save-server-edit')));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.edits.single['name'], 'Updated');
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('GitHub 代理可下拉选择或输入，非法输入禁用命令，Docker 不使用代理', (tester) async {
    final api = FakeApi();
    await launch(tester, api, MemoryStorage([siteA])..tokens['a'] = jwt());
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('安装命令'));
    await click(tester, find.byKey(const Key('github-proxy-presets')));
    await click(tester, find.text('https://ghfast.top/'));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      contains("--install-ghproxy='https://ghfast.top'"),
    );
    await tester.enterText(
      find.byKey(const Key('github-proxy')),
      'https://custom.example.com/gh/',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      contains(
        'https://custom.example.com/gh/https://raw.githubusercontent.com',
      ),
    );
    await tester.enterText(find.byKey(const Key('github-proxy')), 'invalid');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-install-command')), findsNothing);
    expect(find.textContaining('请输入有效的 HTTP'), findsOneWidget);
    await click(tester, find.text('Docker'));
    expect(
      tester.widget<TextField>(find.byKey(const Key('github-proxy'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      startsWith('docker run'),
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('长按删除需确认，失败保留服务器，成功刷新且仅删除所属站点', (tester) async {
    final api = FakeApi();
    final storage = MemoryStorage([siteA, siteB])..tokens['b'] = jwt();
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点').last);
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('删除'));
    await click(tester, find.text('取消'));
    expect(api.deletedServers, isEmpty);
    api.deleteServerHandler = () async => throw const ApiFailure('删除失败');
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('删除'));
    await click(tester, find.byKey(const Key('confirm-delete-server')));
    expect(find.text('删除失败'), findsOneWidget);
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    api.deleteServerHandler = () async {
      api.dashboardHandler = () async => snapshot([]);
    };
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('删除'));
    await click(tester, find.byKey(const Key('confirm-delete-server')));
    expect(api.deletedServers.last.siteId, 'b');
    expect(api.deletedServers.last.id, 'same-id');
    expect(api.deletedServers.last.token, storage.tokens['b']);
    expect(api.forcedRefreshes.last, isTrue);
    expect(find.byType(ServerCard), findsNothing);
    expect(find.text('服务器已删除'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('删除时凭据失效需重新登录，取消不重试，登录成功仅重试当前服务器', (tester) async {
    final api = FakeApi();
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    api.deleteServerHandler = () async =>
        throw const ApiFailure('登录失效', kind: FailureKind.authentication);
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点'));
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('删除'));
    await click(tester, find.byKey(const Key('confirm-delete-server')));
    expect(find.byKey(const Key('password')), findsOneWidget);
    expect(storage.tokens['a'], isNull);
    expect(api.deletedServers, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    expect(api.deletedServers, hasLength(1));

    storage.tokens['a'] = jwt();
    await tester.longPress(find.byType(ServerCard));
    await tester.pumpAndSettle();
    await click(tester, find.text('删除'));
    await click(tester, find.byKey(const Key('confirm-delete-server')));
    expect(api.deletedServers, hasLength(2));
    api.deleteServerHandler = () async {
      api.dashboardHandler = () async => snapshot([]);
    };
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.deletedServers, hasLength(3));
    expect(api.deletedServers.last.siteId, 'a');
    expect(api.deletedServers.last.id, 'same-id');
    expect(api.deletedServers.last.token, storage.tokens['a']);
    expect(find.byType(ServerCard), findsNothing);
    expect(api.forcedRefreshes.last, isTrue);
    await finish(tester);
  });

  testWidgets('新增入口先登录，取消留在列表，登录成功可创建并刷新所属站点', (tester) async {
    final api = FakeApi();
    final storage = MemoryStorage([siteA, siteB]);
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点').first);
    await click(tester, find.byKey(const Key('add-server')));
    expect(find.byKey(const Key('password')), findsOneWidget);
    expect(find.byKey(const Key('server-name')), findsNothing);
    expect(api.addedServers, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    await click(tester, find.byKey(const Key('add-server')));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(find.text('新增服务器'), findsOneWidget);
    expect(find.text('主监控站'), findsNothing);
    expect(find.textContaining('Web 后台'), findsNothing);
    expect(storage.tokens['a'], isNotNull);
    await click(tester, find.byKey(const Key('submit-server')));
    expect(find.text('请输入服务器名称'), findsOneWidget);
    expect(api.addedServers, isEmpty);
    await tester.enterText(find.byKey(const Key('server-name')), '香港 2');
    await tester.enterText(find.byKey(const Key('server-group')), 'Asia');
    final calls = api.dashboardCalls;
    await click(tester, find.byKey(const Key('submit-server')));
    expect(api.addedServers.single.siteId, 'a');
    expect(api.addedServers.single.name, '香港 2');
    expect(api.addedServers.single.group, 'Asia');
    expect(api.addedServers.single.token, storage.tokens['a']);
    expect(api.dashboardCalls, greaterThan(calls));
    expect(find.text('服务器已创建'), findsNothing);
    expect(find.byKey(const Key('install-command')), findsOneWidget);
    expect(api.installRequests.single.siteId, 'a');
    expect(api.installRequests.single.token, storage.tokens['a']);
    await finishInstallation(tester);
    expect(find.byType(ServerCard), findsOneWidget);
    await finish(tester);
  });

  testWidgets('已登录直接新增，提交期间禁止重复请求，401 重新登录后保留草稿', (tester) async {
    final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
    final api = FakeApi();
    final pending = Completer<String>();
    api.addServerHandler = (_, _, _, _) => pending.future;
    await launch(tester, api, storage);
    await click(tester, find.text('进入站点'));
    await click(tester, find.byKey(const Key('add-server')));
    expect(find.byKey(const Key('password')), findsNothing);
    await tester.enterText(find.byKey(const Key('server-name')), '草稿');
    await tester.tap(find.byKey(const Key('submit-server')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-server')));
    await tester.pump();
    expect(api.addedServers, hasLength(1));
    pending.completeError(
      const ApiFailure('登录失效', kind: FailureKind.authentication),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录失效'), findsOneWidget);
    await click(tester, find.text('重新登录并创建'));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    api.addServerHandler = (_, _, _, _) async => 'new-id';
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.addedServers, hasLength(2));
    expect(api.addedServers.last.name, '草稿');
    expect(find.byKey(const Key('install-command')), findsOneWidget);
    await finishInstallation(tester);
    expect(find.byType(ServerCard), findsOneWidget);
    await finish(tester);
  });

  testWidgets('创建后可切换系统并复制完整安装命令，小屏大字体不溢出', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final api = FakeApi();
    api.installParametersHandler = () async => const InstallParameters(
      secret: 'install-secret',
      userAgent: 'custom-agent',
    );
    await launch(
      tester,
      api,
      MemoryStorage([siteA])..tokens['a'] = jwt(),
      size: const Size(320, 900),
      scale: 1.5,
      dark: true,
    );
    await click(tester, find.text('进入站点'));
    await click(tester, find.byKey(const Key('add-server')));
    await tester.enterText(find.byKey(const Key('server-name')), '测试机器');
    await click(tester, find.byKey(const Key('submit-server')));
    final command = tester
        .widget<SelectableText>(find.byKey(const Key('install-command')))
        .data!;
    expect(command, contains("-id='new-server-id'"));
    expect(command, contains("-secret='install-secret'"));
    expect(command, contains("-ua='custom-agent'"));
    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-install-command')),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('server-installation')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await click(tester, find.byKey(const Key('copy-install-command')));
    expect(copied, command);
    await tester.scrollUntilVisible(
      find.text('Windows'),
      -200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('server-installation')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await click(tester, find.text('Windows'));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      contains('install.ps1'),
    );
    await click(tester, find.text('Docker'));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('install-command')))
          .data,
      startsWith('docker run'),
    );
    expect(api.addedServers, hasLength(1));
    expect(api.installRequests, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerCard), findsOneWidget);
    await finish(tester);
  });

  testWidgets('创建成功后获取命令失败仅重试命令，401 登录后不重复创建', (tester) async {
    final api = FakeApi();
    api.installParametersHandler = () async =>
        throw const ApiFailure('获取命令失败', kind: FailureKind.network);
    await launch(tester, api, MemoryStorage([siteA])..tokens['a'] = jwt());
    await click(tester, find.text('进入站点'));
    await click(tester, find.byKey(const Key('add-server')));
    await tester.enterText(find.byKey(const Key('server-name')), 'test');
    await click(tester, find.byKey(const Key('submit-server')));
    expect(find.text('服务器已创建'), findsNothing);
    expect(find.text('获取命令失败'), findsOneWidget);
    expect(find.byKey(const Key('submit-server')), findsNothing);
    api.installParametersHandler = () async =>
        throw const ApiFailure('登录失效', kind: FailureKind.authentication);
    await click(tester, find.text('重新获取安装命令'));
    await click(tester, find.text('重新登录并获取安装命令'));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    api.installParametersHandler = () async =>
        const InstallParameters(secret: 'secret');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(find.byKey(const Key('install-command')), findsOneWidget);
    expect(api.addedServers, hasLength(1));
    expect(api.installRequests, hasLength(3));
    await finish(tester);
  });

  testWidgets('长站点名在窄屏大字体下保留状态点和新增入口', (tester) async {
    final site = siteA.copyWith(name: '这是一个很长的站点名称需要省略显示');
    await launch(
      tester,
      FakeApi(),
      MemoryStorage([site]),
      size: const Size(320, 900),
      scale: 1.5,
    );
    await click(tester, find.text('进入站点'));
    final name = tester.widget<Text>(
      find.byKey(const Key('dashboard-site-name')),
    );
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(find.byKey(const Key('connection-dot')), findsOneWidget);
    expect(find.byKey(const Key('add-server')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('新增前凭据过期或被服务端撤销时转登录，绝不匿名创建', (tester) async {
    for (final revoked in [false, true]) {
      final storage = MemoryStorage([siteA])..tokens['a'] = jwt();
      final api = FakeApi();
      await launch(tester, api, storage);
      await click(tester, find.text('进入站点'));
      if (revoked) {
        api.configHandler = (_, _) async =>
            throw const ApiFailure('凭据失效', kind: FailureKind.authentication);
      } else {
        storage.tokens['a'] = jwt(expired: true);
      }
      await click(tester, find.byKey(const Key('add-server')));
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(find.byKey(const Key('server-name')), findsNothing);
      expect(storage.tokens['a'], isNull);
      expect(api.addedServers, isEmpty);
      await finish(tester);
    }
  });

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
    expect(find.byTooltip('正在连接'), findsOneWidget);
    expect(find.textContaining('快照'), findsNothing);
    expect(find.textContaining('实时连接暂不可用'), findsNothing);
    expect(api.dashboardCalls, 1);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('实时连接'), findsOneWidget);
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
    expect(find.byTooltip('正在连接'), findsOneWidget);
    expect(find.textContaining('实时连接暂不可用'), findsOneWidget);
    expect(find.byType(ServerCard), findsOneWidget);
    retry.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('实时连接'), findsOneWidget);
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
    expect(find.byTooltip('实时连接'), findsOneWidget);
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
  testWidgets('App 口令连接私有验证站点并在重新进入时恢复', (tester) async {
    final api = FakeApi()
      ..settings = publicConfig({
        'turnstile_enabled': true,
        'is_public': false,
      });
    final storage = MemoryStorage();
    await launch(tester, api, storage);
    await click(tester, find.text('添加第一个站点'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('连接新站点')),
      findsOneWidget,
    );
    expect(find.text('添加你的 CF Server Monitor'), findsNothing);
    await tester.enterText(find.byKey(const Key('site-name')), 'Protected');
    await tester.enterText(
      find.byKey(const Key('site-url')),
      'https://a.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('app-password')),
      '1234567890abcdef',
    );
    await tester.enterText(find.byKey(const Key('user-agent')), 'my-monitor/1');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.passwordChecks, ['1234567890abcdef']);
    expect(storage.appPasswords[storage.sites.single.id], '1234567890abcdef');
    expect(storage.userAgents[storage.sites.single.id], 'my-monitor/1');
    expect(api.loginCalls, 0);
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await click(tester, find.text('进入站点'));
    expect(find.byType(ServerCard), findsOneWidget);
    expect(api.sockets.length, 2);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('App 口令和管理员登录分开展示，登录验证只提示一次且可返回只读连接', (tester) async {
    final api = FakeApi()
      ..settings = publicConfig({'turnstile_login_enabled': true});
    final storage = MemoryStorage();
    await launch(tester, api, storage);
    await click(tester, find.text('添加第一个站点'));
    await tester.enterText(find.byKey(const Key('site-name')), 'Protected');
    await tester.enterText(
      find.byKey(const Key('site-url')),
      'https://a.example.com',
    );
    await click(tester, find.text('需要登录？输入账号密码'));
    expect(find.text('使用该站点现有的管理员账号'), findsNothing);
    await tester.ensureVisible(find.text('暂不登录？返回只读连接'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('暂不登录？返回只读连接')).dy,
      greaterThan(tester.getBottomLeft(find.byKey(const Key('password'))).dy),
    );
    expect(
      tester.getBottomLeft(find.text('暂不登录？返回只读连接')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('connect-site'))).dy),
    );
    await click(tester, find.byKey(const Key('connect-site')));
    expect(find.text('已识别 CF Server Monitor'), findsOneWidget);
    expect(find.textContaining('公开站点 ·'), findsNothing);
    expect(find.text('该站点启用了登录验证，当前版本暂不支持登录'), findsNothing);
    final notice = tester.widget<Notice>(find.byType(Notice));
    expect(notice.error, isTrue);
    expect(notice.message, 'App端不支持Turnstile人机验证，请输入 App 访问口令后重试');
    expect(api.loginCalls, 0);
    await click(tester, find.text('暂不登录？返回只读连接'));
    expect(find.byKey(const Key('username')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('app-password')),
      '1234567890abcdef',
    );
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.passwordChecks, isNotEmpty);
    expect(storage.sites, hasLength(1));
    await finish(tester);
  });
  testWidgets('App 口令允许开启登录验证的站点使用管理员账号登录', (tester) async {
    final api = FakeApi()..settings = publicConfig({'turnstile_enabled': true});
    final storage = MemoryStorage();
    await launch(tester, api, storage);
    await click(tester, find.text('添加第一个站点'));
    await tester.enterText(find.byKey(const Key('site-name')), 'Protected');
    await tester.enterText(
      find.byKey(const Key('site-url')),
      'https://a.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('app-password')),
      '1234567890abcdef',
    );
    await click(tester, find.text('需要登录？输入账号密码'));
    await tester.enterText(find.byKey(const Key('password')), 'admin-password');
    await click(tester, find.byKey(const Key('connect-site')));
    expect(api.loginCalls, 1);
    expect(storage.tokens[storage.sites.single.id], isNotNull);
    expect(find.byType(ServerCard), findsOneWidget);
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
    final name = find.byKey(const Key('dashboard-site-name'));
    final status = find.byKey(const Key('connection-dot'));
    expect(find.text('实时连接'), findsNothing);
    expect(
      tester.getRect(status).left - tester.getRect(name).right,
      closeTo(6, 1),
    );
    expect(tester.widget<Text>(name).style!.fontSize, 18);
    expect(
      tester.getRect(find.byKey(const Key('toggle-server-layout'))).right,
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
