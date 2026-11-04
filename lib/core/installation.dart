import 'models.dart';

String normalizeGitHubProxy(String input) {
  if (input.trim().isEmpty) return '';
  final value = input.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(value)) {
    throw const FormatException('请输入有效的 HTTP 或 HTTPS 代理地址');
  }
  return value;
}

enum InstallTarget {
  linux('Linux'),
  unix('OpenWrt / Alpine / FreeBSD'),
  mac('macOS'),
  windows('Windows'),
  docker('Docker');

  const InstallTarget(this.label);
  final String label;
}

class InstallParameters {
  const InstallParameters({required this.secret, this.userAgent = ''});
  final String secret;
  final String userAgent;

  String command(
    MonitorSite site,
    String serverId,
    InstallTarget target, {
    String githubProxy = '',
  }) {
    String posix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
    String powershell(String value) => "'${value.replaceAll("'", "''")}'";
    const source =
        'https://raw.githubusercontent.com/huilang-me/cfsm-agent/main';
    final proxy = target == InstallTarget.docker
        ? ''
        : normalizeGitHubProxy(githubProxy);
    final installSource = proxy.isEmpty ? source : '$proxy/$source';
    final url = '${site.baseUrl}/update';
    final ua = userAgent.trim();
    final customUa = ua.isNotEmpty && ua != 'cfsm';
    if (target == InstallTarget.docker) {
      return [
        'docker run -d --name cf-probe --restart=unless-stopped --network=host',
        '-v cf-probe-data:/data',
        '-e SERVER_ID=${posix(serverId)}',
        '-e SECRET=${posix(secret)}',
        '-e WORKER_URL=${posix(url)}',
        if (customUa) '-e UA=${posix(ua)}',
        'ghcr.io/huilang-me/cfsm-agent:latest',
      ].join(' ');
    }
    if (target == InstallTarget.windows) {
      return [
        r'$script = "$env:TEMP\install-cf-probe.ps1";',
        'Invoke-WebRequest -Uri ${powershell('$installSource/install.ps1')} -OutFile \$script -UseBasicParsing;',
        'PowerShell -ExecutionPolicy Bypass -File \$script install',
        if (proxy.isNotEmpty) '--install-ghproxy=${powershell(proxy)}',
        '-id=${powershell(serverId)}',
        '-secret=${powershell(secret)}',
        '-url=${powershell(url)}',
        "-auto_update='0'",
        if (customUa) '-ua=${powershell(ua)}',
      ].join(' ');
    }
    return [
      'curl -fsSL ${posix('$installSource/install.sh')} | sh -s -- install',
      if (proxy.isNotEmpty) '--install-ghproxy=${posix(proxy)}',
      '-id=${posix(serverId)}',
      '-secret=${posix(secret)}',
      '-url=${posix(url)}',
      '-auto_update=0',
      if (customUa) '-ua=${posix(ua)}',
    ].join(' ');
  }
}
