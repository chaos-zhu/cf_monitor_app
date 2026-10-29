import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/widgets/metric_chart.dart';

void main() {
  final base = DateTime(2026, 10, 29, 21, 37);
  MetricSample sample(int seconds, Map<String, dynamic> data) =>
      MetricSample(base.add(Duration(seconds: seconds)), Server(data).data);

  test('两分钟历史上报混入秒级 CPU 样本时，磁盘、IO 和内存曲线保留完整历史', () {
    // Same cadence and partial payload shape as the real site's response.
    final history = [
      for (var i = 0; i < 5; i++)
        sample(i * 120, {
          'cpu': .5,
          'ram_used': 1060,
          'ram_total': 1838,
          'disk_used': 18760,
          'disk_total': 30128,
          'disk': {'read_bps': 0, 'write_bps': 6744},
        }),
    ];
    final samples = [
      ...history,
      for (var i = 1; i <= 30; i++)
        sample(480 + i * 2, {
          'cpu': i / 10,
          'ram_used': 1060,
          'ram_total': 1838,
          if (i == 30) ...{
            'disk_used': 18760,
            'disk_total': 30128,
            'disk': {'read_bps': 68, 'write_bps': 5723},
          },
        }),
    ];
    final gap = HistoryRange.values.first.gapLimit(120);
    for (final line in [
      ChartLine.ratio('磁盘', 'disk_used', 'disk_total'),
      ChartLine.field('读取', 'disk_read_bps'),
      ChartLine.field('写入', 'disk_write_bps'),
    ]) {
      final segments = line.segments(samples, gap);
      expect(segments, hasLength(1));
      expect(segments.single, hasLength(6));
      expect(segments.single.first.time, base);
      expect(segments.single.last.time, base.add(const Duration(minutes: 9)));
      expect(
        line.nearest(samples, base.add(const Duration(seconds: 490)))!.time,
        history.last.time,
      );
    }
    for (final line in [
      ChartLine.field('CPU', 'cpu'),
      ChartLine.ratio('内存', 'ram_used', 'ram_total'),
    ]) {
      expect(line.segments(samples, gap).single, hasLength(35));
    }
  });

  test('未上报字段跳过，显式 null、false、超时和离线间隔保留断点', () {
    final line = ChartLine.field('ping', 'ping_ct');
    final segments = line.segments([
      sample(0, {'ping_ct': 21}),
      sample(2, {'cpu': 10}),
      sample(120, {'ping_ct': 0}),
      sample(122, {'ping_ct': null}),
      sample(124, {'ping_ct': 48}),
      sample(126, {'ping_ct': false}),
      sample(128, {'ping_ct': 25}),
      sample(130, {'ping_ct': -1}),
      sample(132, {'ping_ct': 18}),
      sample(434, {'ping_ct': 22}),
    ], const Duration(minutes: 5));
    expect(segments.map((s) => s.length), [2, 1, 1, 1, 1]);
    expect(segments.first.last.value('ping_ct'), 0);
  });

  test('24 小时稀疏历史使用站点采样配置，正常桶漂移不会断线', () {
    final samples = [
      sample(0, {'cpu': .5}),
      sample(800, {'cpu': 0}),
      sample(1521, {'cpu': 1}),
      sample(4000, {'cpu': .2}),
    ];
    final segments = ChartLine.field(
      'CPU',
      'cpu',
    ).segments(samples, HistoryRange.values[5].gapLimit(120));
    expect(segments.map((s) => s.length), [3, 1]);
  });
}
