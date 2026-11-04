import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/installation.dart';
import 'support.dart';

void main() {
  test('GitHub 代理用于下载脚本和安装参数，Windows 亦使用，Docker 忽略', () {
    const parameters = InstallParameters(secret: 'secret');
    final linux = parameters.command(
      siteA,
      'id',
      InstallTarget.linux,
      githubProxy: ' https://proxy.example.com/gh/ ',
    );
    expect(
      linux,
      contains(
        "'https://proxy.example.com/gh/https://raw.githubusercontent.com/huilang-me/cfsm-agent/main/install.sh'",
      ),
    );
    expect(linux, contains("--install-ghproxy='https://proxy.example.com/gh'"));
    final windows = parameters.command(
      siteA,
      'id',
      InstallTarget.windows,
      githubProxy: 'https://ghfast.top/',
    );
    expect(
      windows,
      contains(
        'https://ghfast.top/https://raw.githubusercontent.com/huilang-me/cfsm-agent/main/install.ps1',
      ),
    );
    expect(windows, contains("--install-ghproxy='https://ghfast.top'"));
    final docker = parameters.command(
      siteA,
      'id',
      InstallTarget.docker,
      githubProxy: 'https://ghfast.top/',
    );
    expect(docker, isNot(contains('ghfast.top')));
    expect(docker, isNot(contains('--install-ghproxy')));
  });

  test('GitHub 代理直连和输入校验，不生成不完整或含凭据的代理地址', () {
    expect(normalizeGitHubProxy('  '), '');
    for (final value in [
      '/',
      'ghfast.top',
      'ftp://proxy.test',
      'https://u:p@proxy.test',
      'https://proxy.test?q=1',
      'https://proxy.test/#fragment',
      'https://proxy .test',
    ]) {
      expect(() => normalizeGitHubProxy(value), throwsFormatException);
    }
  });
  test('Unix 安装命令保留反代地址，自定义 UA 和含特殊字符的密钥作为完整参数', () async {
    final site = siteA.copyWith(baseUrl: 'https://a.example.com:8443/monitor');
    const secret = r"secret' with $dollar $(printf injected) `printf injected`";
    const ua = "my agent's UA";
    const parameters = InstallParameters(secret: secret, userAgent: ua);
    for (final target in [
      InstallTarget.linux,
      InstallTarget.unix,
      InstallTarget.mac,
    ]) {
      final command = parameters.command(site, 'server-id', target);
      expect(
        command,
        startsWith(
          "curl -fsSL 'https://raw.githubusercontent.com/huilang-me/cfsm-agent/main/install.sh'",
        ),
      );
      // Parse only the generated arguments. Never download or run the installer.
      final args = command.split('| sh -s -- ').last;
      final parsed = await Process.run('/bin/sh', [
        '-c',
        'set -- $args; printf \'%s\\n\' "\$@"',
      ]);
      expect(parsed.exitCode, 0);
      expect((parsed.stdout as String).trimRight().split('\n'), [
        'install',
        '-id=server-id',
        '-secret=$secret',
        '-url=https://a.example.com:8443/monitor/update',
        '-auto_update=0',
        '-ua=$ua',
      ]);
    }
  });

  test('Windows 使用 PowerShell 引号，默认 UA 不额外写入参数', () {
    final command = const InstallParameters(
      secret: "abc'def",
      userAgent: 'cfsm',
    ).command(siteA, 'server-id', InstallTarget.windows);
    expect(command, contains('install.ps1'));
    expect(command, contains("-secret='abc''def'"));
    expect(command, contains("-url='https://a.example.com/update'"));
    expect(command, contains("-auto_update='0'"));
    expect(command, isNot(contains('-ua=')));
  });

  test('Docker 使用数据卷、主机网络和所属服务器环境变量', () {
    final command = const InstallParameters(
      secret: 'secret',
      userAgent: 'custom ua',
    ).command(siteB, 'server-b', InstallTarget.docker);
    expect(command, startsWith('docker run -d --name cf-probe'));
    expect(command, contains('--network=host'));
    expect(command, contains('-v cf-probe-data:/data'));
    expect(command, contains("SERVER_ID='server-b'"));
    expect(command, contains("SECRET='secret'"));
    expect(command, contains("WORKER_URL='https://b.example.com/update'"));
    expect(command, contains("UA='custom ua'"));
    expect(command, endsWith('ghcr.io/huilang-me/cfsm-agent:latest'));
  });
}
