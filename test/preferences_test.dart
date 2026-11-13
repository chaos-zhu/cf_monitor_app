import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cf_monitor_app/core/preferences.dart';
import 'package:cf_monitor_app/core/storage.dart';
import 'package:cf_monitor_app/core/strings.dart';
import 'support.dart';

class FailingPreferencesStorage extends MemoryStorage {
  bool failRead = false;
  Completer<void>? writeGate;
  @override
  Future<Map<String, String>> readPreferences() async {
    if (failRead) throw StateError('read failed');
    return super.readPreferences();
  }

  @override
  Future<void> writePreferences(Map<String, String> next) async {
    await writeGate?.future;
    throw StateError('write failed');
  }
}

void main() {
  test('语言默认中文、主题跟随系统，两个偏好独立保存且设备重建后保留', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesController(DeviceSiteStorage());
    addTearDown(preferences.dispose);
    await preferences.load();
    expect(preferences.language, 'zh');
    expect(preferences.themeMode, ThemeMode.system);
    await preferences.update(language: 'en');
    await preferences.update(themeMode: ThemeMode.dark);
    final restored = PreferencesController(DeviceSiteStorage());
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.language, 'en');
    expect(restored.themeMode, ThemeMode.dark);
    await restored.update(language: 'zh', themeMode: ThemeMode.light);
    expect(await DeviceSiteStorage().readPreferences(), {
      'language': 'zh',
      'theme': 'light',
    });
    await restored.update(themeMode: ThemeMode.system);
    expect((await DeviceSiteStorage().readPreferences())['theme'], 'system');
  });

  test('未知偏好回退默认值，读取失败仍可启动并重试', () async {
    final storage = FailingPreferencesStorage()
      ..preferences = {'language': 'fr', 'theme': 'unknown'};
    final preferences = PreferencesController(storage);
    addTearDown(preferences.dispose);
    await preferences.load();
    expect(preferences.language, 'zh');
    expect(preferences.themeMode, ThemeMode.system);
    storage.failRead = true;
    await preferences.load();
    expect(preferences.initialized, isTrue);
    expect(preferences.loading, isFalse);
    expect(preferences.error, isNotNull);
    storage.failRead = false;
    storage.preferences = {'language': 'en', 'theme': 'dark'};
    await preferences.load();
    expect(preferences.error, isNull);
    expect(preferences.language, 'en');
  });

  test('保存期间阻止重复写入，失败保留原偏好并解除忙碌状态', () async {
    final storage = FailingPreferencesStorage()..writeGate = Completer<void>();
    final preferences = PreferencesController(storage);
    addTearDown(preferences.dispose);
    await preferences.load();
    final first = preferences.update(language: 'en');
    final failure = expectLater(first, throwsStateError);
    expect(preferences.saving, isTrue);
    await preferences.update(themeMode: ThemeMode.dark);
    storage.writeGate!.complete();
    await failure;
    expect(preferences.saving, isFalse);
    expect(preferences.language, 'zh');
    expect(preferences.themeMode, ThemeMode.system);
    expect(storage.preferences, isEmpty);
  });

  test('本地化保留插值原文，翻译动态错误、运行时长和中文计费周期', () {
    const en = AppStrings('en');
    const zh = AppStrings('zh');
    expect(en.text('安装探针 - {0}', ['中文服务器 {1}']), 'Install agent - 中文服务器 {1}');
    expect(zh.text('{0} 在线 / {1} 离线', [1, 2]), '1 在线 / 2 离线');
    expect(
      en.text('站点请求失败（429），请稍后重试'),
      'Site request failed (429). Please try again later.',
    );
    expect(en.text('12 天 3 小时'), '12d 3h');
    expect(en.text('2 天后到期'), 'Expires in 2 days');
    expect(
      en.text('只读访问可绕过全局验证，以只读方式访问'),
      'Read-only access bypasses global verification.',
    );
    expect(
      en.text('暂不登录？返回只读连接'),
      'Not signing in? Return to read-only access',
    );
    expect(en.text('未知的服务器返回信息'), '未知的服务器返回信息');
  });
}
