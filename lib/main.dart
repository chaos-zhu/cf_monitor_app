import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'CF-Server-Monitor',
    ], await rootBundle.loadString('assets/licenses/CF-Server-Monitor.txt'));
  });
  runApp(const ProviderScope(child: MonitorApp()));
}
