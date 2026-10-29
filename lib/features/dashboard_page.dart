import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/api.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import 'connect_page.dart';
import 'detail_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({required this.connection, super.key});
  final ConnectionResult connection;
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  late final MonitorSession session;
  String _region = '全部';
  bool _leaving = false;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = ref.read(sitesProvider);
    final site = widget.connection.site;
    session = MonitorSession(
      api: ref.read(apiProvider),
      site: site,
      config: widget.connection.config ?? SiteConfig({}),
      token: widget.connection.token,
      onAuthExpired: () => controller.clearToken(site.id),
      onSnapshot: (count, online) async {
        final current = controller.sites
            .where((s) => s.id == site.id)
            .firstOrNull;
        if (current != null) {
          await controller.save(
            current.copyWith(
              status: SiteStatus.connected,
              lastVisit: DateTime.now(),
              serverCount: count,
              onlineCount: online,
            ),
          );
        }
      },
    );
    unawaited(_start());
    unawaited(_rates());
  }

  Future<void> _start() async {
    if (widget.connection.config != null) {
      _ready = true;
      await session.start();
      return;
    }
    final controller = ref.read(sitesProvider);
    final site = session.site;
    try {
      var token = await controller.token(site.id);
      if (!mounted || _leaving) return;
      final cfg = await ref.read(apiProvider).config(site, token: token);
      if (!mounted || _leaving) return;
      WorkerApi.ensureSupported(cfg);
      session.config = cfg;
      if (token != null && !cfg.authorized) {
        await controller.clearToken(site.id);
        token = null;
      }
      if (!mounted || _leaving) return;
      session.token = token;
      if (!cfg.isPublic && !cfg.authorized) {
        await controller.save(site.copyWith(status: SiteStatus.loginRequired));
        if (!mounted || _leaving) return;
        final connected = await _login();
        _ready = connected;
        if (!connected && mounted && !_leaving) Navigator.pop(context);
        return;
      }
    } catch (e) {
      if (!mounted || _leaving) return;
      try {
        await controller.save(
          site.copyWith(
            status: e is ApiFailure && e.kind == FailureKind.unsupported
                ? SiteStatus.unsupported
                : SiteStatus.unavailable,
          ),
        );
      } catch (_) {
        /* Preserve the original connection error. */
      }
      if (mounted && !_leaving) {
        Navigator.pop(context, MonitorSession.friendlyError(e));
      }
      return;
    }
    if (mounted && !_leaving) {
      _ready = true;
      await session.start();
    }
  }

  Future<void> _rates() async {
    final storage = ref.read(storageProvider);
    final api = ref.read(apiProvider);
    try {
      final cached = await storage.readRates();
      final cachedRates = jsonMap(cached?['rates']);
      final date = metricTime(cached?['date']);
      if (cachedRates.isNotEmpty) {
        session.rates = {
          ...defaultExchangeRates,
          for (final e in cachedRates.entries)
            if ((metricNumber(e.value) ?? 0) > 0) e.key: metricNumber(e.value)!,
        };
        session.ratesLabel = '缓存汇率';
      }
      if (date != null && DateTime.now().difference(date).inHours < 24) {
        if (mounted) setState(() {});
        return;
      }
      final rates = await api.exchangeRates();
      if (!mounted) return;
      if (rates != null) {
        session.rates = {...defaultExchangeRates, ...rates};
        session.ratesLabel = '最新汇率';
        await storage.writeRates({
          'date': DateTime.now().toIso8601String(),
          'rates': session.rates,
        });
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready || _leaving) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(session.resume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      session.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.dispose();
    super.dispose();
  }

  Future<bool> _login() async {
    final existing =
        ref
            .read(sitesProvider)
            .sites
            .where((s) => s.id == session.site.id)
            .firstOrNull ??
        session.site;
    final result = await Navigator.push<ConnectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectPage(
          site: existing,
          config: session.config,
          requireLogin: true,
        ),
      ),
    );
    if (result == null || !mounted) return false;
    await session.authorize(result.config!, result.token);
    return true;
  }

  Future<void> _detail(Server server) async {
    session.setServerScope(server.id);
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            DetailPage(session: session, serverId: server.id, onLogin: _login),
      ),
    );
    if (mounted) {
      session.setServerScope(null);
      unawaited(session.refresh());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final p = Palette.of(context);
      final servers = session.servers;
      final regions = <String, int>{};
      for (final server in servers) {
        regions.update(server.region, (v) => v + 1, ifAbsent: () => 1);
      }
      final visible = _region == '全部'
          ? servers
          : servers.where((s) => s.region == _region).toList();
      final groups = <String, List<Server>>{};
      for (final server in visible) {
        groups.putIfAbsent(server.group, () => []).add(server);
      }
      return PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _leaving = true;
            session.suspend();
          }
        },
        child: Scaffold(
          body: SafeArea(
            child: PageBody(
              child: RefreshIndicator(
                notificationPredicate: (notification) =>
                    _ready && !session.loading && notification.depth == 0,
                onRefresh: () async {
                  if (_ready && !session.loading) await session.refresh();
                },
                child: CustomScrollView(
                  key: PageStorageKey('dashboard-${session.site.id}'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    session.site.name,
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: StatusPill(
                                      session.connectionLabel,
                                      color: session.realtime
                                          ? p.green
                                          : p.amber,
                                      dot: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Tooltip(
                              message: session.site.host,
                              child: Text(
                                session.site.host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(context, size: 12, color: p.muted),
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (!session.loading) _summary(context),
                            const SizedBox(height: 13),
                            if (session.error != null)
                              Notice(
                                session.error!,
                                error: true,
                                action: session.needsLogin ? '重新登录' : '重试',
                                onAction: session.needsLogin
                                    ? _login
                                    : session.refresh,
                              ),
                            if (session.lifetimeEnded)
                              Notice(
                                '实时连接已达到站点设置的时长。',
                                action: '继续连接',
                                onAction: session.reconnect,
                              ),
                            if (!session.realtime &&
                                session.realtimeUnavailable &&
                                !session.lifetimeEnded &&
                                servers.isNotEmpty)
                              Text(
                                '实时连接暂不可用 · 数据更新于 ${dateTime(session.fetchedAt)}，可下拉刷新',
                                style: TextStyle(fontSize: 11, color: p.muted),
                              ),
                            if (servers.length > 500)
                              const Notice(
                                '此站点超过 500 台服务器，首期仅订阅前 500 台；其余指标通过刷新更新。',
                              ),
                            const SizedBox(height: 8),
                            if (!session.loading)
                              SingleChildScrollView(
                                key: const Key('region-filters'),
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _regionFilter('全部', '全部 ${servers.length}'),
                                    for (final e in regions.entries)
                                      _regionFilter(
                                        e.key,
                                        '${flag(e.key)} ${e.key} ${e.value}',
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (session.loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 64),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(height: 14),
                              Text('正在加载服务器…'),
                            ],
                          ),
                        ),
                      ),
                    if (!session.loading && servers.isEmpty)
                      SliverToBoxAdapter(
                        child: EmptyState(
                          session.error == null ? '此站点暂无服务器' : '暂时无法读取服务器',
                          subtitle: session.error == null
                              ? '在 Web 后台添加服务器后，下拉刷新即可查看。'
                              : null,
                        ),
                      ),
                    if (servers.isNotEmpty && visible.isEmpty)
                      const SliverToBoxAdapter(
                        child: EmptyState(
                          '此地区暂无服务器',
                          subtitle: '选择“全部”查看其他地区。',
                        ),
                      ),
                    for (final entry in groups.entries) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 11),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key,
                                style: mono(context, size: 11, color: p.muted),
                              ),
                              Text(
                                '${entry.value.length} 台服务器',
                                style: TextStyle(fontSize: 11, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList.builder(
                          itemCount: entry.value.length,
                          itemBuilder: (context, index) {
                            final server = entry.value[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 13),
                              child: ServerCard(
                                key: ValueKey(
                                  '${session.site.id}:${server.id}',
                                ),
                                server: server,
                                config: session.config,
                                now: session.now(),
                                onTap: () => _detail(server),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (!session.loading)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                          child: Text(
                            '已显示当前站点全部服务器',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: p.muted),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _regionFilter(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: _region == value,
      onSelected: (_) => setState(() => _region = value),
      showCheckmark: false,
    ),
  );

  Widget _summary(BuildContext context) {
    final p = Palette.of(context);
    Widget item(String label, Widget value, [String? extra]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
        const SizedBox(height: 8),
        value,
        if (extra != null) ...[
          const SizedBox(height: 5),
          Text(extra, style: mono(context, size: 10, color: p.muted)),
        ],
      ],
    );
    return AppPanel(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: item(
                  '服务器',
                  Text(
                    '${session.online} 在线 / ${session.servers.length - session.online} 离线',
                    style: mono(context, size: 13, weight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: item(
                  '实时速度',
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '↓ ${bytes(session.summarySpeed.download, speed: true)}',
                          maxLines: 1,
                          style: mono(context, size: 12, color: p.green),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '↑ ${bytes(session.summarySpeed.upload, speed: true)}',
                          maxLines: 1,
                          style: mono(context, size: 12, color: p.blue),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: item(
                  '总流量',
                  Text(
                    '↓ ${bytes(session.total('net_rx'))}',
                    style: mono(context, size: 13),
                  ),
                  '↑ ${bytes(session.total('net_tx'))}',
                ),
              ),
              if (session.config.show('show_price')) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: item(
                    '剩余价值',
                    Text(
                      '¥ ${decimal(remainingValue(session.servers, session.rates, session.now()))}',
                      style: mono(context, size: 15, weight: FontWeight.w600),
                    ),
                    'CNY · ${session.ratesLabel}',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
