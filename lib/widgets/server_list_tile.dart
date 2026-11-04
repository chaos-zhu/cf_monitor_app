import 'package:flutter/material.dart';
import '../core/strings.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import 'common.dart';

class ServerListTile extends StatelessWidget {
  const ServerListTile({
    required this.server,
    required this.config,
    required this.now,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Server server;
  final SiteConfig config;
  final DateTime now;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final online = server.isOnline(now);
    final probes = _probeKeys.take(3).toList();
    return Material(
      color: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    flag(server.region),
                    style: const TextStyle(fontSize: 18, height: 1.2),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.serverName(server),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ServerIpBadge(server: server),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: online ? context.tr('在线') : context.tr('离线'),
                    child: Semantics(
                      label: online ? context.tr('在线') : context.tr('离线'),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: online ? p.green : p.red,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: p.muted, size: 16),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${compactServerOs(server.text('os'))} · ${context.tr(compactServerUptime(server.data['boot_time'], now))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: p.muted,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('负载 {0}', [decimal(server.load.firstOrNull)]),
                    style: mono(
                      context,
                      size: 10,
                      color: p.muted,
                    ).copyWith(height: 1.2),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      context,
                      'CPU',
                      server.value('cpu')?.clamp(0, 100),
                      p.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metric(
                      context,
                      'RAM',
                      server.percent('ram_used', 'ram_total'),
                      p.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metric(
                      context,
                      'DISK',
                      server.percent('disk_used', 'disk_total'),
                      p.blue,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Divider(height: 1, color: p.line.withValues(alpha: .45)),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final key in probes)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _probe(context, key),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _speed(
                        context,
                        context.tr('下载'),
                        server.value('net_in_speed'),
                        p.green,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _speed(
                        context,
                        context.tr('上传'),
                        server.value('net_out_speed'),
                        p.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _probeKeys => config.show('show_three_net_details')
      ? server.cardProbeKeys.where((key) => !server.probeDisabled(key)).toList()
      : SiteConfig.probeKeys.where(server.enabledProbe).toList();

  Widget _metric(
    BuildContext context,
    String label,
    double? value,
    Color color,
  ) {
    final p = Palette.of(context);
    final effectiveColor = value != null && value >= 95
        ? p.red
        : value != null && value >= 80
        ? p.amber
        : color;
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: mono(
                context,
                size: 10,
                color: p.muted,
              ).copyWith(height: 1.2),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value == null ? '—' : '${decimal(value, 1)}%',
                  maxLines: 1,
                  style: mono(context, size: 10).copyWith(height: 1.2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ((value ?? 0) / 100).clamp(0, 1),
            minHeight: 4,
            color: effectiveColor,
            backgroundColor: p.track,
          ),
        ),
      ],
    );
  }

  Widget _speed(
    BuildContext context,
    String label,
    double? value,
    Color color,
  ) => Tooltip(
    message: '$label ${bytes(value, speed: true)}',
    child: _networkItem(context, label, bytes(value, speed: true), color),
  );

  Widget _networkItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: Palette.of(context).muted,
        ),
      ),
      const SizedBox(height: 5),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(11) * 1.2,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: mono(context, size: 11, color: color).copyWith(height: 1.2),
          ),
        ),
      ),
    ],
  );

  Widget _probe(BuildContext context, String key) {
    final p = Palette.of(context);
    final ping = server.latestProbePing(key);
    final text = ping == null
        ? '—'
        : ping <= 0
        ? context.tr('超时')
        : '${decimal(ping, 0)}ms';
    final color = ping == null
        ? p.muted
        : ping <= 0
        ? p.red
        : ping >= 160
        ? p.amber
        : p.green;
    return Tooltip(
      message: context.tr('{0} · {1} · {2}% 丢包', [
        context.probeName(config, key),
        text,
        decimal(server.averageProbeLoss(key), 1),
      ]),
      child: _networkItem(context, context.probeName(config, key), text, color),
    );
  }
}
