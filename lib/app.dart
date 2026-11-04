import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/api.dart';
import 'core/app_update.dart';
import 'core/storage.dart';
import 'core/preferences.dart';
import 'features/sites_page.dart';
import 'widgets/common.dart';

final apiProvider = Provider<MonitorApi>((ref) {
  final api = WorkerApi();
  ref.onDispose(api.dispose);
  return api;
});
final storageProvider = Provider<SiteStorage>((ref) => DeviceSiteStorage());
final sitesProvider = ChangeNotifierProvider<SiteController>(
  (ref) => SiteController(ref.watch(storageProvider))..load(),
);
final preferencesProvider = ChangeNotifierProvider<PreferencesController>(
  (ref) => PreferencesController(ref.watch(storageProvider))..load(),
);
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
final appUpdateProvider = Provider<AppUpdateService>((ref) {
  final service = AppUpdateService();
  ref.onDispose(service.dispose);
  return service;
});
final externalLinkProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

class MonitorApp extends ConsumerWidget {
  const MonitorApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    return MaterialApp(
      title: 'CF Monitor',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: preferences.themeMode,
      locale: preferences.language == 'en'
          ? const Locale('en')
          : const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: !preferences.initialized
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : const SitesPage(),
    );
  }
}
