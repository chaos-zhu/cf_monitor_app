import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import '../widgets/metric_chart.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    required this.session,
    required this.serverId,
    required this.onLogin,
    super.key,
  });
  final MonitorSession session;
  final String serverId;
  final Future<bool> Function() onLogin;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with WidgetsBindingObserver {
  HistoryRange range = HistoryRange.values.first;
  String tab = '资源';
  List<MetricSample> _history = [];
  Server? _detail;
  String? _historyError, _detailError;
  bool _loading = true, _loginNeeded = false;
  int _request = 0;
  MonitorSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_request;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ++_request;
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _historyError = null;
      _detailError = null;
      _loginNeeded = false;
    });
    Future<void> detail() async {
      try {
        final server = await session.api.detail(
          session.site,
          widget.serverId,
          token: session.token,
        );
        if (!mounted || request != _request) return;
        _detail = server;
        session.mergeDetail(server);
      } catch (e) {
        if (mounted && request == _request) {
          _detailError = MonitorSession.friendlyError(e);
        }
      }
    }

    Future<void> history() async {
      try {
        final samples = await session.api.history(
          session.site,
          widget.serverId,
          range,
          token: session.token,
        );
        if (!mounted || request != _request) return;
        _history = samples;
      } catch (e) {
        if (mounted && request == _request) {
          _historyError = MonitorSession.friendlyError(e);
          _loginNeeded =
              e is ApiFailure &&
              (e.kind == FailureKind.permission ||
                  e.kind == FailureKind.authentication);
        }
      }
    }

    await Future.wait([detail(), history()]);
    if (mounted && request == _request) setState(() => _loading = false);
  }

  List<MetricSample> get _samples {
    final cutoff = session.now().subtract(
      Duration(milliseconds: (range.hours * 3600000).round()),
    );
    final points = <int, Map<String, dynamic>>{};
    for (final sample in [
      ..._history,
      if (range.realtime)
        ...session.recent[widget.serverId] ?? <MetricSample>[],
    ]) {
      if (sample.time.isBefore(cutoff)) continue;
      final ts = sample.time.millisecondsSinceEpoch;
      points[ts] = {...?points[ts], ...sample.data};
    }
    final times = points.keys.toList()..sort();
    return times
        .map(
          (ts) => MetricSample(
            DateTime.fromMillisecondsSinceEpoch(ts),
            points[ts]!,
          ),
        )
        .toList();
  }

  Future<void> _login() async {
    if (await widget.onLogin() && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final p = Palette.of(context);
      final server = session.server(widget.serverId) ?? _detail;
      return Scaffold(
        body: SafeArea(
          child: PageBody(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 7, 20, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (server == null) ...[
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_detailError != null)
                      Notice(
                        _detailError!,
                        error: true,
                        action: '重试',
                        onAction: _load,
                      ),
                  ] else ...[
                    _hero(context, server),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          '历史时间范围',
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                        Text(
                          '${range.label} · ${_samples.length} 个采样点',
                          style: mono(context, size: 10, color: p.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: p.paper,
                        border: Border.all(color: p.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        key: const Key('history-ranges'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            for (final item in HistoryRange.values)
                              Semantics(
                                selected: range == item,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(38, 38),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: range == item
                                        ? p.green
                                        : Colors.transparent,
                                    foregroundColor: range == item
                                        ? Colors.white
                                        : p.muted,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (range == item) return;
                                    setState(() {
                                      range = item;
                                      _history = [];
                                    });
                                    unawaited(_load());
                                  },
                                  child: Text(
                                    item.label,
                                    style: mono(
                                      context,
                                      size: 10,
                                      color: range == item
                                          ? Colors.white
                                          : p.muted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 2,
                      child: _loading
                          ? const LinearProgressIndicator(minHeight: 2)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (_detailError != null)
                      Notice(
                        _detailError!,
                        error: true,
                        action: '重试',
                        onAction: _load,
                      ),
                    if (_historyError != null)
                      Notice(
                        _historyError!,
                        error: true,
                        action: _loginNeeded ? '登录站点' : '重试',
                        onAction: _loginNeeded ? _login : _load,
                      ),
                    if (session.needsLogin)
                      Notice('实时连接需要重新登录。', action: '重新登录', onAction: _login),
                    Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Row(
                        children: [
                          _tabButton('资源', '资源指标'),
                          _tabButton('网络', '网络质量'),
                          _tabButton('系统', '系统信息'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (tab == '资源') ..._resources(context, server),
                    if (tab == '网络') ..._network(context, server),
                    if (tab == '系统') ..._system(server),
                    const SizedBox(height: 8),
                    Text(
                      '最后上报 ${dateTime(server.reportTime)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: p.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _tabButton(String value, String label) {
    final p = Palette.of(context);
    final selected = tab == value;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? p.green : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: TextButton(
            onPressed: () => setState(() => tab = value),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 42),
              foregroundColor: selected ? p.green : p.muted,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, Server s) {
    final p = Palette.of(context);
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${flag(s.region)} ${s.name}',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                s.isOnline() ? '在线' : '离线',
                color: s.isOnline() ? p.green : p.red,
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            '${s.text('os')} · ${s.text('arch')} · ${_ip(s)}',
            style: TextStyle(fontSize: 11, color: p.muted),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: p.line),
          const SizedBox(height: 14),
          Wrap(
            spacing: 25,
            runSpacing: 10,
            children: [
              _heroValue(context, '运行时间', uptime(s.data['boot_time'])),
              _heroValue(
                context,
                'CPU 核心',
                '${decimal(s.value('cpu_cores'), 0)} vCPU',
              ),
              _heroValue(
                context,
                '内存容量',
                bytes(
                  s.value('ram_total') == null
                      ? null
                      : s.number('ram_total') * 1048576,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _ip(Server s) => [
    if (configBool(s.data['ip_v4'])) 'IPv4',
    if (configBool(s.data['ip_v6'])) 'IPv6',
  ].join(' / ');
  Widget _heroValue(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 10, color: Palette.of(context).muted),
      ),
      const SizedBox(height: 6),
      Text(value, style: mono(context, size: 12)),
    ],
  );
  Widget _chart(
    String key,
    String title,
    String unit,
    String current,
    List<ChartLine> lines, {
    bool open = false,
    double? maxY,
  }) => MetricChartCard(
    key: ValueKey(key),
    title: title,
    unit: unit,
    current: current,
    samples: _samples,
    lines: lines,
    initiallyExpanded: open,
    maxY: maxY,
    gapLimit: range.gapLimit(session.config.data['long_history_points']),
  );
  bool _has(Server s, String key) =>
      s.value(key) != null || _history.any((v) => v.value(key) != null);
  List<Widget> _resources(BuildContext context, Server s) => [
    _chart('cpu', 'CPU 使用率', '%', percent(s.value('cpu')), [
      ChartLine.field('CPU', 'cpu'),
    ], open: true),
    _chart(
      'ram',
      '内存使用率',
      '%',
      percent(s.percent('ram_used', 'ram_total')),
      [
        ChartLine.ratio('内存', 'ram_used', 'ram_total'),
        if (s.number('swap_total') > 0)
          ChartLine.ratio('Swap', 'swap_used', 'swap_total'),
      ],
      open: true,
      maxY: 100,
    ),
    _chart(
      'disk',
      '磁盘使用率',
      '%',
      percent(s.percent('disk_used', 'disk_total')),
      [ChartLine.ratio('磁盘', 'disk_used', 'disk_total')],
      maxY: 100,
    ),
    if (_has(s, 'disk_read_bps') || _has(s, 'disk_write_bps'))
      _chart(
        'io-speed',
        '磁盘 IO · 吞吐',
        'B/s',
        'R ${bytes(s.value('disk_read_bps'), speed: true)} / W ${bytes(s.value('disk_write_bps'), speed: true)}',
        [
          ChartLine.field('读取', 'disk_read_bps'),
          ChartLine.field('写入', 'disk_write_bps'),
        ],
      ),
    if (_has(s, 'disk_read_iops') || _has(s, 'disk_write_iops'))
      _chart(
        'iops',
        '磁盘 IO · 操作数',
        'IOPS',
        '${decimal(s.value('disk_read_iops'), 1)} / ${decimal(s.value('disk_write_iops'), 1)}',
        [
          ChartLine.field('读 IOPS', 'disk_read_iops'),
          ChartLine.field('写 IOPS', 'disk_write_iops'),
        ],
      ),
    if (_has(s, 'disk_await_ms'))
      _chart(
        'await',
        '磁盘 IO · 等待',
        'ms',
        '${decimal(s.value('disk_await_ms'), 1)} ms',
        [ChartLine.field('await', 'disk_await_ms')],
      ),
    if (_has(s, 'disk_util'))
      _chart('util', '磁盘 IO · 利用率', '%', percent(s.value('disk_util')), [
        ChartLine.field('util', 'disk_util'),
      ], maxY: 100),
    _chart('load', '负载监控', '负载', s.load.map((v) => decimal(v)).join(' / '), [
      for (var i = 0; i < 3; i++)
        ChartLine(['1 分钟', '5 分钟', '15 分钟'][i], (row) {
          final load = Server(row).load;
          return i < load.length ? load[i] : null;
        }, includes: (row) => row.containsKey('load_avg')),
    ]),
    _chart('process', '进程数', '个', decimal(s.value('processes'), 0), [
      ChartLine.field('进程', 'processes'),
    ]),
    if (s.gpus.isNotEmpty) ...[
      _chart(
        'gpu',
        'GPU 使用率',
        '%',
        s.gpus.map((g) => percent(metricNumber(g['info']))).join(' / '),
        _gpuLines(s, 'info'),
        maxY: 100,
      ),
      if (s.gpus.any((g) => metricNumber(g['mem_used']) != null))
        _chart(
          'gpu-memory',
          'GPU 显存',
          'MiB',
          s.gpus
              .map(
                (g) =>
                    '${decimal(metricNumber(g['mem_used']), 0)} / ${decimal(metricNumber(g['mem_total']), 0)} MiB',
              )
              .join(' · '),
          _gpuLines(s, 'mem_used'),
        ),
      if (s.gpus.any((g) => metricNumber(g['sm_clock']) != null))
        _chart(
          'gpu-clock',
          'GPU 时钟',
          'MHz',
          s.gpus
              .map((g) => '${decimal(metricNumber(g['sm_clock']), 0)} MHz')
              .join(' / '),
          _gpuLines(s, 'sm_clock'),
        ),
      if (s.gpus.any((g) => metricNumber(g['power']) != null))
        _chart(
          'gpu-power',
          'GPU 功耗',
          'W',
          s.gpus
              .map((g) => '${decimal(metricNumber(g['power']), 1)} W')
              .join(' / '),
          _gpuLines(s, 'power'),
        ),
    ],
  ];
  List<ChartLine> _gpuLines(Server s, String key) => [
    for (var i = 0; i < s.gpus.length; i++)
      ChartLine(
        '${s.gpus[i]['name'] ?? s.gpus[i]['id'] ?? 'GPU $i'}',
        (row) {
          final gpus = Server(row).gpus;
          final id = s.gpus[i]['id'];
          final gpu = id != null
              ? gpus.where((g) => g['id'] == id).firstOrNull
              : (i < gpus.length ? gpus[i] : null);
          return metricNumber(gpu?[key]);
        },
        includes: (row) => row.containsKey('gpu_info'),
      ),
  ];
  List<Widget> _network(BuildContext context, Server s) {
    final probes = SiteConfig.probeKeys
        .where((key) => s.enabledProbe(key))
        .toList();
    return [
      InfoRows([
        (
          '实时速度',
          '↓ ${bytes(s.value('net_in_speed'), speed: true)} / ↑ ${bytes(s.value('net_out_speed'), speed: true)}',
        ),
        (
          '总流量',
          '↓ ${bytes(s.value('net_rx'))} / ↑ ${bytes(s.value('net_tx'))}',
        ),
        (
          '月流量',
          '↓ ${bytes(s.value('net_rx_monthly'))} / ↑ ${bytes(s.value('net_tx_monthly'))}',
        ),
        (
          '月流量限制',
          '${bytes(s.trafficUsed)} / ${s.number('traffic_limit') <= 0 ? '不限量' : bytes(s.number('traffic_limit') * 1073741824)}',
        ),
      ]),
      const SizedBox(height: 13),
      _chart(
        'network',
        '网络速度',
        'B/s',
        '↓ ${bytes(s.value('net_in_speed'), speed: true)}',
        [
          ChartLine.field('下载', 'net_in_speed'),
          ChartLine.field('上传', 'net_out_speed'),
        ],
        open: true,
      ),
      _chart(
        'connections',
        '连接数',
        '个',
        'TCP ${decimal(s.value('tcp_conn'), 0)} / UDP ${decimal(s.value('udp_conn'), 0)}',
        [
          ChartLine.field('TCP', 'tcp_conn'),
          ChartLine.field('UDP', 'udp_conn'),
        ],
      ),
      if (probes.isNotEmpty) ...[
        _chart(
          'latency',
          '线路延迟',
          'ms',
          probes
              .map(
                (key) =>
                    '${session.config.probeName(key)} ${s.number('ping_$key') < 0 ? '超时' : '${decimal(s.value('ping_$key'), 0)} ms'}',
              )
              .join(' · '),
          [
            for (final key in probes)
              ChartLine(
                session.config.probeName(key),
                (row) {
                  final value = Server(row).value('ping_$key');
                  return value != null && value >= 0 ? value : null;
                },
                includes: (row) => row.containsKey('ping_$key'),
              ),
          ],
          open: true,
        ),
        _chart(
          'loss',
          '丢包率',
          '%',
          probes
              .map(
                (key) =>
                    '${session.config.probeName(key)} ${percent(s.value('loss_$key'))}',
              )
              .join(' · '),
          [
            for (final key in probes)
              ChartLine.field(session.config.probeName(key), 'loss_$key'),
          ],
          maxY: 100,
        ),
      ] else
        const Notice('当前服务器没有启用的线路探测数据。'),
    ];
  }

  List<Widget> _system(Server s) => [
    InfoRows([
      ('操作系统 / 架构', '${s.text('os')} / ${s.text('arch')}'),
      ('内核版本', s.text('kernel_version')),
      ('CPU 型号', s.text('cpu_info')),
      ('CPU 核心数', '${decimal(s.value('cpu_cores'), 0)} 核'),
      if (s.gpus.isNotEmpty)
        (
          'GPU 型号',
          s.gpus.map((g) => '${g['name'] ?? g['id'] ?? 'GPU'}').join(' / '),
        ),
      (
        '总磁盘 / 内存',
        '${bytes(s.value('disk_total') == null ? null : s.number('disk_total') * 1048576)} / ${bytes(s.value('ram_total') == null ? null : s.number('ram_total') * 1048576)}',
      ),
      (
        'Swap',
        '${decimal(s.value('swap_used'), 0)} / ${decimal(s.value('swap_total'), 0)} MiB',
      ),
      ('运行时间', uptime(s.data['boot_time'])),
      ('启动时间', dateTime(metricTime(s.data['boot_time']))),
      ('最后更新', dateTime(s.reportTime)),
      ('IPv4 / IPv6', _ip(s).isEmpty ? '不可用' : _ip(s)),
      if (session.config.show('show_expire'))
        ('到期时间', s.text('expire_date', '未设置')),
      if (session.config.show('show_price')) ('价格', billingPrice(s)),
      (
        '流量计算方式',
        switch (s.text('traffic_calc_type', 'total')) {
          'dl' => '仅下载',
          'ul' => '仅上传',
          'max' => '上传／下载较大值',
          _ => '上传 + 下载',
        },
      ),
      if (s.tags.isNotEmpty) ('标签', s.tags.join(' · ')),
    ]),
  ];
}
