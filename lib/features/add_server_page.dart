import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/api.dart';
import '../core/session.dart';
import 'installation_page.dart';
import '../widgets/common.dart';

class AddServerPage extends ConsumerStatefulWidget {
  const AddServerPage({
    required this.session,
    required this.onLogin,
    required this.onCreated,
    super.key,
  });
  final MonitorSession session;
  final Future<bool> Function() onLogin;
  final VoidCallback onCreated;

  @override
  ConsumerState<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends ConsumerState<AddServerPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _group = TextEditingController();
  bool _busy = false, _needsLogin = false;
  String? _error;
  String? _createdId;

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _createdId != null || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_needsLogin || widget.session.token == null) {
        if (!await widget.onLogin() || !mounted) return;
        _needsLogin = false;
      }
      final token = widget.session.token;
      if (token == null) return;
      final id = await ref
          .read(apiProvider)
          .addServer(
            widget.session.site,
            token: token,
            name: _name.text,
            group: _group.text,
          );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _createdId = id);
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = MonitorSession.friendlyError(e);
          if (e is ApiFailure && e.kind == FailureKind.authentication) {
            _needsLogin = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.session.servers.map((s) => s.group).toSet().toList();
    return PopScope(
      canPop: !_busy || _createdId != null,
      child: Scaffold(
        appBar: AppBar(title: Text(_createdId == null ? '新增服务器' : '安装探针')),
        body: PageBody(
          child: _createdId != null
              ? InstallCommandView(
                  session: widget.session,
                  serverId: _createdId!,
                  serverName: _name.text.trim(),
                  onLogin: widget.onLogin,
                )
              : Form(
                  key: _form,
                  child: ListView(
                    key: const PageStorageKey('server-creation'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    children: [
                      const Text('服务器名称'),
                      const SizedBox(height: 9),
                      TextFormField(
                        key: const Key('server-name'),
                        controller: _name,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: '例如：香港服务器'),
                        validator: (value) {
                          final name = (value ?? '').trim();
                          if (name.isEmpty) return '请输入服务器名称';
                          if (name.length > 100) return '服务器名称最多 100 个字符';
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),
                      const Text('分组'),
                      const SizedBox(height: 9),
                      TextFormField(
                        key: const Key('server-group'),
                        controller: _group,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          hintText: 'Default（可选）',
                        ),
                      ),
                      if (groups.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final group in groups)
                              ActionChip(
                                label: Text(group),
                                onPressed: _busy
                                    ? null
                                    : () => _group.text = group,
                              ),
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 18),
                        Notice(_error!, error: true),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('submit-server'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_needsLogin ? '重新登录并创建' : '创建服务器'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
