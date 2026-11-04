// Marketing capture harness. Run explicitly; never connects to a real site.
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cf_monitor_app/app.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/features/sites_page.dart';
import 'package:cf_monitor_app/widgets/common.dart';
import 'package:cf_monitor_app/widgets/server_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/support.dart';

const _captureKey = Key('marketing-capture');

// The test engine disables system font discovery. Supply explicit font
// fallbacks while using the production themes, pages, and navigation.
class _CaptureApp extends ConsumerWidget {
  const _CaptureApp();

  ThemeData _theme(Brightness brightness) {
    final theme = appTheme(brightness);
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Apple Color Emoji', 'Arial Unicode'],
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'Roboto',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: preferences.themeMode,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: preferences.initialized ? const SitesPage() : const SizedBox(),
    );
  }
}

class _DemoApi extends FakeApi {
  _DemoApi() {
    settings = publicConfig({
      'site_title': 'Cloud fleet',
      'show_three_net_details': true,
      'custom_ct_name': 'Hong Kong',
      'custom_cu_name': 'Singapore',
      'custom_cm_name': 'Tokyo',
    });
    dashboardHandler = () async =>
        DashboardSnapshot(servers: servers, config: settings.data, reports: []);
  }

  final now = DateTime.now();
  late final servers = [
    _server('hk', 'HK Edge 01', 'HK', 24.8, 3810, 1280, 17),
    _server('sg', 'SG Compute 02', 'SG', 12.4, 6420, 820, 32),
    _server('jp', 'Tokyo Relay 03', 'JP', 41.6, 2180, 460, 48),
    _server('us', 'US West 04', 'US', 8.2, 960, 210, 138),
  ];

  Server _server(
    String id,
    String name,
    String region,
    double cpu,
    double download,
    double upload,
    double latency,
  ) => exampleServer(id: id, cpu: cpu, time: now).merge({
    'name': name,
    'region': region,
    'server_group': 'PRODUCTION',
    'cpu_cores': 4,
    'ram_total': 8192,
    'ram_used': 3248,
    'disk_total': 81920,
    'disk_used': 23552,
    'net_in_speed': download,
    'net_out_speed': upload,
    'net_rx_monthly': 184 * 1073741824,
    'net_tx_monthly': 92 * 1073741824,
    'traffic_limit': 1024,
    'ip_v6': '1',
    'load_avg': '0.24 0.18 0.12',
    'boot_time': now
        .subtract(const Duration(days: 42, hours: 6))
        .millisecondsSinceEpoch,
    'expire_date': now.add(const Duration(days: 120)).toIso8601String(),
    'price': 'USD 6/month',
    'ping_ct': latency,
    'ping_cu': latency + 21,
    'ping_cm': latency + 8,
    'loss_cu': 0,
    'ping': [
      {
        'ts': now.millisecondsSinceEpoch,
        'ct': latency,
        'cu': latency + 21,
        'cm': latency + 8,
      },
    ],
    'loss': [
      {'ts': now.millisecondsSinceEpoch, 'ct': 0, 'cu': 0, 'cm': 0},
    ],
  });

  @override
  Future<Server> detail(MonitorSite site, String id, {String? token}) async =>
      servers.firstWhere((server) => server.id == id);

  @override
  Future<List<MetricSample>> history(
    MonitorSite site,
    String id,
    HistoryRange range, {
    String? token,
  }) async => List.generate(61, (i) {
    final time = now.subtract(Duration(seconds: (60 - i) * 10));
    final wave = math.sin(i * .29);
    return MetricSample(time, {
      'cpu': 24 + wave * 8 + math.sin(i * .87) * 3,
      'ram_used': 3248 + math.sin(i * .12) * 320,
      'ram_total': 8192,
      'disk_used': 23552,
      'disk_total': 81920,
      'net_in_speed': 2800 + wave * 950,
      'net_out_speed': 900 + math.sin(i * .22) * 300,
      'ping_ct': 17 + math.sin(i * .3) * 3,
      'ping_cu': 38 + math.sin(i * .27) * 5,
      'ping_cm': 25 + math.sin(i * .25) * 4,
      'loss_ct': 0,
      'loss_cu': 0,
      'loss_cm': 0,
    });
  });
}

Future<void> _loadFonts() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final flutter = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => entry['name'] == 'flutter');
  final directory = Directory.fromUri(
    configFile.uri.resolve(flutter['rootUri'] as String),
  ).uri.resolve('../../bin/cache/artifacts/material_fonts/');
  final font = FontLoader('Roboto');
  for (final file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    font.addFont(
      Future.value(
        ByteData.sublistView(
          File.fromUri(directory.resolve(file)).readAsBytesSync(),
        ),
      ),
    );
  }
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File.fromUri(
            directory.resolve('MaterialIcons-Regular.otf'),
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
  final symbolFont =
      Platform.environment['SCREENSHOT_SYMBOL_FONT'] ??
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  final emojiFont =
      Platform.environment['SCREENSHOT_EMOJI_FONT'] ??
      '/System/Library/Fonts/Apple Color Emoji.ttc';
  for (final entry in {
    'Arial Unicode': symbolFont,
    'sans-serif': symbolFont,
    'Apple Color Emoji': emojiFont,
    'PingFang SC': emojiFont,
  }.entries) {
    final file = File(entry.value);
    if (file.existsSync()) {
      final fallback = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await fallback.load();
    }
  }
  final monoFile = Platform.environment['SCREENSHOT_MONO_FONT'];
  final mono = FontLoader('monospace')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          monoFile == null
              ? File.fromUri(
                  directory.resolve('Roboto-Regular.ttf'),
                ).readAsBytesSync()
              : File(monoFile).readAsBytesSync(),
        ),
      ),
    );
  await mono.load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('docs/images/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(_loadFonts);
  testWidgets('capture actual mobile pages with isolated demo data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });
    final api = _DemoApi();
    final storage =
        MemoryStorage([
            MonitorSite(
              id: 'cloud',
              name: 'Cloud fleet',
              baseUrl: 'https://cloud.example.com',
              status: SiteStatus.connected,
              lastVisit: api.now,
              serverCount: 4,
              onlineCount: 4,
            ),
            MonitorSite(
              id: 'lab',
              name: 'Home lab',
              baseUrl: 'https://lab.example.com',
              status: SiteStatus.connected,
              lastVisit: api.now,
              serverCount: 3,
              onlineCount: 3,
            ),
            const MonitorSite(
              id: 'private',
              name: 'Private cluster',
              baseUrl: 'https://private.example.com',
              status: SiteStatus.loginRequired,
            ),
          ])
          ..compactLayout = true
          ..preferences = {'language': 'en', 'theme': 'light'};
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(api),
        storageProvider.overrideWithValue(storage),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RepaintBoundary(key: _captureKey, child: _CaptureApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/logo.png'),
        tester.element(find.byType(SitesPage)),
      ),
    );
    await _capture(tester, '01-sites');
    await tester.tap(find.text('Open site').first);
    await _capture(tester, '02-dashboard');
    await tester.runAsync(
      () =>
          container.read(preferencesProvider).update(themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ServerListTile).first);
    await _capture(tester, '03-resources');
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network speed'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Packet loss'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Packet loss')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packet loss'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Network'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(
        find
            .ancestor(of: find.text('Network'), matching: find.byType(Row))
            .first,
      ),
      alignment: .01,
    );
    await _capture(tester, '04-network');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    container.dispose();
  });
}
