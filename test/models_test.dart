import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/formatters.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'support.dart';

void main() {
  test('地址规范化保留端口及反代前缀，拒绝明文和嵌入凭据', () {
    expect(
      normalizeBaseUrl(' https://example.com:8443/monitor/// '),
      'https://example.com:8443/monitor',
    );
    for (final input in [
      'http://example.com',
      'https://user:pass@example.com',
      'example.com',
      'https://example.com?token=secret',
      'https://example.com/#/admin',
    ]) {
      expect(() => normalizeBaseUrl(input), throwsFormatException);
    }
  });
  test('秒、毫秒及 ISO 日期一致；非法数字与布尔值不是 0', () {
    expect(metricTime(1700000000), metricTime(1700000000000));
    expect(metricTime('2026-01-01T00:00:00Z')?.year, 2026);
    expect(metricNumber(false), isNull);
    expect(metricNumber('false'), isNull);
    expect(metricNumber('NaN'), isNull);
    expect(metricNumber('0'), 0);
    expect(metricTime(double.infinity), isNull);
  });
  test('在线状态按原始上报时间，不以查看时间刷新', () {
    final now = DateTime(2026, 10, 29, 18);
    expect(
      exampleServer(
        time: now.subtract(const Duration(seconds: 299)),
      ).isOnline(now),
      isTrue,
    );
    expect(
      exampleServer(
        time: now.subtract(const Duration(seconds: 300)),
      ).isOnline(now),
      isFalse,
    );
  });
  test('资源单位、百分比、无限流量和四种流量计算模式', () {
    final server = Server({
      'ram_used': '1024',
      'ram_total': 2048,
      'net_rx_monthly': 100,
      'net_tx_monthly': 200,
      'traffic_limit': 1,
    });
    expect(server.percent('ram_used', 'ram_total'), 50);
    expect(bytes(1048576), '1.0 MB');
    expect(server.trafficUsed, 300);
    expect(server.merge({'traffic_calc_type': 'dl'}).trafficUsed, 100);
    expect(server.merge({'traffic_calc_type': 'ul'}).trafficUsed, 200);
    expect(server.merge({'traffic_calc_type': 'max'}).trafficUsed, 200);
    expect(Server({}).trafficPercent, isNull);
    expect(Server({'ram_total': 0}).percent('ram_used', 'ram_total'), isNull);
  });
  test('增量保留静态字段及真实 0，禁用与缺样本分别保留', () {
    final merged = Server({
      'id': 'a',
      'name': '原名称',
      'cpu': 20,
      'disk_used': 100,
      'loss_ct': 0,
    }).merge({'cpu': 0, 'loss_ct': false, 'loss_cu': null});
    expect(merged.name, '原名称');
    expect(merged.number('cpu'), 0);
    expect(merged.number('disk_used'), 100);
    expect(merged.enabledProbe('ct'), isFalse);
    expect(merged.enabledProbe('cu'), isFalse);
    expect(Server({'loss_ct': 0}).enabledProbe('ct'), isTrue);
  });
  test('扁平与嵌套磁盘数据统一，GPU 数组与 JSON 字符串兼容', () {
    expect(
      Server({
        'disk': {'write_bps': '2048'},
      }).value('disk_write_bps'),
      2048,
    );
    expect(
      Server({
        'gpu_info': '[{"id":"0","info":12.5,"mem_used":1024}]',
      }).gpus.first['info'],
      12.5,
    );
    expect(Server({'gpu_info': 'not json'}).gpus, isEmpty);
  });
  test('公开站点登录验证不阻止匿名读取，服务端展示开关可合并', () {
    final cfg = publicConfig({'turnstile_login_enabled': true});
    expect(cfg.isPublic, isTrue);
    expect(cfg.globalChallenge, isFalse);
    expect(cfg.loginChallenge, isTrue);
    expect(cfg.merged({'show_price': 'false'}).show('show_price'), isFalse);
    expect(cfg.probeName('ct'), '电信');
    expect(cfg.merged({'node_1_name': '东京'}).probeName('node_1'), '东京');
  });
  test('批量实时协议按样本排序，空回放和增量不被补 0', () {
    final updates = LiveUpdate.parseList([
      {
        'serverId': 'a',
        'samples': [
          {
            'ts': 1700000002000,
            'data': {'cpu': 0},
          },
          {
            'ts': 1700000001000,
            'data': {'ram_used': '10'},
          },
        ],
      },
    ]);
    expect(updates.single.samples.first.data.containsKey('cpu'), isFalse);
    expect(updates.single.samples.last.data['cpu'], 0);
    expect(LiveUpdate.parseList(null), isEmpty);
  });
  test('历史范围精确映射 Worker 白名单', () {
    expect(HistoryRange.values.map((v) => v.hours), [
      .167,
      .5,
      1,
      6,
      12,
      24,
      48,
      96,
      168,
    ]);
  });
  test('历史断线阈值与 Web 一致，不依赖混入的高频样本密度', () {
    expect(HistoryRange.values.first.gapLimit(120), const Duration(minutes: 5));
    expect(HistoryRange.values[5].gapLimit(120).inSeconds, 1368);
    expect(HistoryRange.values[5].gapLimit(240).inSeconds, 684);
    expect(HistoryRange.values[5].gapLimit(999).inSeconds, 1368);
  });
  test('线路汇总使用时间排序后的窗口末值与平均丢包，保留 0 和超时', () {
    final server = Server({
      'ping_ct': 52,
      'loss_ct': 0,
      'loss_bd': false,
      'ping': [
        {'ts': 1700000002000, 'ct': 21},
        {'ts': 1700000001000, 'ct': 52},
        {'ts': 1700000003000, 'ct': null},
      ],
      'loss': [
        {'ts': 1700000001000, 'ct': 16, 'cu': false},
        {'ts': 1700000002000, 'ct': 0, 'cu': false},
        {'ts': 1700000003000, 'ct': .3, 'cu': false},
      ],
    });
    expect(server.latestProbePing('ct'), 21);
    expect(server.averageProbeLoss('ct'), closeTo(5.4333, .0001));
    expect(server.probeDisabled('ct'), isFalse);
    expect(server.probeDisabled('cu'), isTrue);
    expect(server.probeDisabled('bd'), isTrue);
    expect(server.cardProbeKeys, ['ct', 'cm', 'node_1']);
    expect(Server({'ping_ct': 0}).latestProbePing('ct'), 0);
    expect(Server({'loss_ct': 0}).averageProbeLoss('ct'), 0);
    expect(Server({'ping_ct': -1}).latestProbePing('ct'), -1);
  });
  test('剩余价值使用计费周期、币种、免费标签与到期规则', () {
    final now = DateTime(2026, 1, 1);
    final s = Server({
      'price': r'$12/month',
      'currency': r'$',
      'billing_cycle': 'month',
      'expire_date': now.add(const Duration(days: 15)).toIso8601String(),
    });
    expect(remainingValue([s], {'USD': .5, 'CNY': 1}, now), 12);
    expect(
      remainingValue(
        [
          s.merge({'tags': '白嫖中'}),
        ],
        {'USD': .5},
        now,
      ),
      0,
    );
    expect(
      remainingValue(
        [
          s.merge({'expire_date': '2025-01-01'}),
        ],
        {'USD': .5},
        now,
      ),
      0,
    );
    expect(priceCurrency(Server({'price': 'USD 5/year'})), 'USD');
    expect(
      billingCycle(Server({'price': '¥120/年', 'billing_cycle': 'month'})),
      'year',
    );
  });
}
