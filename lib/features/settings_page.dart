import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/app_update.dart';
import '../core/strings.dart';
import '../widgets/common.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checking = false;

  Future<void> _openLink(Uri url) async {
    try {
      if (await ref.read(externalLinkProvider)(url)) return;
    } catch (_) {
      // Opening external applications can fail even when a handler exists.
    }
    if (mounted) showMessage(context, '无法打开链接，请稍后重试');
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final UpdateResult result;
    try {
      // Retry package metadata as well if the previous attempt failed.
      if (ref.read(packageInfoProvider).hasError) {
        ref.invalidate(packageInfoProvider);
      }
      final installed = await ref.read(packageInfoProvider.future);
      if (!mounted) return;
      final country = View.of(context).platformDispatcher.locale.countryCode;
      result = await ref
          .read(appUpdateProvider)
          .check(installed, countryCode: country ?? 'us');
    } catch (_) {
      if (mounted) showMessage(context, '检查更新失败，请检查网络后重试');
      return;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    switch (result.status) {
      case UpdateStatus.available:
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('发现新版本 {0}', [result.version])),
            content: Text(
              context.tr(
                result.source == UpdateSource.appStore
                    ? '前往 App Store 更新 CF Monitor。'
                    : '前往 GitHub Release 选择适合设备的 APK，下载后安装更新。',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('前往更新')),
              ),
            ],
          ),
        );
        if (open == true && mounted) await _openLink(result.url!);
      case UpdateStatus.upToDate:
        showMessage(context, '当前已是最新版本');
      case UpdateStatus.notPublished:
        showMessage(
          context,
          result.source == UpdateSource.appStore
              ? '当前地区的 App Store 暂未上架，请稍后重试'
              : '暂无可用的 Android 正式版本，请稍后重试',
        );
      case UpdateStatus.unsupported:
        showMessage(context, '仅支持在 Android 或 iOS 上检查更新');
    }
  }

  Future<void> _save(
    BuildContext context,
    Future<void> Function() update,
  ) async {
    try {
      await update();
    } catch (_) {
      if (context.mounted) showMessage(context, '保存设置失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(preferencesProvider);
    final packageInfo = ref.watch(packageInfoProvider);
    final platform = ref.watch(appUpdateProvider).platform;
    final enabled = !preferences.loading && !preferences.saving;
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('设置'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            if (preferences.error != null)
              Notice(
                preferences.error!,
                error: true,
                action: '重试',
                onAction: enabled ? preferences.load : null,
              ),
            Text(
              context.tr('语言'),
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (code, label) in [('zh', '中文'), ('en', 'English')])
                    _SettingOption(
                      key: Key('language-$code'),
                      label: label,
                      selected: preferences.language == code,
                      onTap: enabled
                          ? () => _save(
                              context,
                              () => preferences.update(language: code),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              context.tr('主题'),
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (mode, label, icon) in [
                    (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
                    (ThemeMode.light, '明亮', Icons.light_mode_outlined),
                    (ThemeMode.dark, '暗黑', Icons.dark_mode_outlined),
                  ])
                    _SettingOption(
                      key: Key('theme-${mode.name}'),
                      label: context.tr(label),
                      icon: icon,
                      selected: preferences.themeMode == mode,
                      onTap: enabled
                          ? () => _save(
                              context,
                              () => preferences.update(themeMode: mode),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              context.tr('关于'),
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('CF Monitor'),
                      subtitle: Text(
                        packageInfo.when(
                          data: (info) => context.tr('当前版本 {0}', [
                            '${info.version} (${info.buildNumber})',
                          ]),
                          error: (_, _) => context.tr('无法读取版本信息'),
                          loading: () => context.tr('正在读取版本信息…'),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key('check-update'),
                      leading: const Icon(Icons.system_update_outlined),
                      title: Text(context.tr(_checking ? '正在检查更新…' : '检查更新')),
                      subtitle: switch (platform) {
                        TargetPlatform.android => const Text(
                          'Android · GitHub Releases',
                        ),
                        TargetPlatform.iOS => const Text('iOS · App Store'),
                        _ => null,
                      },
                      trailing: _checking
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _checking ? null : _checkUpdate,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              context.tr('作者的其他项目'),
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: const Key('open-easynode'),
                  leading: const Icon(Icons.terminal_outlined),
                  title: const Text('EasyNode'),
                  subtitle: Text(context.tr('服务器 SSH 终端与管理面板')),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _openLink(AppUpdateService.easyNodeUrl),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingOption extends StatelessWidget {
  const _SettingOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      title: Text(label),
      leading: icon == null ? null : Icon(icon),
      selected: selected,
      trailing: selected ? const Icon(Icons.check, size: 20) : null,
      onTap: onTap,
    ),
  );
}
