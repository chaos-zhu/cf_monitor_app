import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/features/settings_page.dart';
import 'package:cf_monitor_app/widgets/common.dart';
import 'package:cf_monitor_app/widgets/server_list_tile.dart';
import 'support.dart';
import 'widget_test.dart' show launch, click, finish;

Brightness settingsBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsPage))).brightness;

void main() {
  testWidgets('设置入口切换中英文，返回站点页立即生效，重启保留语言与主题', (tester) async {
    final storage = MemoryStorage([siteA]);
    await launch(tester, FakeApi(), storage);
    await click(tester, find.byKey(const Key('open-settings')));
    expect(find.text('设置'), findsOneWidget);
    await click(tester, find.byKey(const Key('language-en')));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    await click(tester, find.byKey(const Key('theme-dark')));
    expect(settingsBrightness(tester), Brightness.dark);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('My sites'), findsOneWidget);
    expect(find.text(siteA.name), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    await finish(tester);
    await launch(tester, FakeApi(), storage);
    expect(find.text('My sites'), findsOneWidget);
    await click(tester, find.byKey(const Key('open-settings')));
    expect(settingsBrightness(tester), Brightness.dark);
    await click(tester, find.byKey(const Key('language-zh')));
    expect(find.text('设置'), findsOneWidget);
    expect(storage.preferences, {'language': 'zh', 'theme': 'dark'});
    await finish(tester);
  });

  testWidgets('跟随系统响应亮度变化，明亮和暗黑选择覆盖系统，窄屏大字体不溢出', (tester) async {
    final storage = MemoryStorage();
    await launch(
      tester,
      FakeApi(),
      storage,
      size: const Size(320, 900),
      scale: 1.5,
    );
    await click(tester, find.byKey(const Key('open-settings')));
    expect(settingsBrightness(tester), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(settingsBrightness(tester), Brightness.dark);
    await click(tester, find.byKey(const Key('theme-light')));
    expect(settingsBrightness(tester), Brightness.light);
    await click(tester, find.byKey(const Key('theme-dark')));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(settingsBrightness(tester), Brightness.dark);
    await click(tester, find.byKey(const Key('theme-system')));
    expect(settingsBrightness(tester), Brightness.light);
    await tester.scrollUntilVisible(
      find.byKey(const Key('language-en')),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await click(tester, find.byKey(const Key('language-en')));
    expect(tester.takeException(), isNull);
    expect(storage.preferences['theme'], 'system');
    await finish(tester);
  });

  testWidgets('英文覆盖列表、详情、安装和连接表单，保留站点及自定义线路名称', (tester) async {
    final storage = MemoryStorage([siteA])
      ..tokens['a'] = jwt()
      ..preferences = {'language': 'en', 'theme': 'dark'};
    final api = FakeApi()..settings = publicConfig({'custom_ct_name': '我的线路'});
    await launch(tester, api, storage, size: const Size(320, 900), scale: 1.5);
    await click(tester, find.text('Open site'));
    expect(find.text('Live speed'), findsOneWidget);
    expect(find.text('All 1'), findsOneWidget);
    await click(tester, find.byKey(const Key('toggle-server-layout')));
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('我的线路'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.longPress(find.byType(ServerListTile));
    await tester.pumpAndSettle();
    await click(tester, find.text('Install command'));
    expect(find.text('Install agent - TX-香港'), findsOneWidget);
    expect(find.text('Target system'), findsOneWidget);
    expect(find.text('GitHub proxy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await click(tester, find.byType(ServerListTile));
    expect(find.text('Resources'), findsOneWidget);
    await click(tester, find.text('System'));
    expect(find.text('CPU model'), findsOneWidget);
    expect(find.textContaining(' / month'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add site'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await click(tester, find.text('Add site'));
    expect(find.text('Connect a new site'), findsOneWidget);
    await click(tester, find.text('Check and connect'));
    expect(find.text('Enter a site name'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('英文连接错误及重试按钮采用当前语言', (tester) async {
    final storage = MemoryStorage([siteA])..preferences = {'language': 'en'};
    final api = FakeApi()
      ..dashboardHandler = () async => throw const ApiFailure(
        '无法连接站点，请检查地址、证书与网络',
        kind: FailureKind.network,
      );
    await launch(tester, api, storage);
    await click(tester, find.text('Open site'));
    expect(
      find.text('Cannot connect. Check the site URL, certificate and network.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(Notice), findsOneWidget);
    await finish(tester);
  });
}
