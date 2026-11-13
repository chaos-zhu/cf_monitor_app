import 'dart:convert';

Map<String, dynamic> jsonMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

double? metricNumber(Object? value) {
  if (value == null || value is bool || value == '') return null;
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

bool configBool(Object? value, [bool fallback = false]) {
  if (value == null) return fallback;
  return value == true || value == 'true' || value == 1 || value == '1';
}

DateTime? metricTime(Object? value) {
  final number = metricNumber(value);
  if (number != null && number > 0) {
    final millis = number < 10000000000 ? number * 1000 : number;
    if (millis > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.round());
  }
  return value is String ? DateTime.tryParse(value) : null;
}

String normalizeBaseUrl(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('请输入完整站点地址，例如 https://monitor.example.com');
  }
  if (uri.scheme != 'https') {
    throw const FormatException('请使用 HTTPS 站点地址');
  }
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri.replace(path: path).toString();
}

enum SiteStatus { pending, connected, loginRequired, unavailable, unsupported }

class MonitorSite {
  const MonitorSite({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.status = SiteStatus.pending,
    this.lastVisit,
    this.serverCount,
    this.onlineCount,
    this.appPassword,
    this.userAgent,
  });
  final String id;
  final String name;
  final String baseUrl;
  final SiteStatus status;
  final DateTime? lastVisit;
  final int? serverCount;
  final int? onlineCount;
  final String? appPassword;
  final String? userAgent;
  String get host => Uri.parse(baseUrl).host;

  MonitorSite copyWith({
    String? name,
    String? baseUrl,
    SiteStatus? status,
    DateTime? lastVisit,
    int? serverCount,
    int? onlineCount,
    String? appPassword,
    String? userAgent,
  }) => MonitorSite(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    status: status ?? this.status,
    lastVisit: lastVisit ?? this.lastVisit,
    serverCount: serverCount ?? this.serverCount,
    onlineCount: onlineCount ?? this.onlineCount,
    appPassword: appPassword ?? this.appPassword,
    userAgent: userAgent ?? this.userAgent,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'status': status.name,
    'lastVisit': lastVisit?.toIso8601String(),
    'serverCount': serverCount,
    'onlineCount': onlineCount,
  };

  factory MonitorSite.fromJson(Map<String, dynamic> json) => MonitorSite(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: normalizeBaseUrl(json['baseUrl'] as String),
    status:
        SiteStatus.values.where((v) => v.name == json['status']).firstOrNull ??
        SiteStatus.pending,
    lastVisit: metricTime(json['lastVisit']),
    serverCount: metricNumber(json['serverCount'])?.toInt(),
    onlineCount: metricNumber(json['onlineCount'])?.toInt(),
  );
}

class SiteConfig {
  SiteConfig(Map<String, dynamic> json) : data = Map.unmodifiable(json);
  final Map<String, dynamic> data;
  bool get isPublic => configBool(data['is_public']);
  bool get authorized => configBool(data['authorization']);
  bool get globalChallenge => configBool(data['turnstile_enabled']);
  bool get loginChallenge =>
      globalChallenge || configBool(data['turnstile_login_enabled']);
  String get title => '${data['site_title'] ?? ''}';
  String get version => '${data['version'] ?? ''}';
  bool show(String key, [bool fallback = true]) =>
      configBool(data[key], fallback);
  int get connectionMinutes =>
      (metricNumber(data['frontend_ws_timeout_minutes']) ?? 0).toInt().clamp(
        0,
        1440,
      );
  int get latencyPoints =>
      (metricNumber(jsonMap(data['latency_window'])['points']) ?? 20)
          .toInt()
          .clamp(1, 100);
  SiteConfig merged(Map<String, dynamic> extra) =>
      SiteConfig({...data, ...extra});

  static const probeKeys = [
    'ct',
    'cu',
    'cm',
    'bd',
    'node_1',
    'node_2',
    'node_3',
    'node_4',
  ];
  String probeName(String key) =>
      '${data[{'ct': 'custom_ct_name', 'cu': 'custom_cu_name', 'cm': 'custom_cm_name', 'bd': 'custom_bd_name'}[key] ?? '${key}_name'] ?? {'ct': '电信', 'cu': '联通', 'cm': '移动', 'bd': 'BGP', 'node_1': 'Node 1', 'node_2': 'Node 2', 'node_3': 'Node 3', 'node_4': 'Node 4'}[key]}';
}

class Server {
  Server(Map<String, dynamic> raw) : data = Map.unmodifiable(_flatten(raw));
  final Map<String, dynamic> data;
  static Map<String, dynamic> _flatten(Map<String, dynamic> raw) {
    final result = {...raw};
    final disk = jsonMap(raw['disk']);
    for (final key in [
      'read_bps',
      'write_bps',
      'read_iops',
      'write_iops',
      'await_ms',
      'util',
    ]) {
      if (disk.containsKey(key)) result['disk_$key'] = disk[key];
    }
    return result;
  }

  String text(String key, [String fallback = '—']) {
    final value = data[key];
    return value == null || value == '' ? fallback : '$value';
  }

  double? value(String key) => metricNumber(data[key]);
  double number(String key) => value(key) ?? 0;
  String get id => text('id', '');
  String get name => text('name', '未命名服务器');
  String get group => text('server_group', 'DEFAULT');
  String get region => text('region', 'XX').toUpperCase();
  DateTime? get reportTime => metricTime(
    data['report_timestamp'] ?? data['last_updated'] ?? data['timestamp'],
  );
  bool isOnline([DateTime? now]) {
    final time = reportTime;
    return time != null &&
        (now ?? DateTime.now()).difference(time).inMilliseconds < 300000;
  }

  double? percent(String used, String total) {
    final u = value(used), t = value(total);
    return u != null && t != null && t > 0 ? (u / t * 100).clamp(0, 100) : null;
  }

  double get trafficUsed => switch (text('traffic_calc_type', 'total')) {
    'dl' => number('net_rx_monthly'),
    'ul' => number('net_tx_monthly'),
    'max' =>
      number('net_rx_monthly') > number('net_tx_monthly')
          ? number('net_rx_monthly')
          : number('net_tx_monthly'),
    _ => number('net_rx_monthly') + number('net_tx_monthly'),
  };
  double? get trafficPercent => number('traffic_limit') > 0
      ? trafficUsed / (number('traffic_limit') * 1073741824) * 100
      : null;
  List<String> get tags => text(
    'tags',
    '',
  ).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  bool enabledProbe(String key) =>
      data['loss_$key'] != false &&
      data['loss_$key'] != 'false' &&
      value('loss_$key') != null;
  List<Map<String, dynamic>> probeHistory(String field) {
    final raw = data[field];
    final rows = raw is List
        ? raw
              .map(jsonMap)
              .where((row) => metricTime(row['ts'] ?? row['timestamp']) != null)
              .toList()
        : <Map<String, dynamic>>[];
    rows.sort(
      (a, b) => metricTime(
        a['ts'] ?? a['timestamp'],
      )!.compareTo(metricTime(b['ts'] ?? b['timestamp'])!),
    );
    return rows;
  }

  bool probeDisabled(String key) {
    var loss = data['loss_$key'];
    if (loss == false || loss == 'false') return true;
    if (metricNumber(loss) != null) return false;
    loss = probeHistory('loss').lastOrNull?[key];
    return loss == false || loss == 'false';
  }

  List<String> get cardProbeKeys => [
    ...SiteConfig.probeKeys.where((key) => !probeDisabled(key)),
    ...SiteConfig.probeKeys.where(probeDisabled),
  ].take(3).toList();

  double? latestProbePing(String key) {
    for (final row in probeHistory('ping').reversed) {
      final value = metricNumber(row[key]);
      if (value != null) return value;
    }
    return value('ping_$key');
  }

  double? averageProbeLoss(String key) {
    final values = probeHistory(
      'loss',
    ).map((row) => metricNumber(row[key])).whereType<double>().toList();
    return values.isEmpty
        ? value('loss_$key')
        : values.reduce((a, b) => a + b) / values.length;
  }

  List<double?> get load => text(
    'load_avg',
    '',
  ).trim().split(RegExp(r'\s+')).map(metricNumber).take(3).toList();
  List<Map<String, dynamic>> get gpus {
    Object? raw = data['gpu_info'];
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return [];
      }
    }
    return raw is List ? raw.whereType<Map>().map(jsonMap).toList() : [];
  }

  Server merge(Map<String, dynamic> patch) =>
      Server({...data, ..._flatten(patch)});
}

class MetricSample {
  const MetricSample(this.time, this.data);
  final DateTime time;
  final Map<String, dynamic> data;
  double? value(String key) => Server(data).value(key);
  static MetricSample? parse(Object? value) {
    final raw = jsonMap(value);
    final data = jsonMap(raw['data'] ?? raw['payload'] ?? raw['metrics']);
    final time = metricTime(
      raw['ts'] ??
          raw['timestamp'] ??
          data['sample_timestamp'] ??
          data['timestamp'],
    );
    return time == null || data.isEmpty ? null : MetricSample(time, data);
  }
}

class LiveUpdate {
  const LiveUpdate(this.serverId, this.samples, {this.reportTime});
  final String serverId;
  final List<MetricSample> samples;
  final DateTime? reportTime;
  static List<LiveUpdate> parseList(Object? raw) {
    if (raw is! List) return [];
    return raw
        .map((item) {
          final json = jsonMap(item);
          final samples =
              (json['samples'] is List ? json['samples'] as List : <dynamic>[])
                  .map(MetricSample.parse)
                  .whereType<MetricSample>()
                  .toList()
                ..sort((a, b) => a.time.compareTo(b.time));
          return LiveUpdate(
            '${json['serverId'] ?? ''}',
            samples,
            reportTime: metricTime(json['reportTs']),
          );
        })
        .where((v) => v.serverId.isNotEmpty && v.samples.isNotEmpty)
        .toList();
  }
}

class DashboardSnapshot {
  DashboardSnapshot({
    required this.servers,
    required this.config,
    required this.reports,
  });
  final List<Server> servers;
  final Map<String, dynamic> config;
  final List<LiveUpdate> reports;
  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['servers'] is! List) throw const FormatException('服务器列表格式不受支持');
    return DashboardSnapshot(
      servers: (json['servers'] as List)
          .map((v) => Server(jsonMap(v)))
          .where((s) => s.id.isNotEmpty)
          .toList(),
      config: jsonMap(json['sysConfig']),
      reports: LiveUpdate.parseList(json['latestReportUpdates']),
    );
  }
}

class HistoryRange {
  const HistoryRange(this.label, this.hours);
  final String label;
  final double hours;
  bool get realtime => hours == values.first.hours;

  // Match Web's gap policy; live sample density must not split report history.
  Duration gapLimit(Object? configuredPoints) {
    final points = metricNumber(configuredPoints);
    final count = [60, 120, 180, 240].contains(points) ? points!.toInt() : 120;
    final millis = hours <= 1 ? 300000 : (hours * 3600000 / count).ceil() * 1.9;
    return Duration(milliseconds: millis.round().clamp(300000, 0x7fffffff));
  }

  static const values = [
    HistoryRange('10M', .167),
    HistoryRange('30M', .5),
    HistoryRange('1H', 1),
    HistoryRange('6H', 6),
    HistoryRange('12H', 12),
    HistoryRange('24H', 24),
    HistoryRange('2D', 48),
    HistoryRange('4D', 96),
    HistoryRange('7D', 168),
  ];
}
