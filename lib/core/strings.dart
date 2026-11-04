import 'package:flutter/widgets.dart';
import 'models.dart';

/// App-owned text only. Site names, tags, commands and custom probe names
/// are displayed as supplied by the site.
extension MonitorStrings on BuildContext {
  String tr(String source, [List<Object?> arguments = const []]) => AppStrings(
    Localizations.maybeLocaleOf(this)?.languageCode ?? 'zh',
  ).text(source, arguments);

  String serverName(Server server) =>
      server.text('name', '').isEmpty ? tr('未命名服务器') : server.name;

  String probeName(SiteConfig config, String key) {
    final name = config.probeName(key);
    final field =
        const {
          'ct': 'custom_ct_name',
          'cu': 'custom_cu_name',
          'cm': 'custom_cm_name',
          'bd': 'custom_bd_name',
        }[key] ??
        '${key}_name';
    return config.data[field] == null ? tr(name) : name;
  }
}

class AppStrings {
  const AppStrings(this.languageCode);
  final String languageCode;

  String text(String source, [List<Object?> arguments = const []]) {
    var template = source;
    if (languageCode == 'en') {
      template = english[source] ?? source;
      // Core formatters and API failures have no widget context. Translate
      // their known message shapes only when rendering them.
      if (template == source && arguments.isEmpty) {
        for (final entry in _formattedMessages.entries) {
          final match = entry.key.firstMatch(source);
          if (match != null) {
            return text(entry.value, [
              for (var i = 1; i <= match.groupCount; i++) match.group(i),
            ]);
          }
        }
      }
    }
    return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? '${arguments[index]}' : match[0]!;
    });
  }

  static final _formattedMessages = <RegExp, String>{
    RegExp(r'^站点请求失败（(\d+)），请稍后重试$'): '站点请求失败（{0}），请稍后重试',
    RegExp(r'^(\d+) 天 (\d+) 小时$'): '{0} 天 {1} 小时',
    RegExp(r'^(\d+) 天$'): '{0} 天',
    RegExp(r'^(\d+) 小时$'): '{0} 小时',
    RegExp(r'^已到期 (\d+) 天$'): '已到期 {0} 天',
    RegExp(r'^(\d+) 天后到期$'): '{0} 天后到期',
  };

  static const english = <String, String>{
    '\n{0} 在线 / {1} 台（快照）': '\n{0} online / {1} servers (snapshot)',
    '1 分钟': '1 minute',
    '15 分钟': '15 minutes',
    '5 分钟': '5 minutes',
    'CPU 使用率': 'CPU usage',
    'CPU 型号': 'CPU model',
    'CPU 核心': 'CPU cores',
    'CPU 核心数': 'CPU cores',
    'Default（可选）': 'Default (optional)',
    'Docker 镜像不使用 GitHub 代理': 'Docker images do not use the GitHub proxy',
    'GPU 使用率': 'GPU usage',
    'GPU 功耗': 'GPU power',
    'GPU 型号': 'GPU model',
    'GPU 时钟': 'GPU clock',
    'GPU 显存': 'GPU memory',
    'GitHub 代理': 'GitHub proxy',
    '{0} · {1} · {2}% 丢包': '{0} · {1} · {2}% packet loss',
    '{0} · {1} 个采样点': '{0} · {1} samples',
    '{0} · 运行 {1}': '{0} · Up {1}',
    '{0} 个站点，各自连接与管理': '{0} sites, managed independently',
    '{0} 台服务器': '{0} servers',
    '{0} 在线 / {1} 台（快照）': '{0} online / {1} servers (snapshot)',
    '{0} 在线 / {1} 离线': '{0} online / {1} offline',
    '{0} 核': '{0} cores',
    '{0}% 丢包': '{0}% packet loss',
    '{0}ms 延迟': '{0}ms latency',
    '{0}历史曲线，{1}个采样点，点击或拖动查看数值':
        '{0} history chart, {1} samples. Tap or drag to inspect values.',
    '上传': 'Upload',
    '上传 + 下载': 'Upload + download',
    '上传／下载较大值': 'Higher of upload / download',
    '上次连接成功': 'Last connection successful',
    '下载': 'Download',
    '不可用': 'Unavailable',
    '不限量': 'Unlimited',
    '丢包率': 'Packet loss',
    '个': 'count',
    '仅上传': 'Upload only',
    '仅下载': 'Download only',
    '从本机删除': 'Remove from device',
    '价格': 'Price',
    '使用该站点现有的管理员账号': 'Use the site\'s existing administrator account',
    '例如：主监控站': 'e.g. Main monitor',
    '例如：香港服务器': 'e.g. Hong Kong server',
    '保存布局失败，请重试': 'Could not save the layout. Please try again.',
    '保存默认主页失败，请重试': 'Could not save the default site. Please try again.',
    '全部 {0}': 'All {0}',
    '全部站点': 'All sites',
    '公开站点': 'Public site',
    '内存': 'Memory',
    '内存使用率': 'Memory usage',
    '内存容量': 'Memory capacity',
    '内核版本': 'Kernel version',
    '写 IOPS': 'Write IOPS',
    '写入': 'Write',
    '分组': 'Group',
    '切换列表布局': 'Switch to list layout',
    '切换卡片布局': 'Switch to card layout',
    '创建服务器': 'Create server',
    '删除': 'Delete',
    '删除失败，请重试': 'Could not delete. Please try again.',
    '删除服务器？': 'Delete server?',
    '删除本机站点？': 'Remove site from device?',
    '到期 {0}': 'Expiry: {0}',
    '到期时间': 'Expires',
    '剩余价值': 'Remaining value',
    '历史时间范围': 'History range',
    '取消': 'Cancel',
    '取消默认主页站点': 'Clear default home site',
    '启动时间': 'Boot time',
    '在 Web 后台添加服务器后，下拉刷新即可查看。':
        'Add servers in the web admin, then pull to refresh.',
    '在线': 'Online',
    '复制失败，可长按命令复制': 'Could not copy. Touch and hold the command to copy it.',
    '复制安装命令': 'Copy install command',
    '安装命令': 'Install command',
    '安装命令已复制': 'Install command copied',
    '安装探针 - {0}': 'Install agent - {0}',
    '实时连接已达到站点设置的时长。': 'The live connection reached the site\'s time limit.',
    '实时连接暂不可用 · 数据更新于 {0}，可下拉刷新':
        'Live connection unavailable · Updated {0}. Pull to refresh.',
    '实时连接需要重新登录。': 'Sign in again to restore the live connection.',
    '实时速度': 'Live speed',
    '密码': 'Password',
    '密码不保存，登录凭证按站点独立存储':
        'Passwords are not saved. Sign-in tokens are stored separately for each site.',
    '将从当前站点删除“{0}”及其监控数据。服务器上的 Agent 不会自动卸载。':
        'Delete “{0}” and its monitoring data from this site? The agent on the server will remain installed.',
    '将移除“{0}”的本机记录和登录凭证，服务器端数据不受影响。':
        'Remove “{0}” and its sign-in token from this device? Server data will remain unchanged.',
    '已取消默认主页站点': 'Default home site cleared',
    '已显示当前站点全部服务器': 'All servers for this site are shown',
    '已设为默认主页站点': 'Set as default home site',
    '已识别 CF Server Monitor · {0}': 'CF Server Monitor detected · {0}',
    '当前服务器没有启用的线路探测数据。': 'No enabled network probes for this server.',
    '当前版本不支持 Turnstile 人机验证。公开站点若仅开启登录验证，仍可匿名查看。':
        'Turnstile verification is not supported. Public sites with sign-in verification only can still be viewed anonymously.',
    '待连接': 'Not connected',
    '总流量': 'Total traffic',
    '总磁盘 / 内存': 'Total disk / memory',
    '我的站点': 'My sites',
    '操作系统 / 架构': 'OS / architecture',
    '新增服务器': 'Add server',
    '显示密码': 'Show password',
    '暂时无法读取服务器': 'Unable to load servers',
    '最后上报 {0}': 'Last report {0}',
    '最后更新': 'Last updated',
    '月流量': 'Monthly traffic',
    '月流量限制': 'Monthly traffic limit',
    '服务器': 'Servers',
    '服务器名称': 'Server name',
    '服务器名称最多 100 个字符': 'Server names can contain up to 100 characters',
    '服务器已删除': 'Server deleted',
    '未设置': 'Not set',
    '标签': 'Tags',
    '检查并连接': 'Check and connect',
    '正在删除服务器': 'Deleting server',
    '正在加载服务器…': 'Loading servers…',
    '此地区暂无服务器': 'No servers in this region',
    '此时段暂无可用数据': 'No data for this period',
    '此站点暂无服务器': 'No servers at this site',
    '此站点超过 500 台服务器，首期仅订阅前 500 台；其余指标通过刷新更新。':
        'This site has more than 500 servers. Live updates cover the first 500; refresh to update the rest.',
    '流量计算方式': 'Traffic calculation',
    '添加你的 CF Server Monitor': 'Connect your CF Server Monitor',
    '添加站点': 'Add site',
    '添加第一个站点': 'Add your first site',
    '用户名': 'Username',
    '登录凭证仅保存在本机安全存储中': 'Sign-in tokens are stored securely on this device only',
    '登录并连接': 'Sign in and connect',
    '登录此站点': 'Sign in to this site',
    '登录站点': 'Sign in',
    '目标系统': 'Target system',
    '直连（不使用代理）': 'Direct (no proxy)',
    '直连，或输入代理地址': 'Direct, or enter a proxy URL',
    '磁盘': 'Disk',
    '磁盘 IO · 利用率': 'Disk I/O · Utilization',
    '磁盘 IO · 吞吐': 'Disk I/O · Throughput',
    '磁盘 IO · 操作数': 'Disk I/O · Operations',
    '磁盘 IO · 等待': 'Disk I/O · Wait',
    '磁盘使用率': 'Disk usage',
    '离线': 'Offline',
    '私有站点': 'Private site',
    '站点名称': 'Site name',
    '站点地址': 'Site URL',
    '系统信息': 'System',
    '线路延迟': 'Network latency',
    '继续连接': 'Reconnect',
    '编辑{0}': 'Edit {0}',
    '编辑站点': 'Edit site',
    '网络质量': 'Network',
    '网络速度': 'Network speed',
    '设为默认主页站点': 'Set as default home site',
    '请输入服务器名称': 'Enter a server name',
    '请输入用户名和密码': 'Enter your username and password',
    '请输入站点名称': 'Enter a site name',
    '读 IOPS': 'Read IOPS',
    '读取': 'Read',
    '负载': 'Load',
    '负载 {0}': 'Load {0}',
    '负载监控': 'Load average',
    '资源指标': 'Resources',
    '超时': 'Timeout',
    '输入用户名': 'Enter username',
    '输入站点密码': 'Enter site password',
    '运行时间': 'Uptime',
    '返回服务器列表': 'Back to servers',
    '还没有添加站点': 'No sites yet',
    '进入站点': 'Open site',
    '进程': 'Processes',
    '进程数': 'Process count',
    '连接你的 CF Server Monitor，\n随时查看服务器运行状态。':
        'Connect your CF Server Monitor\nto check your servers anytime.',
    '连接失败': 'Connection failed',
    '连接或保存失败，请重试': 'Could not connect or save. Please try again.',
    '连接数': 'Connections',
    '连接新站点': 'Connect a new site',
    '选择 GitHub 代理': 'Choose a GitHub proxy',
    '选择“全部”查看其他地区。': 'Select “All” to view other regions.',
    '重新登录': 'Sign in again',
    '重新登录并创建': 'Sign in again and create',
    '重新登录并获取安装命令': 'Sign in again to get the command',
    '重新获取安装命令': 'Retry fetching command',
    '重新读取': 'Reload',
    '重新连接站点': 'Reconnect to site',
    '重试': 'Retry',
    '隐藏密码': 'Hide password',
    '需要登录': 'Sign-in required',
    '需要登录？输入账号密码': 'Need to sign in? Enter your credentials',
    '验证暂不支持': 'Verification not supported',
    '默认主页站点': 'Default home site',
    '设置': 'Settings',
    '关于': 'About',
    '当前版本 {0}': 'Current version {0}',
    '无法读取版本信息': 'Could not read version information',
    '正在读取版本信息…': 'Reading version information…',
    '检查更新': 'Check for updates',
    '正在检查更新…': 'Checking for updates…',
    '发现新版本 {0}': 'New version {0} available',
    '前往 App Store 更新 CF Monitor。': 'Update CF Monitor in the App Store.',
    '前往 GitHub Release 选择适合设备的 APK，下载后安装更新。':
        'Choose the APK for your device on GitHub Releases, then download and install the update.',
    '前往更新': 'Get update',
    '当前已是最新版本': 'You are up to date',
    '当前地区的 App Store 暂未上架，请稍后重试':
        'Not available in your App Store region yet. Please try again later.',
    '暂无可用的 Android 正式版本，请稍后重试':
        'No Android release is available yet. Please try again later.',
    '仅支持在 Android 或 iOS 上检查更新':
        'Update checks are supported on Android and iOS.',
    '检查更新失败，请检查网络后重试':
        'Could not check for updates. Check your network and try again.',
    '作者的其他项目': 'More from the author',
    '服务器 SSH 终端与管理面板': 'SSH terminal and server management panel',
    '无法打开链接，请稍后重试': 'Could not open the link. Please try again later.',
    '语言': 'Language',
    '主题': 'Theme',
    '跟随系统': 'System',
    '明亮': 'Light',
    '暗黑': 'Dark',
    '保存设置失败，请重试': 'Could not save settings. Please try again.',
    '无法读取设置，请重试': 'Could not load settings. Please try again.',
    '全部': 'All',
    '正在连接': 'Connecting',
    '暂无服务器': 'No servers',
    '实时连接': 'Live connection',
    '实时连接已到时': 'Live connection time limit reached',
    '实时断开 · 自动重连': 'Disconnected · Reconnecting',
    '连接已暂停': 'Connection paused',
    '参考汇率': 'Reference rates',
    '缓存汇率': 'Cached rates',
    '最新汇率': 'Latest rates',
    '无法读取本机站点，请重试': 'Could not load saved sites. Please try again.',
    '请输入有效的 HTTP 或 HTTPS 代理地址': 'Enter a valid HTTP or HTTPS proxy URL',
    '请输入完整站点地址，例如 https://monitor.example.com':
        'Enter a full site URL, e.g. https://monitor.example.com',
    '请使用 HTTPS 站点地址': 'Use an HTTPS site URL',
    '登录凭证未通过站点校验，请重试':
        'The site rejected your sign-in token. Please try again.',
    '请重新登录以获取安装命令': 'Sign in again to get the install command',
    '操作失败，请检查网络后重试': 'The operation failed. Check your network and try again.',
    '服务器名称不符合站点要求，请修改后重试':
        'The site rejected the server name. Change it and try again.',
    '登录已失效或当前数据需要登录，请重新登录':
        'Your session expired or this data requires sign-in. Please sign in again.',
    '请求被站点验证或防护拦截，当前版本不支持人机验证':
        'The request was blocked by site protection. Human verification is not supported.',
    '未找到站点接口或服务器，服务器可能已被删除':
        'Site endpoint or server not found. The server may have been deleted.',
    '该服务器尚未分配历史分区，请在 Web 后台处理':
        'This server has no history partition. Configure it in the web admin.',
    '站点数据库需要维护，请在 Web 后台处理':
        'The site database needs maintenance in the web admin.',
    '实时服务暂不可用，请稍后重试':
        'The live service is unavailable. Please try again later.',
    '站点发生重定向，请填写最终的 HTTPS 地址':
        'The site redirected the request. Enter the final HTTPS URL.',
    '站点请求失败（{0}），请稍后重试': 'Site request failed ({0}). Please try again later.',
    '站点未返回有效的监控数据，请检查地址与版本':
        'The site returned invalid monitoring data. Check its URL and version.',
    '无法连接站点，请检查地址、证书与网络':
        'Cannot connect. Check the site URL, certificate and network.',
    '此地址未识别为 CF Server Monitor 站点':
        'This URL was not recognized as a CF Server Monitor site',
    '站点未返回登录凭证': 'The site did not return a sign-in token',
    '该站点启用了全局人机验证，当前版本暂不支持连接':
        'This site requires global human verification, which is not supported.',
    '该站点启用了登录验证，当前版本暂不支持登录':
        'This site requires sign-in verification, which is not supported.',
    '服务器列表格式不受支持': 'Unsupported server list format',
    '请先登录此站点': 'Sign in to this site first',
    '新增服务器未成功，请刷新列表确认后重试':
        'Could not create the server. Refresh the list to check before trying again.',
    '删除服务器未成功，请刷新列表确认后重试':
        'Could not delete the server. Refresh the list to check before trying again.',
    '无法获取安装密钥，请重试获取安装命令':
        'Could not fetch the install key. Retry fetching the command.',
    '服务器详情格式不受支持': 'Unsupported server details format',
    '不支持的历史时间范围': 'Unsupported history range',
    '查看超过 24 小时的历史数据需要登录': 'Sign in to view more than 24 hours of history',
    '历史数据格式不受支持': 'Unsupported history data format',
    '请重新登录': 'Please sign in again',
    '未命名服务器': 'Unnamed server',
    '免费': 'Free',
    '长期有效': 'No expiry',
    '今日到期': 'Expires today',
    '已到期 {0} 天': 'Expired {0} days ago',
    '{0} 天后到期': 'Expires in {0} days',
    '{0} 天 {1} 小时': '{0}d {1}h',
    '{0} 天': '{0}d',
    '{0} 小时': '{0}h',
    '月': 'month',
    '季': 'quarter',
    '半年': '6 months',
    '年': 'year',
    '两年': '2 years',
    '三年': '3 years',
    '四年': '4 years',
    '五年': '5 years',
    '电信': 'Telecom',
    '联通': 'Unicom',
    '移动': 'Mobile',
  };
}
