import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/models.dart';

class Palette {
  Palette(this.dark);
  final bool dark;
  static Palette of(BuildContext context) =>
      Palette(Theme.of(context).brightness == Brightness.dark);
  Color get background =>
      dark ? const Color(0xff101a17) : const Color(0xfff4f6f3);
  Color get paper => dark ? const Color(0xff192620) : Colors.white;
  Color get text => dark ? const Color(0xffe7f0eb) : const Color(0xff182c25);
  Color get muted => dark ? const Color(0xffa4b5ab) : const Color(0xff718078);
  Color get line => dark ? const Color(0xff2a3c31) : const Color(0xffe4eae5);
  Color get green => dark ? const Color(0xff68d4ac) : const Color(0xff168565);
  Color get soft => dark ? const Color(0xff213e30) : const Color(0xffe9f4ed);
  Color get blue => dark ? const Color(0xff80a5ff) : const Color(0xff497de1);
  Color get red => dark ? const Color(0xfff48787) : const Color(0xffd95555);
  Color get amber => dark ? const Color(0xffedbc66) : const Color(0xffb67b1e);
  Color get track => dark ? const Color(0xff2b3a31) : const Color(0xffedf0eb);
}

ThemeData appTheme(Brightness brightness) {
  final p = Palette(brightness == Brightness.dark);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff168565),
    brightness: brightness,
    surface: p.paper,
    primary: p.green,
    error: p.red,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    dividerColor: p.line,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(bodyColor: p.text, displayColor: p.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: p.line),
      ),
      hintStyle: TextStyle(color: p.muted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff168565),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.green),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: p.line),
      backgroundColor: p.paper,
      selectedColor: p.soft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
  );
}

TextStyle mono(
  BuildContext context, {
  double size = 12,
  Color? color,
  FontWeight? weight,
}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['PingFang SC', 'sans-serif'],
  fontSize: size,
  color: color ?? Palette.of(context).text,
  fontWeight: weight,
);

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.paper,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {this.color, this.dot = false, super.key});
  final String label;
  final Color? color;
  final bool dot;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: 6, color: c),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(
    this.message, {
    this.action,
    this.onAction,
    this.error = false,
    super.key,
  });
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = error ? p.red : p.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: c, fontSize: 12, height: 1.5)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title, {
    this.subtitle,
    this.action,
    this.onAction,
    this.icon = Icons.dns_outlined,
    super.key,
  });
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: p.green),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 9),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.6),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

class MetricBar extends StatelessWidget {
  const MetricBar(
    this.label,
    this.value, {
    this.unlimited = false,
    this.blue = false,
    super.key,
  });
  final String label;
  final double? value;
  final bool unlimited, blue;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = value != null && value! >= 95
        ? p.red
        : value != null && value! >= 80
        ? p.amber
        : blue
        ? p.blue
        : p.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: mono(context, size: 11, color: p.muted)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: unlimited ? 1 : ((value ?? 0) / 100).clamp(0, 1),
                minHeight: 5,
                backgroundColor: p.track,
                color: unlimited ? p.green.withValues(alpha: .35) : c,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              unlimited ? '∞' : percent(value),
              textAlign: TextAlign.right,
              style: mono(context, size: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoRows extends StatelessWidget {
  const InfoRows(this.rows, {super.key});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.muted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 7,
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: mono(context, size: 12).copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1) Divider(height: 1, color: p.line),
          ],
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class ServerCard extends StatelessWidget {
  const ServerCard({
    required this.server,
    required this.config,
    required this.now,
    required this.onTap,
    this.onLongPress,
    super.key,
  });
  final Server server;
  final SiteConfig config;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final online = server.isOnline(now);
    return AppPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    flag(server.region),
                    style: const TextStyle(fontSize: 23),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                server.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ServerIpBadge(server: server),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${compactServerOs(server.text('os'))} · 运行 ${compactServerUptime(server.data['boot_time'], now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  StatusPill(
                    online ? '在线' : '离线',
                    color: online ? p.green : p.red,
                  ),
                  Icon(Icons.chevron_right, size: 17, color: p.muted),
                ],
              ),
              if (server.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final tag in server.tags)
                      StatusPill(tag, color: p.muted),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              MetricBar('CPU', server.value('cpu')?.clamp(0, 100)),
              MetricBar(
                'RAM',
                server.percent('ram_used', 'ram_total'),
                blue: true,
              ),
              MetricBar(
                'DISK',
                server.percent('disk_used', 'disk_total'),
                blue: true,
              ),
              const SizedBox(height: 8),
              _line(
                context,
                'LOAD',
                server.load.isEmpty
                    ? '—'
                    : server.load.map((v) => decimal(v)).join(' / '),
              ),
              _line(
                context,
                'NET',
                '↓ ${bytes(server.value('net_in_speed'), speed: true)}  ↑ ${bytes(server.value('net_out_speed'), speed: true)}',
              ),
              _line(
                context,
                'TRF',
                '↓ ${bytes(server.value('net_rx_monthly'))}  ↑ ${bytes(server.value('net_tx_monthly'))}',
              ),
              if (config.show('show_tf') && server.number('traffic_limit') > 0)
                _line(
                  context,
                  'LIMIT',
                  '${bytes(server.trafficUsed)} / ${bytes(server.number('traffic_limit') * 1073741824)}',
                ),
              if (config.show('show_three_net_details')) ...[
                const SizedBox(height: 10),
                LatencyPanel(server: server, config: config),
              ] else ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final key in SiteConfig.probeKeys.where(
                      server.enabledProbe,
                    ))
                      Text(
                        '${config.probeName(key)} ${server.number('ping_$key') < 0 ? '超时' : '${decimal(server.value('ping_$key'), 0)} ms'}',
                        style: mono(context, size: 10, color: p.muted),
                      ),
                  ],
                ),
              ],
              if ((config.show('show_price') &&
                      server.text('price', '').isNotEmpty) ||
                  (config.show('show_expire') &&
                      server.text('expire_date', '').isNotEmpty)) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: p.line),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 7,
                  children: [
                    if (config.show('show_expire') &&
                        server.text('expire_date', '').isNotEmpty)
                      Text(
                        '到期 ${expiry(server.data['expire_date'], now)}',
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                    if (config.show('show_price') &&
                        server.text('price', '').isNotEmpty)
                      Text(
                        billingPrice(server),
                        style: mono(context, size: 11, color: p.muted),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 43,
          child: Text(
            key,
            style: mono(context, size: 11, color: Palette.of(context).muted),
          ),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: mono(context, size: 11),
            ),
          ),
        ),
      ],
    ),
  );
}

String compactServerOs(String os) => os
    .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
    .replaceAll('GNU/Linux ', '')
    .trim();

String compactServerUptime(Object? bootTime, DateTime now) {
  final boot = metricTime(bootTime);
  if (boot == null || boot.isAfter(now)) return '—';
  final elapsed = now.difference(boot);
  return elapsed.inDays > 0 ? '${elapsed.inDays} 天' : '${elapsed.inHours} 小时';
}

class ServerIpBadge extends StatelessWidget {
  const ServerIpBadge({required this.server, super.key});
  final Server server;

  @override
  Widget build(BuildContext context) {
    final ipv4 = configBool(server.data['ip_v4']);
    final ipv6 = configBool(server.data['ip_v6']);
    if (!ipv4 && !ipv6) return const SizedBox.shrink();
    final label = ipv4 && ipv6
        ? 'IPv4/6'
        : ipv4
        ? 'IPv4'
        : 'IPv6';
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: switch (label) {
            'IPv4' =>
              p.dark ? const Color(0xffb392f0) : const Color(0xff7c3aed),
            'IPv6' =>
              p.dark ? const Color(0xfff778ba) : const Color(0xffdb2777),
            _ => p.dark ? const Color(0xff39d2c0) : const Color(0xff0d9488),
          },
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: p.dark ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class LatencyPanel extends StatelessWidget {
  const LatencyPanel({required this.server, required this.config, super.key});
  final Server server;
  final SiteConfig config;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final keys = server.cardProbeKeys;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                config.probeName(key),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              flex: 3,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  (server.latestProbePing(key) ?? 0) <= 0
                                      ? '超时'
                                      : '${decimal(server.latestProbePing(key), 0)}ms 延迟',
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                  style: mono(
                                    context,
                                    size: 10,
                                    color: p.muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${decimal(server.averageProbeLoss(key), 1)}% 丢包',
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: mono(context, size: 10, color: p.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(child: _samples(context, key, false)),
                      const SizedBox(width: 7),
                      Expanded(child: _samples(context, key, true)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _samples(BuildContext context, String key, bool loss) {
    final p = Palette.of(context);
    final ping = server.probeHistory('ping');
    final losses = server.probeHistory('loss');
    final count = [
      config.latencyPoints,
      ping.length,
      losses.length,
    ].reduce((a, b) => a > b ? a : b);
    double? value(List<Map<String, dynamic>> samples, int index) =>
        index < samples.length ? metricNumber(samples[index][key]) : null;
    Color color(int index) {
      final pingValue = value(ping, index);
      final lossValue = value(losses, index);
      final hasPing = pingValue != null && pingValue >= 0;
      final hasLoss = lossValue != null;
      if (!hasPing && !hasLoss) return p.red.withValues(alpha: .52);
      if (loss) {
        if (!hasLoss) return p.track;
        if (lossValue <= 0) return p.green;
        if (lossValue < 5) return p.blue;
        if (lossValue < 20) return p.amber;
        return p.red;
      }
      if (!hasPing || pingValue == 0) return p.red;
      if (pingValue < 80) return p.green;
      if (pingValue < 160) return p.blue;
      if (pingValue < 240) return p.amber;
      return p.red;
    }

    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == count - 1 ? 0 : 2),
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: color(i),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
