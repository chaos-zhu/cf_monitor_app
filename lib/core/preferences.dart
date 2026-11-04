import 'package:flutter/material.dart';
import 'storage.dart';

class PreferencesController extends ChangeNotifier {
  PreferencesController(this.storage);
  final SiteStorage storage;
  String language = 'zh';
  ThemeMode themeMode = ThemeMode.system;
  bool loading = true;
  bool initialized = false;
  bool saving = false;
  String? error;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      final saved = await storage.readPreferences();
      language = saved['language'] == 'en' ? 'en' : 'zh';
      themeMode =
          ThemeMode.values
              .where((mode) => mode.name == saved['theme'])
              .firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      error = '无法读取设置，请重试';
    } finally {
      loading = false;
      initialized = true;
      _notify();
    }
  }

  Future<void> update({String? language, ThemeMode? themeMode}) async {
    if (loading || saving) return;
    final nextLanguage = language ?? this.language;
    if (!['zh', 'en'].contains(nextLanguage)) {
      throw ArgumentError.value(language);
    }
    final nextTheme = themeMode ?? this.themeMode;
    saving = true;
    _notify();
    try {
      await storage.writePreferences({
        'language': nextLanguage,
        'theme': nextTheme.name,
      });
      this.language = nextLanguage;
      this.themeMode = nextTheme;
      error = null;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
