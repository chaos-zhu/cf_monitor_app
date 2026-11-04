import 'dart:async';

import 'package:cf_monitor_app/app.dart';
import 'package:cf_monitor_app/core/app_update.dart';
import 'package:cf_monitor_app/features/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_test.dart' show installedVersion;
import 'support.dart';
import 'widget_test.dart' show click, finish;

class FakeUpdateService extends AppUpdateService {
  FakeUpdateService({super.platform = TargetPlatform.android});

  int calls = 0;
  Future<UpdateResult> Function() reply = () async => const UpdateResult(
    status: UpdateStatus.upToDate,
    source: UpdateSource.github,
  );

  @override
  Future<UpdateResult> check(
    PackageInfo installed, {
    String countryCode = 'us',
  }) {
    calls++;
    return reply();
  }
}

Future<void> openSettings(
  WidgetTester tester,
  FakeUpdateService service,
  Future<bool> Function(Uri) open, {
  String language = 'zh',
  Size size = const Size(390, 1000),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    service.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(
          MemoryStorage()..preferences = {'language': language},
        ),
        apiProvider.overrideWithValue(FakeApi()),
        packageInfoProvider.overrideWith(
          (ref) async => installedVersion('1.1.0'),
        ),
        appUpdateProvider.overrideWithValue(service),
        externalLinkProvider.overrideWithValue(open),
      ],
      child: const MonitorApp(),
    ),
  );
  await tester.pumpAndSettle();
  await click(tester, find.byKey(const Key('open-settings')));
}

Future<void> scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Android 显示实际版本，新版确认后打开 Release，EasyNode 入口可用', (tester) async {
    final links = <Uri>[];
    final service = FakeUpdateService()
      ..reply = () async => UpdateResult(
        status: UpdateStatus.available,
        source: UpdateSource.github,
        version: '1.2.0',
        url: Uri.parse(
          'https://github.com/chaos-zhu/cf_monitor_app/releases/tag/v1.2.0',
        ),
      );
    await openSettings(tester, service, (url) async {
      links.add(url);
      return true;
    });
    expect(find.text('当前版本 1.1.0 (50)'), findsOneWidget);
    expect(find.text('Android · GitHub Releases'), findsOneWidget);
    await scrollTo(tester, 'check-update');
    await click(tester, find.byKey(const Key('check-update')));
    expect(find.text('发现新版本 1.2.0'), findsOneWidget);
    await click(tester, find.text('取消'));
    expect(links, isEmpty);
    await click(tester, find.byKey(const Key('check-update')));
    await click(tester, find.text('前往更新'));
    expect(links.single.path, endsWith('/releases/tag/v1.2.0'));
    await scrollTo(tester, 'open-easynode');
    await click(tester, find.byKey(const Key('open-easynode')));
    expect(links.last, AppUpdateService.easyNodeUrl);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('iOS 英文提示未上架，更新打开 App Store，窄屏大字体不溢出', (tester) async {
    final links = <Uri>[];
    final service = FakeUpdateService(platform: TargetPlatform.iOS)
      ..reply = () async => const UpdateResult(
        status: UpdateStatus.notPublished,
        source: UpdateSource.appStore,
      );
    await openSettings(
      tester,
      service,
      (url) async {
        links.add(url);
        return true;
      },
      language: 'en',
      size: const Size(320, 900),
      scale: 1.5,
    );
    await scrollTo(tester, 'check-update');
    expect(find.text('iOS · App Store'), findsOneWidget);
    await click(tester, find.byKey(const Key('check-update')));
    expect(
      find.text(
        'Not available in your App Store region yet. Please try again later.',
      ),
      findsOneWidget,
    );
    expect(find.text('You are up to date'), findsNothing);
    service.reply = () async => UpdateResult(
      status: UpdateStatus.available,
      source: UpdateSource.appStore,
      version: '1.2.0',
      url: Uri.parse('https://apps.apple.com/app/id123456789'),
    );
    await click(tester, find.byKey(const Key('check-update')));
    expect(find.text('Update CF Monitor in the App Store.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await click(tester, find.text('Get update'));
    expect(links.single.host, 'apps.apple.com');
    await scrollTo(tester, 'open-easynode');
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('检查中禁用按钮，失败可重试，外链失败有提示', (tester) async {
    final pending = Completer<UpdateResult>();
    final service = FakeUpdateService()..reply = () => pending.future;
    await openSettings(tester, service, (_) async => false);
    await scrollTo(tester, 'check-update');
    await tester.tap(find.byKey(const Key('check-update')));
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.byKey(const Key('check-update'))).onTap,
      isNull,
    );
    await tester.tap(find.byKey(const Key('check-update')));
    expect(service.calls, 1);
    pending.completeError(const UpdateCheckException());
    await tester.pumpAndSettle();
    expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    service.reply = () async => const UpdateResult(
      status: UpdateStatus.upToDate,
      source: UpdateSource.github,
    );
    await click(tester, find.byKey(const Key('check-update')));
    expect(find.text('当前已是最新版本'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await scrollTo(tester, 'open-easynode');
    await click(tester, find.byKey(const Key('open-easynode')));
    expect(find.text('无法打开链接，请稍后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('离开设置页后检查完成不再显示弹窗或访问已销毁的页面', (tester) async {
    final pending = Completer<UpdateResult>();
    final service = FakeUpdateService()..reply = () => pending.future;
    await openSettings(tester, service, (_) async => true);
    await scrollTo(tester, 'check-update');
    await tester.tap(find.byKey(const Key('check-update')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    pending.complete(
      UpdateResult(
        status: UpdateStatus.available,
        source: UpdateSource.github,
        version: '1.2.0',
        url: Uri.https(
          'github.com',
          '/chaos-zhu/cf_monitor_app/releases/latest',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
