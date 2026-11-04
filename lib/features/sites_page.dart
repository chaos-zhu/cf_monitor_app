import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings.dart';
import '../app.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'connect_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';

class SitesPage extends ConsumerStatefulWidget {
  const SitesPage({super.key});
  @override
  ConsumerState<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends ConsumerState<SitesPage> {
  String? _busy;
  bool _entering = false;
  bool _startupHandled = false;

  void _openDefaultOnce(MonitorSite? site) {
    _startupHandled = true;
    if (site == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _busy != null ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      // Push above the management page so both system back and iOS swipe
      // return here. Only attempt this once during the app's startup.
      unawaited(_enter(site));
    });
  }

  Future<void> _edit([MonitorSite? site]) async {
    final result = await Navigator.push<ConnectionResult>(
      context,
      MaterialPageRoute(builder: (_) => ConnectPage(site: site)),
    );
    if (result != null && mounted) await _dashboard(result);
  }

  Future<void> _dashboard(ConnectionResult result) async {
    final error = await Navigator.push<String>(
      context,
      CupertinoPageRoute(builder: (_) => DashboardPage(connection: result)),
    );
    if (mounted && error != null) showMessage(context, error);
  }

  Future<void> _enter(MonitorSite site) async {
    if (_busy != null || _entering) return;
    // Open the page before reading credentials or making network requests.
    _entering = true;
    try {
      await _dashboard(ConnectionResult(site, null, null));
    } finally {
      _entering = false;
    }
  }

  Future<void> _menu(MonitorSite site) async {
    final store = ref.read(sitesProvider);
    final isDefault = store.defaultSiteId == site.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isDefault ? Icons.home : Icons.home_outlined),
              title: Text(
                isDefault ? context.tr('取消默认主页站点') : context.tr('设为默认主页站点'),
              ),
              onTap: () => Navigator.pop(context, 'default'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.tr('编辑站点')),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Palette.of(context).red,
              ),
              title: Text(context.tr('从本机删除')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'default') {
      setState(() => _busy = site.id);
      try {
        await store.setDefaultSite(isDefault ? null : site.id);
        if (mounted) {
          showMessage(
            context,
            isDefault ? context.tr('已取消默认主页站点') : context.tr('已设为默认主页站点'),
          );
        }
      } catch (_) {
        if (mounted) showMessage(context, context.tr('保存默认主页失败，请重试'));
      } finally {
        if (mounted) setState(() => _busy = null);
      }
      return;
    }
    if (action == 'edit') {
      await _edit(site);
      return;
    }
    if (action != 'delete') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('删除本机站点？')),
        content: Text(
          context.tr('将移除“{0}”的本机记录和登录凭证，服务器端数据不受影响。', [site.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('删除')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(sitesProvider).remove(site);
      } catch (_) {
        if (mounted) showMessage(context, context.tr('删除失败，请重试'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sitesProvider);
    final p = Palette.of(context);
    if (!_startupHandled && !state.loading && state.error == null) {
      _openDefaultOnce(state.defaultSite);
    }
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: context.tr('设置'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xff168565),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.dns_outlined,
                size: 19,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'CF Monitor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: PageBody(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: state.load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
                  children: [
                    Text(
                      context.tr('我的站点'),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      context.tr('{0} 个站点，各自连接与管理', [state.sites.length]),
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 26),
                    if (state.error != null)
                      Notice(
                        state.error!,
                        error: true,
                        action: context.tr('重新读取'),
                        onAction: state.load,
                      ),
                    if (state.sites.isEmpty && state.error == null)
                      EmptyState(
                        context.tr('还没有添加站点'),
                        subtitle: context.tr(
                          '连接你的 CF Server Monitor，\n随时查看服务器运行状态。',
                        ),
                        action: context.tr('添加第一个站点'),
                        onAction: () => _edit(),
                      ),
                    if (state.sites.isNotEmpty) ...[
                      Text(
                        context.tr('全部站点'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 13),
                      for (final site in state.sites)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: _siteCard(site),
                        ),
                    ],
                    if (state.sites.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _busy == null ? () => _edit() : null,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.tr('添加站点')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 51),
                          side: BorderSide(color: p.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: p.muted),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            context.tr('登录凭证仅保存在本机安全存储中'),
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _siteCard(MonitorSite site) {
    final p = Palette.of(context);
    final busy = _busy == site.id;
    final (label, color) = switch (site.status) {
      SiteStatus.pending => (context.tr('待连接'), p.muted),
      SiteStatus.connected => (context.tr('上次连接成功'), p.green),
      SiteStatus.loginRequired => (context.tr('需要登录'), p.amber),
      SiteStatus.unavailable => (context.tr('连接失败'), p.red),
      SiteStatus.unsupported => (context.tr('验证暂不支持'), p.amber),
    };
    final hasSnapshot = site.lastVisit != null && site.serverCount != null;
    final statusLabel = site.status == SiteStatus.connected && hasSnapshot
        ? context.tr('{0} 在线 / {1} 台（快照）', [
            site.onlineCount ?? 0,
            site.serverCount,
          ])
        : label;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  site.status == SiteStatus.loginRequired
                      ? Icons.lock_outline
                      : Icons.dns_outlined,
                  color: color,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            site.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (ref.watch(sitesProvider).defaultSiteId ==
                            site.id) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: context.tr('默认主页站点'),
                            child: Icon(Icons.home, size: 16, color: p.green),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      site.host,
                      style: mono(context, size: 11, color: p.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('编辑{0}', [site.name]),
                onPressed: _busy == null ? () => _menu(site) : null,
                icon: Icon(Icons.more_horiz, color: p.muted, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.line),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(statusLabel, color: color, dot: true),
                    if (site.lastVisit != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${dateTime(site.lastVisit)}${site.status != SiteStatus.connected && hasSnapshot ? context.tr('\n{0} 在线 / {1} 台（快照）', [site.onlineCount ?? 0, site.serverCount]) : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: p.muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _busy == null ? () => _enter(site) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            site.status == SiteStatus.loginRequired
                                ? context.tr('登录站点')
                                : site.status == SiteStatus.unavailable
                                ? context.tr('重试')
                                : context.tr('进入站点'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_outward, size: 14),
                        ],
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
