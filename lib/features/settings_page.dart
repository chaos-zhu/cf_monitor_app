import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/strings.dart';
import '../widgets/common.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
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
