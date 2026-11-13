import 'dart:async';
import 'dart:convert';
import 'package:cf_monitor_app/core/api.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/core/storage.dart';
import 'package:cf_monitor_app/core/installation.dart';

const siteA = MonitorSite(
  id: 'a',
  name: '主监控站',
  baseUrl: 'https://a.example.com',
);
const siteB = MonitorSite(
  id: 'b',
  name: '实验室',
  baseUrl: 'https://b.example.com',
);
String jwt({bool expired = false}) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -60 : 604800)})))}.signature';
SiteConfig publicConfig([Map<String, dynamic> extra = const {}]) => SiteConfig({
  'is_public': true,
  'authorization': false,
  'turnstile_enabled': false,
  'turnstile_login_enabled': false,
  ...extra,
});
Server exampleServer({
  String id = 'same-id',
  double cpu = .25,
  DateTime? time,
}) => Server({
  'id': id,
  'name': 'TX-香港',
  'region': 'HK',
  'server_group': 'DEFAULT',
  'os': 'Debian 12',
  'arch': 'amd64',
  'cpu': cpu,
  'cpu_cores': 2,
  'ram_used': 1024,
  'ram_total': 2048,
  'swap_used': 100,
  'swap_total': 512,
  'disk_used': 10000,
  'disk_total': 30000,
  'net_in_speed': 70,
  'net_out_speed': 68,
  'net_rx': 1073741824,
  'net_tx': 1073741824,
  'net_rx_monthly': 433400000,
  'net_tx_monthly': 224700000,
  'report_timestamp': (time ?? DateTime.now()).millisecondsSinceEpoch,
  'boot_time': DateTime.now()
      .subtract(const Duration(days: 461))
      .millisecondsSinceEpoch,
  'ip_v4': '1',
  'ip_v6': '0',
  'price': '¥ 12/月',
  'expire_date': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
  'load_avg': '0.00 0.00 0.00',
  'processes': 147,
  'tcp_conn': 2,
  'udp_conn': 23,
  'ping_ct': 57,
  'loss_ct': 0,
  'ping_cu': 106,
  'loss_cu': 5.6,
  'ping_cm': 17,
  'loss_cm': 0,
  'ping': [
    {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'ct': 57,
      'cu': 106,
      'cm': 17,
    },
  ],
  'loss': [
    {'ts': DateTime.now().millisecondsSinceEpoch, 'ct': 0, 'cu': 5.6, 'cm': 0},
  ],
  'kernel_version': '6.1.0-21-amd64',
  'cpu_info': 'Intel Xeon Platinum 8255C',
  'disk_read_bps': 0,
  'disk_write_bps': 9300,
  'disk_read_iops': 0,
  'disk_write_iops': 1.4,
  'disk_await_ms': .7,
  'disk_util': .1,
});
DashboardSnapshot snapshot([List<Server>? servers]) => DashboardSnapshot(
  servers: servers ?? [exampleServer()],
  config: {'show_three_net_details': true},
  reports: [],
);

class MemoryStorage extends SiteStorage {
  MemoryStorage([List<MonitorSite> initial = const []]) : sites = [...initial];
  List<MonitorSite> sites;
  String? defaultSiteId;
  bool compactLayout = false;
  Map<String, String> preferences = {};
  @override
  Future<Map<String, String>> readPreferences() async => {...preferences};
  @override
  Future<void> writePreferences(Map<String, String> next) async =>
      preferences = {...next};
  final tokens = <String, String>{};
  final appPasswords = <String, String>{};
  final userAgents = <String, String>{};
  @override
  Future<String?> readUserAgent(String id) async => userAgents[id];
  @override
  Future<void> writeUserAgent(String id, String? userAgent) async {
    if (userAgent == null) {
      userAgents.remove(id);
    } else {
      userAgents[id] = userAgent;
    }
  }

  @override
  Future<String?> readAppPassword(String id) async => appPasswords[id];
  @override
  Future<void> writeAppPassword(String id, String? password) async {
    if (password == null) {
      appPasswords.remove(id);
    } else {
      appPasswords[id] = password;
    }
  }

  @override
  Future<String?> readDefaultSiteId() async => defaultSiteId;
  @override
  Future<void> writeDefaultSiteId(String? id) async => defaultSiteId = id;
  @override
  Future<bool> readCompactLayout() async => compactLayout;
  @override
  Future<void> writeCompactLayout(bool compact) async =>
      compactLayout = compact;
  @override
  Future<List<MonitorSite>> load() async => [...sites];
  @override
  Future<void> save(List<MonitorSite> next) async {
    await Future<void>.delayed(Duration.zero);
    sites = [...next];
  }

  @override
  Future<String?> readToken(String id) async => tokens[id];
  @override
  Future<void> writeToken(String id, String? token) async {
    if (token == null) {
      tokens.remove(id);
    } else {
      tokens[id] = token;
    }
  }
}

class FakeSocket implements LiveConnection {
  FakeSocket({Future<void>? ready}) : _ready = ready ?? Future.value();
  final Future<void> _ready;
  final controller = StreamController<Object?>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  @override
  Future<void> get ready => _ready;
  @override
  Stream<Object?> get events => controller.stream;
  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
  }

  void emit(Map<String, dynamic> message) =>
      controller.add(jsonEncode(message));
  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

class FakeApi extends MonitorApi {
  Server? editableServer;
  Future<Server> Function()? serverForEditHandler;
  Map<String, dynamic> editSettings = {'wss_report_enabled': true};
  @override
  Future<Map<String, dynamic>> editorSettings(
    MonitorSite site, {
    required String token,
  }) async => editSettings;
  final edits = <Map<String, dynamic>>[];
  Future<void> Function()? editServerHandler;
  @override
  Future<Server> serverForEdit(
    MonitorSite site,
    String id, {
    required String token,
  }) async => serverForEditHandler != null
      ? await serverForEditHandler!()
      : editableServer ?? exampleServer(id: id);
  @override
  Future<void> editServer(
    MonitorSite site,
    String id,
    Map<String, dynamic> fields, {
    required String token,
  }) async {
    if (editServerHandler != null) await editServerHandler!();
    edits.add({'site': site.id, 'id': id, 'token': token, ...fields});
  }

  final passwordChecks = <String?>[];
  @override
  Future<void> validateAppPassword(MonitorSite site) async {
    passwordChecks.add(site.appPassword);
  }

  SiteConfig settings = publicConfig();
  Future<SiteConfig> Function(MonitorSite, String?)? configHandler;
  Future<DashboardSnapshot> Function()? dashboardHandler;
  Future<List<MetricSample>> Function(HistoryRange)? historyHandler;
  FakeSocket Function()? socketFactory;
  Future<String> Function(MonitorSite, String, String, String)?
  addServerHandler;
  Future<InstallParameters> Function()? installParametersHandler;
  final installRequests = <({String siteId, String token})>[];
  Future<void> Function()? deleteServerHandler;
  final deletedServers = <({String siteId, String id, String token})>[];
  final forcedRefreshes = <bool>[];
  final addedServers =
      <({String siteId, String token, String name, String group})>[];
  int configCalls = 0, dashboardCalls = 0, loginCalls = 0, historyCalls = 0;
  final sockets = <FakeSocket>[];
  final sitesRequested = <String>[];
  @override
  Future<SiteConfig> config(MonitorSite site, {String? token}) async {
    configCalls++;
    if (configHandler != null) return configHandler!(site, token);
    return token != null ? settings.merged({'authorization': true}) : settings;
  }

  @override
  Future<String> login(
    MonitorSite site,
    String username,
    String password,
  ) async {
    loginCalls++;
    return jwt();
  }

  @override
  Future<DashboardSnapshot> dashboard(
    MonitorSite site, {
    String? token,
    bool forceRefresh = false,
  }) async {
    dashboardCalls++;
    forcedRefreshes.add(forceRefresh);
    sitesRequested.add(site.id);
    return dashboardHandler != null ? dashboardHandler!() : snapshot();
  }

  @override
  Future<String> addServer(
    MonitorSite site, {
    required String token,
    required String name,
    String group = '',
  }) async {
    addedServers.add((siteId: site.id, token: token, name: name, group: group));
    if (addServerHandler != null) {
      return addServerHandler!(site, token, name, group);
    }
    return 'new-server-id';
  }

  @override
  Future<void> deleteServer(
    MonitorSite site,
    String id, {
    required String token,
  }) async {
    deletedServers.add((siteId: site.id, id: id, token: token));
    if (deleteServerHandler != null) await deleteServerHandler!();
  }

  @override
  Future<InstallParameters> installParameters(
    MonitorSite site, {
    required String token,
  }) async {
    installRequests.add((siteId: site.id, token: token));
    if (installParametersHandler != null) return installParametersHandler!();
    return const InstallParameters(secret: 'test-install-secret');
  }

  @override
  Future<Server> detail(MonitorSite site, String id, {String? token}) async =>
      exampleServer(id: id);
  @override
  Future<List<MetricSample>> history(
    MonitorSite site,
    String id,
    HistoryRange range, {
    String? token,
  }) async {
    historyCalls++;
    if (historyHandler != null) return historyHandler!(range);
    if (range.hours > 24 && token == null) {
      throw const ApiFailure(
        '查看超过 24 小时的历史数据需要登录',
        kind: FailureKind.permission,
      );
    }
    final now = DateTime.now();
    return List.generate(
      20,
      (i) => MetricSample(
        now.subtract(Duration(seconds: (19 - i) * 20)),
        exampleServer(cpu: i / 10).data,
      ),
    );
  }

  @override
  LiveConnection connect(MonitorSite site, {String? token}) {
    final socket = socketFactory?.call() ?? FakeSocket();
    sockets.add(socket);
    return socket;
  }
}
