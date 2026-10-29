import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'formatters.dart';
import 'models.dart';

class MonitorSession extends ChangeNotifier {
  MonitorSession({
    required this.api,
    required this.site,
    required this.config,
    this.token,
    this.onSnapshot,
    this.onAuthExpired,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final MonitorApi api;
  MonitorSite site;
  SiteConfig config;
  String? token;
  final DateTime Function() now;
  final Future<void> Function(int total, int online)? onSnapshot;
  final Future<void> Function()? onAuthExpired;
  List<Server> servers = [];
  final Map<String, List<MetricSample>> recent = {};
  final Map<String, Map<String, int>> _fieldTimes = {};
  final Map<String, Map<String, int>> _fieldRevisions = {};
  final Map<String, int> _restTimes = {};
  int _revision = 0;
  bool loading = true;
  bool refreshing = false;
  bool realtime = false;
  bool lifetimeEnded = false;
  bool needsLogin = false;
  bool unsupported = false;
  String? error;
  String connectionLabel = '正在连接';
  String? activeServerId;
  Map<String, double> rates = {...defaultExchangeRates};
  String ratesLabel = '参考汇率';
  DateTime? fetchedAt;
  LiveConnection? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _tick, _retry, _ping, _lifetime, _poll;
  bool _disposed = false, _suspended = false, _connecting = false;
  int _epoch = 0, _request = 0, _failures = 0;
  DateTime? _pong;
  bool _awaitingPong = false;
  ({double download, double upload}) summarySpeed = (download: 0, upload: 0);

  void _updateSummarySpeed() {
    summarySpeed = (
      download: total('net_in_speed', onlineOnly: true),
      upload: total('net_out_speed', onlineOnly: true),
    );
  }

  void _startTick() {
    // Web recomputes dashboard totals once per second, independently of the
    // number of servers sending updates between ticks.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _updateSummarySpeed();
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Server? server(String id) => servers.where((s) => s.id == id).firstOrNull;
  int get online => servers.where((s) => s.isOnline(now())).length;
  bool get realtimeUnavailable => _failures > 0;
  double total(String key, {bool onlineOnly = false}) => servers
      .where((s) => !onlineOnly || s.isOnline(now()))
      .fold(0.0, (sum, s) => sum + s.number(key));

  Future<void> start() async {
    _startTick();
    await refresh();
    if (!_disposed && !_suspended && !needsLogin && error == null) {
      await _connect();
    }
  }

  Future<void> refresh() async {
    if (_disposed || _suspended) return;
    final request = ++_request, revision = _revision;
    refreshing = true;
    _notify();
    try {
      WorkerApi.ensureSupported(config);
      final snapshot = await api.dashboard(site, token: token);
      if (_disposed || request != _request || _suspended) return;
      final old = {for (final s in servers) s.id: s};
      servers = snapshot.servers
          .map((fresh) => _reconcile(fresh, old[fresh.id], revision: revision))
          .toList();
      final ids = servers.map((s) => s.id).toSet();
      recent.removeWhere((id, _) => !ids.contains(id));
      _restTimes.removeWhere((id, _) => !ids.contains(id));
      _fieldTimes.removeWhere((id, _) => !ids.contains(id));
      _fieldRevisions.removeWhere((id, _) => !ids.contains(id));
      config = config.merged(snapshot.config);
      WorkerApi.ensureSupported(config);
      unsupported = false;
      applyUpdates(snapshot.reports, notify: false);
      _updateSummarySpeed();
      fetchedAt = now();
      error = null;
      needsLogin = false;
      _sendSubscription();
      if (_socket == null && !_connecting && !lifetimeEnded) {
        unawaited(_connect());
      }
      // Saving management-page metadata must not delay displaying server data
      // or establishing the live connection.
      if (onSnapshot != null) {
        unawaited(
          Future<void>.sync(
            () => onSnapshot!(servers.length, online),
          ).catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (!_disposed && request == _request) {
        error = friendlyError(e);
        _handleAuthentication(e);
        _handleUnsupported(e);
        if (!needsLogin && !unsupported && _socket == null) {
          _lostConnection(_epoch);
        }
      }
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        refreshing = false;
        _notify();
      }
    }
  }

  static String friendlyError(Object e) =>
      e is ApiFailure ? e.message : '操作失败，请检查网络后重试';
  void _handleAuthentication(Object e) {
    if (e is ApiFailure && e.kind == FailureKind.authentication) {
      ++_epoch;
      _connecting = false;
      needsLogin = true;
      token = null;
      _retry?.cancel();
      _poll?.cancel();
      _poll = null;
      unawaited(_closeSocket());
      if (onAuthExpired != null) {
        unawaited(onAuthExpired!().catchError((Object _) {}));
      }
    }
  }

  void _handleUnsupported(Object error) {
    if (error is ApiFailure && error.kind == FailureKind.unsupported) {
      ++_epoch;
      _connecting = false;
      unsupported = true;
      connectionLabel = '验证暂不支持';
      _retry?.cancel();
      _poll?.cancel();
      _poll = null;
      unawaited(_closeSocket());
    }
  }

  Future<void> authorize(SiteConfig next, String? nextToken) async {
    ++_epoch;
    _connecting = false;
    unawaited(_closeSocket().catchError((Object _) {}));
    config = next;
    token = nextToken;
    needsLogin = false;
    unsupported = false;
    lifetimeEnded = false;
    await start();
  }

  void setServerScope(String? id) {
    activeServerId = id;
    _sendSubscription();
  }

  void _sendSubscription() {
    final socket = _socket;
    if (socket == null || !realtime) return;
    final ids = activeServerId != null
        ? [activeServerId!]
        : servers.map((s) => s.id).take(500).toList();
    try {
      socket.send({
        'type': 'subscribe',
        'scope': activeServerId ?? 'all',
        'ids': ids,
      });
    } catch (_) {
      _lostConnection(_epoch);
    }
  }

  Future<void> _connect() async {
    if (_disposed ||
        _suspended ||
        _connecting ||
        _socket != null ||
        lifetimeEnded ||
        unsupported ||
        needsLogin ||
        unsupported) {
      return;
    }
    if (servers.isEmpty) {
      connectionLabel = '暂无服务器';
      _notify();
      return;
    }
    _retry?.cancel();
    _connecting = true;
    final epoch = ++_epoch;
    connectionLabel = '正在连接';
    _notify();
    try {
      final socket = api.connect(site, token: token);
      _socket = socket;
      _subscription = socket.events.listen(
        (data) => _message(epoch, data),
        onError: (Object _) => _lostConnection(epoch),
        onDone: () => _lostConnection(epoch),
      );
      await socket.ready;
      if (_disposed || _suspended || epoch != _epoch) return;
      realtime = true;
      _failures = 0;
      _pong = now();
      _awaitingPong = false;
      connectionLabel = '实时连接';
      _poll?.cancel();
      _poll = null;
      _sendSubscription();
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        if (_awaitingPong &&
            _pong != null &&
            now().difference(_pong!).inSeconds > 50) {
          _lostConnection(epoch);
          return;
        }
        try {
          socket.send({'type': 'ping'});
          _awaitingPong = true;
        } catch (_) {
          _lostConnection(epoch);
        }
      });
      _lifetime?.cancel();
      if (config.connectionMinutes > 0) {
        _lifetime = Timer(Duration(minutes: config.connectionMinutes), () {
          lifetimeEnded = true;
          connectionLabel = '实时连接已到时';
          unawaited(_closeSocket());
          _notify();
        });
      }
      _notify();
      // Reconcile the REST/subscribe gap while live updates are already buffered.
      unawaited(refresh());
    } catch (_) {
      if (epoch == _epoch) _lostConnection(epoch);
    } finally {
      if (epoch == _epoch) _connecting = false;
    }
  }

  void _message(int epoch, Object? raw) {
    if (_disposed || _suspended || epoch != _epoch) return;
    try {
      final json = jsonMap(raw is String ? jsonDecode(raw) : raw);
      switch (json['type']) {
        case 'pong':
          _pong = now();
          _awaitingPong = false;
        case 'batchUpdate':
          final reportTime = metricTime(json['ts']);
          applyUpdates(
            LiveUpdate.parseList(json['updates'])
                .map(
                  (update) => LiveUpdate(
                    update.serverId,
                    update.samples,
                    reportTime: update.reportTime ?? reportTime,
                  ),
                )
                .toList(),
          );
        default:
          break;
      }
    } on FormatException {
      /* Ignore malformed frames without losing valid state. */
    }
  }

  void applyUpdates(List<LiveUpdate> updates, {bool notify = true}) {
    if (_disposed) return;
    final byId = {for (final s in servers) s.id: s};
    for (final update in updates) {
      var current = byId[update.serverId];
      if (current == null) continue;
      final times = _fieldTimes.putIfAbsent(update.serverId, () => {});
      final revisions = _fieldRevisions.putIfAbsent(update.serverId, () => {});
      final ordered = [...update.samples]
        ..sort((a, b) => a.time.compareTo(b.time));
      for (final sample in ordered) {
        final ts = sample.time.millisecondsSinceEpoch;
        final patch = <String, dynamic>{};
        for (final entry in Server(sample.data).data.entries) {
          final baseline = _restTimes[update.serverId] ?? 0;
          if (ts < (times[entry.key] ?? 0) || ts < baseline) continue;
          times[entry.key] = ts;
          revisions[entry.key] = ++_revision;
          patch[entry.key] = entry.value;
        }
        final report =
            update.reportTime ??
            metricTime(sample.data['report_timestamp']) ??
            sample.time;
        final previous = current!.reportTime;
        if (previous == null || !report.isBefore(previous)) {
          patch['report_timestamp'] = report.millisecondsSinceEpoch;
          revisions['report_timestamp'] = ++_revision;
        }
        current = current.merge(patch);
        final list = recent.putIfAbsent(update.serverId, () => []);
        final index = list.indexWhere((v) => v.time == sample.time);
        final item = MetricSample(sample.time, Server(sample.data).data);
        if (index < 0) {
          list.add(item);
        } else {
          list[index] = MetricSample(sample.time, {
            ...list[index].data,
            ...item.data,
          });
        }
        list.sort((a, b) => a.time.compareTo(b.time));
        if (list.length > 500) list.removeRange(0, list.length - 500);
      }
      byId[update.serverId] = current!;
    }
    servers = servers.map((s) => byId[s.id]!).toList();
    if (notify) _notify();
  }

  // Static fields always come from REST. Only demonstrably newer metric
  // fields are overlaid, including updates received during this request.
  Server _reconcile(Server fresh, Server? previous, {int? revision}) {
    final baseline = fresh.reportTime?.millisecondsSinceEpoch ?? 0;
    final previousBaseline = _restTimes[fresh.id] ?? 0;
    if (baseline > previousBaseline) _restTimes[fresh.id] = baseline;
    if (previous == null) return fresh;
    final overlay = <String, dynamic>{};
    final times = _fieldTimes[fresh.id] ?? <String, int>{};
    final revisions = _fieldRevisions[fresh.id] ?? <String, int>{};
    for (final key in times.keys) {
      if ((times[key]! > baseline ||
              (revision != null && (revisions[key] ?? 0) > revision)) &&
          previous.data.containsKey(key)) {
        overlay[key] = previous.data[key];
      }
    }
    final report = previous.reportTime;
    if (report != null &&
        (fresh.reportTime == null || report.isAfter(fresh.reportTime!))) {
      overlay['report_timestamp'] = report.millisecondsSinceEpoch;
    }
    return fresh.merge(overlay);
  }

  void mergeDetail(Server detail) {
    if (_disposed) return;
    final index = servers.indexWhere((s) => s.id == detail.id);
    if (index >= 0) {
      // Detail responses omit the dashboard's latency windows.
      detail = Server({
        for (final key in ['ping', 'loss'])
          if (servers[index].data.containsKey(key))
            key: servers[index].data[key],
        ...detail.data,
      });
      servers = [...servers]..[index] = _reconcile(detail, servers[index]);
      config = config.merged(jsonMap(detail.data['sysConfig']));
      applyUpdates(
        LiveUpdate.parseList(detail.data['latestReportUpdates']),
        notify: false,
      );
    }
    _notify();
  }

  void _lostConnection(int epoch) {
    if (_disposed ||
        _suspended ||
        epoch != _epoch ||
        lifetimeEnded ||
        needsLogin ||
        unsupported) {
      return;
    }
    ++_epoch;
    realtime = false;
    _connecting = false;
    connectionLabel = '实时断开 · 自动重连';
    unawaited(_closeSocket());
    _poll ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (!realtime) unawaited(refresh());
    });
    _retry?.cancel();
    _failures = (_failures + 1).clamp(1, 6);
    final delay = (1 << _failures).clamp(2, 30);
    _retry = Timer(Duration(seconds: delay), () {
      unawaited(_recheckAndConnect());
    });
    _notify();
  }

  Future<void> _recheckAndConnect() async {
    if (_disposed || _suspended || needsLogin || unsupported || lifetimeEnded) {
      return;
    }
    try {
      final cfg = await api.config(site, token: token);
      if (_disposed || _suspended) return;
      WorkerApi.ensureSupported(cfg);
      unsupported = false;
      if (!cfg.isPublic && !cfg.authorized) {
        _handleAuthentication(
          const ApiFailure('请重新登录', kind: FailureKind.authentication),
        );
        connectionLabel = '需要登录';
        _notify();
        return;
      }
      config = config.merged(cfg.data);
      await _connect();
    } catch (e) {
      error = friendlyError(e);
      if (e is ApiFailure &&
          (e.kind == FailureKind.unsupported ||
              e.kind == FailureKind.authentication)) {
        _handleAuthentication(e);
        _handleUnsupported(e);
        _notify();
      } else {
        _lostConnection(_epoch);
      }
    }
  }

  Future<void> reconnect() async {
    if (_disposed || _suspended) return;
    lifetimeEnded = false;
    _failures = 0;
    _retry?.cancel();
    ++_epoch;
    await _closeSocket();
    await refresh();
    await _recheckAndConnect();
  }

  Future<void> _closeSocket() async {
    realtime = false;
    _ping?.cancel();
    _lifetime?.cancel();
    final subscription = _subscription;
    _subscription = null;
    final socket = _socket;
    _socket = null;
    final cancellation = subscription?.cancel();
    try {
      await socket?.close();
    } catch (_) {
      /* Already closed. */
    }
    await cancellation;
  }

  void suspend() {
    _suspended = true;
    ++_epoch;
    ++_request;
    _connecting = false;
    _retry?.cancel();
    _tick?.cancel();
    _tick = null;
    _poll?.cancel();
    _poll = null;
    connectionLabel = '连接已暂停';
    unawaited(_closeSocket());
  }

  Future<void> resume() async {
    if (_disposed) return;
    _suspended = false;
    _startTick();
    if (lifetimeEnded) {
      _notify();
      return;
    }
    await refresh();
    await _recheckAndConnect();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    ++_request;
    _tick?.cancel();
    _retry?.cancel();
    _ping?.cancel();
    _lifetime?.cancel();
    _poll?.cancel();
    unawaited(_closeSocket());
    super.dispose();
  }
}
