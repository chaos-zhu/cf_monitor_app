import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api.dart';
import 'core/storage.dart';
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

class MonitorApp extends StatelessWidget {
  const MonitorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CF Monitor',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const SitesPage(),
  );
}
