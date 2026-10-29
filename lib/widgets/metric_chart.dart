import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import 'common.dart';

class ChartLine {
  const ChartLine(this.label, this.read, {this.includes});
  final String label;
  final double? Function(Map<String, dynamic>) read;
  final bool Function(Map<String, dynamic>)? includes;
  factory ChartLine.field(String label, String key) => ChartLine(
    label,
    (row) => Server(row).value(key),
    includes: (row) => Server(row).data.containsKey(key),
  );
  factory ChartLine.ratio(String label, String used, String total) => ChartLine(
    label,
    (row) => Server(row).percent(used, total),
    includes: (row) => row.containsKey(used) || row.containsKey(total),
  );

  List<List<MetricSample>> segments(
    List<MetricSample> samples,
    Duration gapLimit,
  ) {
    final result = <List<MetricSample>>[];
    var segment = <MetricSample>[];
    for (final sample in samples) {
      // A partial live update says nothing about the other metrics. Explicit
      // null/disabled values, however, remain real breaks in this series.
      if (!(includes?.call(sample.data) ?? true)) continue;
      final value = read(sample.data);
      if (value == null || value < 0) {
        segment = [];
        continue;
      }
      if (segment.isEmpty ||
          sample.time.difference(segment.last.time) > gapLimit) {
        segment = [];
        result.add(segment);
      }
      segment.add(sample);
    }
    return result;
  }

  MetricSample? nearest(List<MetricSample> samples, DateTime time) {
    MetricSample? nearest;
    for (final sample in samples) {
      if (!(includes?.call(sample.data) ?? true)) continue;
      if (nearest == null ||
          sample.time.difference(time).abs() <
              nearest.time.difference(time).abs()) {
        nearest = sample;
      }
    }
    return nearest;
  }
}

class MetricChartCard extends StatefulWidget {
  const MetricChartCard({
    required this.title,
    required this.unit,
    required this.samples,
    required this.lines,
    required this.current,
    this.initiallyExpanded = false,
    this.maxY,
    this.gapLimit = const Duration(minutes: 5),
    super.key,
  });
  final String title, unit, current;
  final List<MetricSample> samples;
  final List<ChartLine> lines;
  final bool initiallyExpanded;
  final double? maxY;
  final Duration gapLimit;
  @override
  State<MetricChartCard> createState() => _MetricChartCardState();
}

class _MetricChartCardState extends State<MetricChartCard> {
  late bool expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.show_chart, size: 17, color: p.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 7,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          widget.current,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: mono(context, size: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  widget.unit,
                  style: TextStyle(fontSize: 10, color: p.muted),
                ),
              ),
              MetricChart(
                samples: widget.samples,
                lines: widget.lines,
                unit: widget.unit,
                maxY: widget.maxY,
                gapLimit: widget.gapLimit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MetricChart extends StatefulWidget {
  const MetricChart({
    required this.samples,
    required this.lines,
    required this.unit,
    this.maxY,
    this.gapLimit = const Duration(minutes: 5),
    this.height = 148,
    super.key,
  });
  final List<MetricSample> samples;
  final List<ChartLine> lines;
  final String unit;
  final double? maxY;
  final Duration gapLimit;
  final double height;
  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  DateTime? selectedTime;
  final Set<int> hidden = {};
  List<Color> colors(BuildContext context) {
    final p = Palette.of(context);
    return [
      p.green,
      p.blue,
      p.amber,
      const Color(0xff9b7cce),
      const Color(0xffd86e91),
      p.red,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final palette = colors(context);
    final samples = widget.samples;
    final selected = selectedTime == null || samples.isEmpty
        ? null
        : samples.reduce(
            (a, b) =>
                a.time.difference(selectedTime!).abs() <
                    b.time.difference(selectedTime!).abs()
                ? a
                : b,
          );
    final visible = [
      for (var i = 0; i < widget.lines.length; i++)
        if (!hidden.contains(i)) i,
    ];
    final hasData = samples.any(
      (point) => visible.any((i) => widget.lines[i].read(point.data) != null),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasData)
          SizedBox(
            height: widget.height,
            child: Center(
              child: Text(
                '此时段暂无可用数据',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              void select(double x) {
                if (samples.isEmpty) return;
                final ratio = ((x - 42) / (box.maxWidth - 52)).clamp(0, 1);
                final start = samples.first.time.millisecondsSinceEpoch,
                    end = samples.last.time.millisecondsSinceEpoch;
                setState(
                  () => selectedTime = DateTime.fromMillisecondsSinceEpoch(
                    (start + (end - start) * ratio).round(),
                  ),
                );
              }

              return Semantics(
                label: '${widget.unit}历史曲线，${samples.length}个采样点，点击或拖动查看数值',
                child: MouseRegion(
                  onHover: (e) => select(e.localPosition.dx),
                  child: GestureDetector(
                    onTapDown: (e) => select(e.localPosition.dx),
                    onHorizontalDragUpdate: (e) => select(e.localPosition.dx),
                    child: CustomPaint(
                      size: Size(box.maxWidth, widget.height),
                      painter: _ChartPainter(
                        samples: samples,
                        lines: widget.lines,
                        visible: visible,
                        colors: palette,
                        palette: p,
                        maxY: widget.maxY,
                        selected: selected?.time,
                        gapLimit: widget.gapLimit,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (widget.lines.length > 1)
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              for (var i = 0; i < widget.lines.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() {
                    if (hidden.contains(i)) {
                      hidden.remove(i);
                    } else if (hidden.length < widget.lines.length - 1) {
                      hidden.add(i);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hidden.contains(i)
                              ? Icons.circle_outlined
                              : Icons.circle,
                          size: 7,
                          color: palette[i % palette.length],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.lines[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            color: hidden.contains(i) ? p.muted : p.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        if (selected != null) ...[
          const SizedBox(height: 7),
          Text(
            dateTime(selected.time),
            style: mono(context, size: 10, color: p.muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              for (final i in visible)
                Text(
                  '${widget.lines[i].label} ${decimal(widget.lines[i].read(widget.lines[i].nearest(samples, selected.time)?.data ?? {}))}',
                  style: mono(context, size: 10),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.lines,
    required this.visible,
    required this.colors,
    required this.palette,
    required this.gapLimit,
    this.maxY,
    this.selected,
  });
  final List<MetricSample> samples;
  final List<ChartLine> lines;
  final List<int> visible;
  final List<Color> colors;
  final Palette palette;
  final Duration gapLimit;
  final double? maxY;
  final DateTime? selected;
  void text(
    Canvas canvas,
    String value,
    Offset offset, {
    bool right = false,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          color: palette.muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        offset.dx -
            (right
                ? painter.width
                : center
                ? painter.width / 2
                : 0),
        offset.dy,
      ),
    );
  }

  String tick(double value) {
    if (value >= 1000000) return '${decimal(value / 1000000, 1)}M';
    if (value >= 1000) return '${decimal(value / 1000, 1)}k';
    return decimal(value, value < 10 ? 1 : 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width < 90) return;
    final plot = Rect.fromLTRB(42, 9, size.width - 10, size.height - 24);
    double highest = 0;
    for (final sample in samples) {
      for (final i in visible) {
        final value = lines[i].read(sample.data);
        if (value != null && value >= 0) highest = math.max(highest, value);
      }
    }
    final ceiling = maxY ?? (highest == 0 ? 1 : highest * 1.15);
    final start = samples.first.time.millisecondsSinceEpoch.toDouble();
    final end = samples.last.time.millisecondsSinceEpoch.toDouble();
    final span = math.max(1, end - start);
    double x(DateTime time) =>
        plot.left + (time.millisecondsSinceEpoch - start) / span * plot.width;
    double y(double v) =>
        plot.bottom - (v.clamp(0, ceiling) / ceiling) * plot.height;
    for (var i = 0; i < 3; i++) {
      final yy = plot.top + plot.height * i / 2;
      canvas.drawLine(
        Offset(plot.left, yy),
        Offset(plot.right, yy),
        Paint()
          ..color = palette.line
          ..strokeWidth = .7,
      );
      text(
        canvas,
        tick(ceiling * (1 - i / 2)),
        Offset(plot.left - 7, yy - 6),
        right: true,
      );
    }
    canvas.save();
    canvas.clipRect(plot.inflate(2));
    for (final index in visible) {
      final path = Path();
      for (final segment in lines[index].segments(samples, gapLimit)) {
        for (var i = 0; i < segment.length; i++) {
          final sample = segment[i];
          final point = Offset(
            x(sample.time),
            y(lines[index].read(sample.data)!),
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
          if (segment.length == 1) {
            canvas.drawCircle(
              point,
              2.5,
              Paint()..color = colors[index % colors.length],
            );
          }
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[index % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (selected != null) {
      final sx = x(selected!);
      canvas.drawLine(
        Offset(sx, plot.top),
        Offset(sx, plot.bottom),
        Paint()
          ..color = palette.muted.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      for (final index in visible) {
        final sample = lines[index].nearest(samples, selected!);
        if (sample != null) {
          final value = lines[index].read(sample.data);
          if (value != null && value >= 0) {
            canvas.drawCircle(
              Offset(x(sample.time), y(value)),
              3,
              Paint()..color = colors[index % colors.length],
            );
          }
        }
      }
    }
    canvas.restore();
    String axis(DateTime time) => end - start > 86400000
        ? '${time.month}/${time.day} ${time.hour}h'
        : clock(time).substring(0, 5);
    text(canvas, axis(samples.first.time), Offset(plot.left, plot.bottom + 9));
    text(
      canvas,
      axis(DateTime.fromMillisecondsSinceEpoch(((start + end) / 2).round())),
      Offset(plot.center.dx, plot.bottom + 9),
      center: true,
    );
    text(
      canvas,
      axis(samples.last.time),
      Offset(plot.right, plot.bottom + 9),
      right: true,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
