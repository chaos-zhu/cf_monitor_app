import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings.dart';
import '../app.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../widgets/common.dart';

class ConnectionResult {
  const ConnectionResult(this.site, this.config, this.token);
  final MonitorSite site;
  final SiteConfig? config;
  final String? token;
}

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({
    this.site,
    this.config,
    this.requireLogin = false,
    super.key,
  });
  final MonitorSite? site;
  final SiteConfig? config;
  final bool requireLogin;
  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _url;
  final _username = TextEditingController(text: 'admin'),
      _password = TextEditingController(),
      _appPassword = TextEditingController(),
      _userAgent = TextEditingController();
  late final String _id;
  late final Future<void> _credentialsLoaded;
  SiteConfig? _config;
  bool _login = false, _busy = false, _hidden = true;
  bool _appPasswordHidden = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site?.name ?? '');
    _url = TextEditingController(text: widget.site?.baseUrl ?? '');
    _id =
        widget.site?.id ??
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    _config = widget.config;
    _login = widget.requireLogin;
    _credentialsLoaded = widget.site == null
        ? Future.value()
        : _loadCredentials();
    _url.addListener(() {
      if (widget.site != null && _url.text != widget.site!.baseUrl) {
        _appPassword.clear();
        _userAgent.clear();
      }
      if (_config != null) {
        setState(() {
          _config = null;
          _error = null;
        });
      }
    });
  }

  Future<void> _loadCredentials() async {
    final storage = ref.read(storageProvider);
    final values = await Future.wait([
      storage.readAppPassword(_id),
      storage.readUserAgent(_id),
    ]);
    if (!mounted || _url.text != widget.site!.baseUrl) return;
    if (_appPassword.text.isEmpty) _appPassword.text = values[0] ?? '';
    if (_userAgent.text.isEmpty) _userAgent.text = values[1] ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _appPassword.dispose();
    _userAgent.dispose();
    super.dispose();
  }

  MonitorSite _candidate() => MonitorSite(
    id: _id,
    name: _name.text.trim(),
    baseUrl: normalizeBaseUrl(_url.text),
  );
  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _credentialsLoaded;
      final password = _appPassword.text;
      final userAgent = _userAgent.text;
      final site = _candidate().copyWith(
        appPassword: password.isEmpty ? null : password,
        userAgent: userAgent.isEmpty ? null : userAgent,
      );
      final controller = ref.read(sitesProvider);
      final api = ref.read(apiProvider);
      final token = widget.site?.baseUrl == site.baseUrl
          ? await controller.token(site.id)
          : null;
      final cfg = await api.config(site, token: token);
      if (!mounted) return;
      setState(() => _config = cfg);
      WorkerApi.ensureSupported(cfg, hasAppPassword: site.appPassword != null);
      if (site.appPassword != null && !widget.requireLogin) {
        await api.validateAppPassword(site);
      }
      if (_login ||
          (site.appPassword == null && !cfg.isPublic && !cfg.authorized)) {
        if (!_login) {
          setState(() => _login = true);
          return;
        }
        WorkerApi.ensureSupported(cfg, login: true);
        if (_username.text.trim().isEmpty || _password.text.isEmpty) {
          setState(() => _error = context.tr('请输入用户名和密码'));
          return;
        }
        final nextToken = await api.login(
          site,
          _username.text.trim(),
          _password.text,
        );
        final authorized = await api.config(site, token: nextToken);
        WorkerApi.ensureSupported(
          authorized,
          hasAppPassword: site.appPassword != null,
        );
        if (!authorized.authorized) {
          throw const ApiFailure(
            '登录凭证未通过站点校验，请重试',
            kind: FailureKind.authentication,
          );
        }
        await controller.save(
          site,
          token: nextToken,
          replaceToken: true,
          appPassword: site.appPassword,
          replaceAppPassword: !widget.requireLogin,
          userAgent: site.userAgent,
          replaceUserAgent: !widget.requireLogin,
        );
        _password.clear();
        if (mounted) {
          Navigator.pop(context, ConnectionResult(site, authorized, nextToken));
        }
      } else {
        await controller.save(
          site,
          appPassword: site.appPassword,
          replaceAppPassword: true,
          userAgent: site.userAgent,
          replaceUserAgent: true,
        );
        if (mounted) {
          Navigator.pop(
            context,
            ConnectionResult(site, cfg, cfg.authorized ? token : null),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : e is ApiFailure
              ? e.message
              : context.tr('连接或保存失败，请重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cfg = _config;
    final showTurnstileNotice =
        (cfg?.globalChallenge == true && _appPassword.text.isEmpty) ||
        (_login && cfg?.loginChallenge == true);
    final isTurnstileError =
        _error == '该站点启用了全局人机验证，当前版本暂不支持连接' ||
        _error == '该站点启用了登录验证，当前版本暂不支持登录';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.requireLogin ? context.tr('重新连接站点') : context.tr('连接新站点'),
        ),
      ),
      body: PageBody(
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context.tr('站点名称')),
                TextFormField(
                  key: const Key('site-name'),
                  controller: _name,
                  enabled: !_busy && !widget.requireLogin,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(hintText: context.tr('例如：主监控站')),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? context.tr('请输入站点名称') : null,
                ),
                const SizedBox(height: 22),
                _label(context.tr('站点地址')),
                TextFormField(
                  key: const Key('site-url'),
                  controller: _url,
                  enabled: !_busy && !widget.requireLogin,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'https://monitor.example.com',
                  ),
                  validator: (v) {
                    try {
                      normalizeBaseUrl(v ?? '');
                      return null;
                    } on FormatException catch (e) {
                      return context.tr(e.message);
                    }
                  },
                ),
                if (cfg != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: p.green,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr('已识别 CF Server Monitor'),
                          style: TextStyle(fontSize: 12, color: p.green),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!widget.requireLogin) ...[
                  const SizedBox(height: 22),
                  _label(context.tr('App 访问口令（可选）')),
                  TextFormField(
                    key: const Key('app-password'),
                    controller: _appPassword,
                    onChanged: (_) => setState(() {}),
                    enabled: !_busy,
                    obscureText: _appPasswordHidden,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: context.tr('输入站点的 App 访问口令'),
                      suffixIcon: IconButton(
                        tooltip: context.tr(
                          _appPasswordHidden ? '显示密码' : '隐藏密码',
                        ),
                        onPressed: () => setState(
                          () => _appPasswordHidden = !_appPasswordHidden,
                        ),
                        icon: Icon(
                          _appPasswordHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value != null &&
                            value.isNotEmpty &&
                            !RegExp(r'^[\x21-\x7e]{16,32}$').hasMatch(value)
                        ? context.tr('App 访问口令须为 16-32 位可见 ASCII 字符')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('只读访问可绕过全局验证，以只读方式访问'),
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                  const SizedBox(height: 22),
                  _label(context.tr('自定义 User-Agent（可选）')),
                  TextFormField(
                    key: const Key('user-agent'),
                    controller: _userAgent,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: context.tr('输入站点安全规则允许的 User-Agent'),
                    ),
                    validator: (value) =>
                        value != null &&
                            value.isNotEmpty &&
                            !RegExp(r'^[\x20-\x7e]+$').hasMatch(value)
                        ? context.tr('User-Agent 只能包含可打印 ASCII 字符')
                        : null,
                  ),
                ],
                if (_login) ...[
                  const SizedBox(height: 25),
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline, size: 17, color: p.green),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                context.tr('登录此站点'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _label(context.tr('用户名')),
                        TextFormField(
                          key: const Key('username'),
                          controller: _username,
                          enabled: !_busy,
                          autocorrect: false,
                          decoration: InputDecoration(
                            hintText: context.tr('输入用户名'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _label(context.tr('密码')),
                        TextFormField(
                          key: const Key('password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hidden,
                          autocorrect: false,
                          enableSuggestions: false,
                          onFieldSubmitted: (_) {
                            if (!_busy) _connect();
                          },
                          decoration: InputDecoration(
                            hintText: context.tr('输入站点密码'),
                            suffixIcon: IconButton(
                              tooltip: _hidden
                                  ? context.tr('显示密码')
                                  : context.tr('隐藏密码'),
                              onPressed: () =>
                                  setState(() => _hidden = !_hidden),
                              icon: Icon(
                                _hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _login = true),
                      child: Text(context.tr('需要登录？输入账号密码')),
                    ),
                  ),
                ],
                if (_error != null &&
                    !(showTurnstileNotice && isTurnstileError)) ...[
                  const SizedBox(height: 18),
                  Notice(_error!, error: true),
                ],
                if (showTurnstileNotice)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Notice(
                      context.tr('当前版本不支持 Turnstile 人机验证。公开站点若仅开启登录验证，仍可匿名查看。'),
                      error: true,
                    ),
                  ),
                if (_login && !widget.requireLogin)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _login = false;
                              _error = null;
                            }),
                      child: Text(context.tr('暂不登录？返回只读连接')),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('connect-site'),
                  onPressed: _busy ? null : () => _connect(),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _login
                                    ? context.tr('登录并连接')
                                    : context.tr('检查并连接'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Icon(Icons.arrow_forward, size: 17),
                          ],
                        ),
                ),
                const SizedBox(height: 17),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 14,
                      color: p.muted,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        context.tr('密码不保存，登录凭证按站点独立存储'),
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      value,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}
