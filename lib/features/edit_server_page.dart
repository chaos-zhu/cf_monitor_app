import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/strings.dart';
import '../widgets/common.dart';

class EditServerPage extends ConsumerStatefulWidget {
  const EditServerPage({
    required this.session,
    required this.serverId,
    required this.onLogin,
    super.key,
  });
  final MonitorSession session;
  final String serverId;
  final Future<bool> Function() onLogin;
  @override
  ConsumerState<EditServerPage> createState() => _EditServerPageState();
}

class _EditServerPageState extends ConsumerState<EditServerPage> {
  static const textFields = [
    'name',
    'server_group',
    'region',
    'tags',
    'note',
    'price',
    'expire_date',
    'traffic_limit',
    'traffic_alert_percent',
    'interface',
    'rx_correction',
    'tx_correction',
    'custom_ct',
    'custom_cu',
    'custom_cm',
    'custom_bd',
    'node_1',
    'node_2',
    'node_3',
    'node_4',
  ];
  static const flags = [
    'auto_renewal',
    'auto_update',
    'is_hidden',
    'offline_notify_disabled',
  ];
  static const currencies = [
    '\$',
    '¥',
    '€',
    '£',
    '¥JPY',
    'HK\$',
    'A\$',
    'C\$',
    'S\$',
    'NZ\$',
    '₣',
    '₩',
    '₹',
    '฿',
    '₫',
    '₱',
    'Rp',
    'RM',
    '₺',
    '₪',
    '৳',
    '₨',
    'LKR',
    '₮',
    '₽',
    'R\$',
    'kr',
    'zł',
    '₴',
    '₸',
    'R',
    '₦',
    'EGP',
    'د.إ',
    '﷼',
    'Q',
  ];
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final values = <String, dynamic>{};
  Map<String, dynamic>? settings;
  bool busy = true, needsLogin = false, loaded = false;
  String? error;

  @override
  void initState() {
    super.initState();
    for (final key in textFields) {
      fields[key] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (needsLogin || widget.session.token == null) {
        if (!await widget.onLogin() || !mounted) return;
        needsLogin = false;
      }
      final token = widget.session.token;
      if (token == null) return;
      final api = ref.read(apiProvider);
      final results = await Future.wait<Object>([
        api.serverForEdit(widget.session.site, widget.serverId, token: token),
        api.editorSettings(widget.session.site, token: token),
      ]);
      if (!mounted) return;
      final data = (results[0] as Server).data;
      settings = results[1] as Map<String, dynamic>;
      for (final key in textFields) {
        fields[key]!.text =
            '${(key == 'region' ? data['region_override'] ?? data[key] : data[key]) ?? ''}';
      }
      final expiry = DateTime.tryParse(fields['expire_date']!.text);
      if (expiry != null) {
        fields['expire_date']!.text = expiry.toIso8601String().substring(0, 10);
      }
      for (final key in flags) {
        values[key] = configBool(data[key]);
      }
      for (final entry in {
        'currency': '¥',
        'billing_cycle': 'month',
        'traffic_calc_type': 'total',
        'reset_day': 1,
        'collect_interval': 0,
        'report_interval': 60,
        'wss_report_interval': 2,
        'connection_mode': 'auto',
        'ping_mode': 'tcp',
      }.entries) {
        values[entry.key] = data[entry.key] ?? entry.value;
      }
      if (!configBool(settings!['wss_report_enabled'])) {
        values['connection_mode'] = 'http';
      }
      loaded = true;
    } catch (e) {
      if (mounted) {
        setState(() {
          error = MonitorSession.friendlyError(e);
          needsLogin = e is ApiFailure && e.kind == FailureKind.authentication;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    if (busy || !form.currentState!.validate()) return;
    for (final entry in fields.entries) {
      final validation = _validate(entry.key, entry.value.text);
      if (validation != null) {
        setState(() => error = validation);
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (needsLogin || widget.session.token == null) {
        if (!await widget.onLogin() || !mounted) return;
        needsLogin = false;
      }
      final token = widget.session.token;
      if (token == null) return;
      final payload = <String, dynamic>{
        for (final e in fields.entries) e.key: e.value.text.trim(),
      };
      for (final key in flags) {
        payload[key] = values[key] == true ? '1' : '0';
      }
      for (final key in [
        'currency',
        'billing_cycle',
        'traffic_calc_type',
        'connection_mode',
        'ping_mode',
      ]) {
        payload[key] = values[key];
      }
      for (final key in [
        'reset_day',
        'collect_interval',
        'report_interval',
        'wss_report_interval',
      ]) {
        payload[key] = int.parse('${values[key]}');
      }
      payload['traffic_alert_percent'] = payload['traffic_alert_percent'] == ''
          ? null
          : int.parse(payload['traffic_alert_percent'] as String);
      await ref
          .read(apiProvider)
          .editServer(
            widget.session.site,
            widget.serverId,
            payload,
            token: token,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = MonitorSession.friendlyError(e);
          needsLogin = e is ApiFailure && e.kind == FailureKind.authentication;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _validate(String key, String? input) {
    final value = (input ?? '').trim();
    if (key == 'name' && value.isEmpty) return context.tr('请输入服务器名称');
    if (key == 'name' && value.length > 100) {
      return context.tr('服务器名称最多 100 个字符');
    }
    if (key == 'traffic_alert_percent' && value.isNotEmpty) {
      final n = int.tryParse(value);
      if (n == null || n < 0 || n > 100) return context.tr('请输入 0 到 100 的整数');
    }
    if (['traffic_limit', 'rx_correction', 'tx_correction'].contains(key) &&
        value.isNotEmpty &&
        (double.tryParse(value) == null ||
            !double.parse(value).isFinite ||
            double.parse(value) < 0)) {
      return context.tr('请输入有效的非负数');
    }
    if (key == 'expire_date' && value.isNotEmpty) {
      final date = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != value) {
        return context.tr('请输入有效日期，格式为 YYYY-MM-DD');
      }
    }
    return null;
  }

  Widget _text(
    String key,
    String label, {
    bool numeric = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 7),
        TextFormField(
          key: Key('edit-$key'),
          controller: fields[key],
          enabled: !busy,
          maxLines: lines,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          style: TextStyle(color: Palette.of(context).text, fontSize: 14),
          decoration: _inputDecoration(hint: hint),
          validator: (v) => _validate(key, v),
        ),
      ],
    ),
  );

  Widget _fieldLabel(String label) => Text(
    context.tr(label),
    style: TextStyle(
      color: Palette.of(context).muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _inputDecoration({String? hint, Widget? suffix}) {
    final p = Palette.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: p.line),
    );
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: p.paper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: p.green, width: 1.4),
      ),
    );
  }

  Widget _select(
    String key,
    String label,
    Map<String, String> choices, {
    bool enabled = true,
  }) {
    final value = '${values[key]}';
    final options = {...choices};
    if (!options.containsKey(value)) options[value] = value;
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 7),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('edit-$key'),
              borderRadius: BorderRadius.circular(8),
              onTap: busy || !enabled
                  ? null
                  : () async {
                      final selected = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (sheetContext) => SafeArea(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(sheetContext).height * .7,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    12,
                                  ),
                                  child: Text(
                                    context.tr(label),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      for (final entry in options.entries)
                                        ListTile(
                                          title: Text(context.tr(entry.value)),
                                          trailing: entry.key == value
                                              ? Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: p.green,
                                                )
                                              : null,
                                          onTap: () => Navigator.pop(
                                            sheetContext,
                                            entry.key,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (selected != null && mounted) {
                        setState(() => values[key] = selected);
                      }
                    },
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: enabled ? p.paper : p.track,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(options[value]!),
                        style: TextStyle(
                          fontSize: 14,
                          color: enabled ? p.text : p.muted,
                        ),
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 18, color: p.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch(String key, String label, {String? subtitle}) {
    final p = Palette.of(context);
    final selected = values[key] == true;
    Future<void> toggle() async {
      final v = !selected;
      if (key == 'auto_update' && v) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('自动更新风险提示')),
            content: Text(context.tr('开启后需重新复制安装命令并在服务器执行，请确认更新来源可信。')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('取消')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('确认开启')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      setState(() => values[key] = v);
    }

    return Semantics(
      label: context.tr(label),
      toggled: selected,
      enabled: !busy,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('edit-$key'),
          onTap: busy ? null : toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(label),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          context.tr(subtitle),
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 24,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: selected ? p.green : p.line,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 180),
                    alignment: selected
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String label) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 16),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 17,
            decoration: BoxDecoration(
              color: p.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            context.tr(label),
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: p.line)),
        ],
      ),
    );
  }

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 350 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.2) {
        return Column(children: [first, second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _dateField() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('到期日期'),
        const SizedBox(height: 7),
        TextFormField(
          key: const Key('edit-expire_date'),
          controller: fields['expire_date'],
          enabled: !busy,
          readOnly: true,
          style: TextStyle(color: Palette.of(context).text, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'YYYY-MM-DD',
            suffix: IconButton(
              tooltip: context.tr('清除日期'),
              onPressed: busy ? null : () => fields['expire_date']!.clear(),
              icon: const Icon(Icons.clear),
            ),
          ),
          validator: (value) => _validate('expire_date', value),
          onTap: () async {
            final today = DateTime.now();
            final current =
                DateTime.tryParse(fields['expire_date']!.text) ?? today;
            final first = DateTime(1900);
            final last = DateTime(2100, 12, 31);
            final initial = current.isBefore(first)
                ? first
                : current.isAfter(last)
                ? last
                : current;
            final date = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
              helpText: context.tr('选择日期'),
            );
            if (date != null && mounted) {
              fields['expire_date']!.text = date.toIso8601String().substring(
                0,
                10,
              );
            }
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wss = configBool(settings?['wss_report_enabled']);
    final nodes = {
      'custom_ct': '电信',
      'custom_cu': '联通',
      'custom_cm': '移动',
      'custom_bd': 'BGP',
      'node_1': 'Node 1',
      'node_2': 'Node 2',
      'node_3': 'Node 3',
      'node_4': 'Node 4',
    };
    const nodeHints = {
      'custom_ct': 'gd-ct-dualstack.ip.zstaticcdn.com',
      'custom_cu': 'gd-cu-dualstack.ip.zstaticcdn.com',
      'custom_cm': 'gd-cm-dualstack.ip.zstaticcdn.com',
      'custom_bd': 'ip.zstaticcdn.com',
    };
    return PopScope(
      canPop: !busy || !loaded,
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('编辑服务器'))),
        bottomNavigationBar: !loaded
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: Palette.of(context).paper,
                  border: Border(
                    top: BorderSide(color: Palette.of(context).line),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (error != null) Notice(error!, error: true),
                            FilledButton(
                              key: const Key('save-server-edit'),
                              onPressed: busy ? null : _save,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                minimumSize: const Size(0, 48),
                              ),
                              child: Text(
                                context.tr(
                                  busy
                                      ? '保存中'
                                      : needsLogin
                                      ? '重新登录并保存'
                                      : '保存',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        body: PageBody(
          child: !loaded
              ? Center(
                  child: busy
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(context.tr('正在加载服务器配置')),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.tr(error ?? '无法读取服务器配置')),
                            TextButton(
                              onPressed: _load,
                              child: Text(
                                context.tr(needsLogin ? '重新登录' : '重试'),
                              ),
                            ),
                          ],
                        ),
                )
              : Form(
                  key: form,
                  child: ListView(
                    key: const Key('server-edit-form'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    children: [
                      _heading('基本信息'),
                      _text('name', '服务器名称'),
                      _pair(
                        _text('server_group', '分组'),
                        _text('region', '地区', hint: context.tr('留空自动获取')),
                      ),
                      _text('tags', '标签', hint: context.tr('使用逗号分隔')),
                      _text(
                        'note',
                        '备注',
                        lines: 2,
                        hint: context.tr('内部备注，仅在管理端显示'),
                      ),
                      _heading('计费'),
                      _pair(
                        _select('currency', '货币', {
                          for (final currency in currencies) currency: currency,
                        }),
                        _text('price', '价格', numeric: true, hint: '40.00'),
                      ),
                      _pair(
                        _select('billing_cycle', '计费周期', const {
                          'month': '月',
                          'quarter': '季',
                          'half_year': '半年',
                          'year': '年',
                          'two_years': '两年',
                          'three_years': '三年',
                          'four_years': '四年',
                          'five_years': '五年',
                        }),
                        _dateField(),
                      ),
                      _heading('流量'),
                      _pair(
                        _text(
                          'traffic_limit',
                          '流量限制 (GB)',
                          numeric: true,
                          hint: 'e.g. 1000',
                        ),
                        _select('traffic_calc_type', '流量计算方式', const {
                          'total': '上传 + 下载',
                          'ul': '上传',
                          'dl': '下载',
                          'max': '上传／下载较大值',
                        }),
                      ),
                      _pair(
                        _select('reset_day', '流量重置日', {
                          for (var i = 0; i <= 31; i++) '$i': '$i',
                        }),
                        _text(
                          'traffic_alert_percent',
                          '流量告警阈值 (%)',
                          numeric: true,
                          hint: context.tr('留空跟随全局设置'),
                        ),
                      ),
                      _heading('采集与网络'),
                      _pair(
                        _select('collect_interval', '采集间隔（秒）', const {
                          '0': '0',
                          '1': '1',
                          '2': '2',
                          '5': '5',
                          '10': '10',
                        }),
                        _select('report_interval', '上报间隔（秒）', const {
                          '30': '30',
                          '60': '60',
                          '120': '120',
                          '180': '180',
                        }),
                      ),
                      _select('connection_mode', '连接模式', const {
                        'auto': '自动',
                        'http': 'HTTP',
                      }, enabled: wss),
                      if (wss && values['connection_mode'] == 'auto')
                        _select('wss_report_interval', 'WSS 上报间隔（秒）', const {
                          '1': '1',
                          '2': '2',
                          '3': '3',
                          '4': '4',
                          '5': '5',
                        }),
                      _select('ping_mode', '探测模式', const {
                        'tcp': 'TCP',
                        'icmp': 'ICMP (root)',
                      }),
                      _text('interface', '网络接口', hint: 'eth0'),
                      _pair(
                        _text(
                          'rx_correction',
                          '下载修正 (GB)',
                          numeric: true,
                          hint: '0',
                        ),
                        _text(
                          'tx_correction',
                          '上传修正 (GB)',
                          numeric: true,
                          hint: '0',
                        ),
                      ),
                      _heading('探测节点'),
                      for (final e in nodes.entries)
                        _text(
                          e.key,
                          '${settings?['${e.key}_name'] ?? e.value}',
                          hint:
                              (settings?[e.key] as String?)?.isNotEmpty == true
                              ? settings![e.key] as String
                              : nodeHints[e.key] ?? 'host[:port] / [IPv6]:port',
                        ),
                      _heading('选项'),
                      _switch('auto_renewal', '自动续费'),
                      _switch('auto_update', '自动更新', subtitle: '修改后需重新执行安装命令'),
                      _switch('is_hidden', '隐藏服务器'),
                      _switch('offline_notify_disabled', '关闭离线通知'),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
