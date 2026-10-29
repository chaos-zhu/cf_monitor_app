import 'dart:math' as math;
import 'models.dart';

String bytes(num? value, {bool speed = false}) {
  if (value == null || !value.isFinite) return '—';
  final suffix = speed ? '/s' : '';
  if (value == 0) return '0 B$suffix';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final i = (math.log(value.abs()) / math.log(1024)).floor().clamp(
    0,
    units.length - 1,
  );
  final n = value / math.pow(1024, i);
  return '${n.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}$suffix';
}

String decimal(num? value, [int digits = 2]) =>
    value == null || !value.isFinite ? '—' : value.toStringAsFixed(digits);
String percent(num? value) => value == null ? '—' : '${decimal(value)}%';
String clock(DateTime? date) => date == null
    ? '—'
    : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
String dateTime(DateTime? date) => date == null
    ? '—'
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${clock(date)}';
String uptime(Object? raw, [DateTime? now]) {
  final boot = metricTime(raw);
  if (boot == null) return '—';
  final delta = (now ?? DateTime.now()).difference(boot);
  if (delta.isNegative) return '—';
  return '${delta.inDays} 天 ${delta.inHours % 24} 小时';
}

String expiry(Object? value, [DateTime? now]) {
  if (value == null || value == '') return '未设置';
  final time = metricTime(value);
  if (time == null) return '$value';
  final days = time.difference(now ?? DateTime.now()).inDays;
  if (days > 36500) return '长期有效';
  return days < 0
      ? '已到期 ${days.abs()} 天'
      : days == 0
      ? '今日到期'
      : '$days 天后到期';
}

String flag(String region) {
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(region) || region == 'XX') return '🏳️';
  return String.fromCharCodes(region.codeUnits.map((v) => v + 127397));
}

const defaultExchangeRates = <String, double>{
  'AED': .5435,
  'AUD': .20941,
  'BDT': 18.02,
  'BRL': .74734,
  'CAD': .20691,
  'CHF': .11746,
  'CNY': 1,
  'CZK': 3.0787,
  'DKK': .95296,
  'EGP': 7.15,
  'EUR': .1275,
  'GBP': .11027,
  'GTQ': 1.14,
  'HKD': 1.1594,
  'HUF': 44.688,
  'IDR': 2622.37,
  'ILS': .43085,
  'INR': 14.0178,
  'ISK': 18.4626,
  'JPY': 23.707,
  'KRW': 224.11,
  'KZT': 64,
  'LKR': 44.4,
  'MXN': 2.5472,
  'MYR': .59945,
  'MNT': 530,
  'NGN': 225.6,
  'NOK': 1.4096,
  'NZD': .2535,
  'PHP': 8.9288,
  'PKR': 41.5,
  'PLN': .54138,
  'RON': .66769,
  'RUB': 11.9,
  'SAR': .555,
  'SEK': 1.3895,
  'SGD': .18975,
  'THB': 4.8172,
  'TRY': 6.849,
  'UAH': 3.6,
  'USD': .14799,
  'VND': 3500,
  'ZAR': 2.3995,
};
const currencyAliases = <String, String>{
  '¥': 'CNY',
  '￥': 'CNY',
  'RMB': 'CNY',
  r'$': 'USD',
  r'US$': 'USD',
  '€': 'EUR',
  '£': 'GBP',
  '¥JPY': 'JPY',
  r'HK$': 'HKD',
  r'A$': 'AUD',
  r'C$': 'CAD',
  r'S$': 'SGD',
  r'NZ$': 'NZD',
  '₣': 'CHF',
  '₩': 'KRW',
  '₹': 'INR',
  '฿': 'THB',
  '₫': 'VND',
  '₱': 'PHP',
  'Rp': 'IDR',
  'RM': 'MYR',
  '₺': 'TRY',
  '₪': 'ILS',
  '৳': 'BDT',
  '₨': 'PKR',
  'LKR': 'LKR',
  '₮': 'MNT',
  '₽': 'RUB',
  r'R$': 'BRL',
  'kr': 'SEK',
  'zł': 'PLN',
  '₴': 'UAH',
  '₸': 'KZT',
  'R': 'ZAR',
  '₦': 'NGN',
  'د.إ': 'AED',
  '﷼': 'SAR',
  'Q': 'GTQ',
};
const cycleDays = <String, int>{
  'month': 30,
  'quarter': 90,
  'half_year': 180,
  'year': 365,
  'two_years': 730,
  'three_years': 1095,
  'four_years': 1460,
  'five_years': 1825,
};
const cycleLabels = <String, String>{
  'month': '月',
  'quarter': '季',
  'half_year': '半年',
  'year': '年',
  'two_years': '两年',
  'three_years': '三年',
  'four_years': '四年',
  'five_years': '五年',
};
String billingCycle(Server server) {
  final price = server.text('price', '');
  final tail = price.split('/').last.trim();
  const aliases = {
    '月': 'month',
    '季': 'quarter',
    '季度': 'quarter',
    '半年': 'half_year',
    '年': 'year',
    '两年': 'two_years',
    '2年': 'two_years',
    '三年': 'three_years',
    '3年': 'three_years',
    '四年': 'four_years',
    '五年': 'five_years',
    'monthly': 'month',
    'quarterly': 'quarter',
    'yearly': 'year',
    'annual': 'year',
  };
  final fromPrice = price.contains('/')
      ? aliases[tail] ?? (cycleDays.containsKey(tail) ? tail : null)
      : null;
  final raw = fromPrice ?? server.text('billing_cycle', 'month');
  return aliases[raw] ?? (cycleDays.containsKey(raw) ? raw : 'month');
}

double priceAmount(Server server) {
  final raw = server.text('price', '').trim();
  if (['免费', 'free', '白嫖'].any((v) => raw.toLowerCase().contains(v))) return 0;
  return double.tryParse(
        RegExp(r'\d+(?:\.\d+)?').firstMatch(raw)?.group(0) ?? '',
      ) ??
      0;
}

String priceCurrency(Server server) {
  final configured = server.text('currency', '');
  if (configured.isNotEmpty) {
    return currencyAliases[configured] ??
        (defaultExchangeRates.containsKey(configured.toUpperCase())
            ? configured.toUpperCase()
            : 'CNY');
  }
  final raw = server.text('price', '').trim();
  for (final code in defaultExchangeRates.keys) {
    if (raw.toUpperCase().startsWith(code)) return code;
  }
  final keys = currencyAliases.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (raw.startsWith(key)) return currencyAliases[key]!;
  }
  return 'CNY';
}

String billingPrice(Server server) {
  final raw = server.text('price', '');
  if (raw.isEmpty) return '—';
  if (priceAmount(server) == 0) return '免费';
  return '${priceCurrency(server)} ${decimal(priceAmount(server))} / ${cycleLabels[billingCycle(server)]}';
}

double remainingValue(
  Iterable<Server> servers,
  Map<String, double> rates, [
  DateTime? time,
]) {
  final now = time ?? DateTime.now();
  double total = 0;
  for (final s in servers) {
    if (s.tags.contains('白嫖中')) continue;
    final rate =
        rates[priceCurrency(s)] ?? defaultExchangeRates[priceCurrency(s)] ?? 1;
    final price = priceAmount(s) / rate;
    final expires = metricTime(s.data['expire_date'] ?? s.data['expired_at']);
    if (expires == null) continue;
    final days = expires.difference(now).inMilliseconds / 86400000;
    if (days <= 0) continue;
    total += days > 36500
        ? price
        : price * days / (cycleDays[billingCycle(s)] ?? 30);
  }
  return total;
}
