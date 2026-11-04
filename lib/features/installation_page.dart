import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/api.dart';
import '../core/installation.dart';
import '../core/session.dart';
import '../widgets/common.dart';

class InstallationPage extends StatelessWidget {
  const InstallationPage({
    required this.session,
    required this.serverId,
    required this.serverName,
    required this.onLogin,
    super.key,
  });
  final MonitorSession session;
  final String serverId, serverName;
  final Future<bool> Function() onLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '安装探针 - $serverName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: PageBody(
      child: InstallCommandView(
        session: session,
        serverId: serverId,
        onLogin: onLogin,
      ),
    ),
  );
}

class InstallCommandView extends ConsumerStatefulWidget {
  const InstallCommandView({
    required this.session,
    required this.serverId,
    required this.onLogin,
    super.key,
  });
  final MonitorSession session;
  final String serverId;
  final Future<bool> Function() onLogin;

  @override
  ConsumerState<InstallCommandView> createState() => _InstallCommandViewState();
}

class _InstallCommandViewState extends ConsumerState<InstallCommandView> {
  bool _busy = false, _needsLogin = false;
  String? _error;
  InstallParameters? _installation;
  InstallTarget _target = InstallTarget.linux;
  final _proxy = TextEditingController();
  static const _proxies = [
    '',
    'https://ghfast.top/',
    'https://ghproxy.net/',
    'https://gh.llkk.cc/',
    'https://gh-proxy.com/',
  ];

  @override
  void dispose() {
    _proxy.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_retryCommand());
  }

  Future<void> _fetchCommand() async {
    final token = widget.session.token;
    if (token == null) {
      throw const ApiFailure('请重新登录以获取安装命令', kind: FailureKind.authentication);
    }
    final parameters = await ref
        .read(apiProvider)
        .installParameters(widget.session.site, token: token);
    if (mounted) setState(() => _installation = parameters);
  }

  Future<void> _retryCommand() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_needsLogin || widget.session.token == null) {
        if (!await widget.onLogin() || !mounted) return;
        _needsLogin = false;
      }
      await _fetchCommand();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = MonitorSession.friendlyError(e);
          _needsLogin = e is ApiFailure && e.kind == FailureKind.authentication;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? proxyError;
    try {
      if (_target != InstallTarget.docker) normalizeGitHubProxy(_proxy.text);
    } on FormatException catch (e) {
      proxyError = e.message;
    }
    final command = proxyError != null
        ? null
        : _installation?.command(
            widget.session.site,
            widget.serverId,
            _target,
            githubProxy: _proxy.text,
          );
    return ListView(
      key: const PageStorageKey('server-installation'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        const Text('目标系统'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final target in InstallTarget.values)
              ChoiceChip(
                label: Text(target.label),
                selected: target == _target,
                onSelected: (_) => setState(() => _target = target),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Text('GitHub 代理'),
        const SizedBox(height: 10),
        TextField(
          key: const Key('github-proxy'),
          controller: _proxy,
          enabled: _target != InstallTarget.docker,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '直连，或输入代理地址',
            errorText: proxyError,
            helperText: _target == InstallTarget.docker
                ? 'Docker 镜像不使用 GitHub 代理'
                : null,
            suffixIcon: PopupMenuButton<String>(
              key: const Key('github-proxy-presets'),
              tooltip: '选择 GitHub 代理',
              enabled: _target != InstallTarget.docker,
              icon: const Icon(Icons.keyboard_arrow_down),
              onSelected: (value) => setState(() => _proxy.text = value),
              itemBuilder: (_) => [
                for (final proxy in _proxies)
                  PopupMenuItem(
                    value: proxy,
                    child: Text(proxy.isEmpty ? '直连（不使用代理）' : proxy),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text('安装命令', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (_busy) const LinearProgressIndicator(),
        if (command != null) ...[
          AppPanel(
            child: SelectableText(
              command,
              key: const Key('install-command'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('copy-install-command'),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('复制安装命令'),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: command));
                if (context.mounted) showMessage(context, '安装命令已复制');
              } catch (_) {
                if (context.mounted) showMessage(context, '复制失败，可长按命令复制');
              }
            },
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Notice(_error!, error: true),
        ],
        if (_installation == null && !_busy) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _retryCommand,
            child: Text(_needsLogin ? '重新登录并获取安装命令' : '重新获取安装命令'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('finish-server'),
          onPressed: () => Navigator.pop(context),
          child: const Text('返回服务器列表'),
        ),
      ],
    );
  }
}
