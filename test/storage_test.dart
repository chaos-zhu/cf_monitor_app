import 'package:flutter_test/flutter_test.dart';
import 'package:cf_monitor_app/core/models.dart';
import 'package:cf_monitor_app/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support.dart';

void main() {
  test('服务器布局默认卡片，设备持久化列表选择且可切回', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SiteController(DeviceSiteStorage());
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.compactLayout, isFalse);
    await controller.setCompactLayout(true);
    final reloaded = SiteController(DeviceSiteStorage());
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.compactLayout, isTrue);
    await reloaded.setCompactLayout(false);
    expect(await DeviceSiteStorage().readCompactLayout(), isFalse);
  });

  test('多个站点持久化、凭据隔离及并发保存不丢失', () async {
    final storage = MemoryStorage();
    final controller = SiteController(storage);
    addTearDown(controller.dispose);
    await controller.load();
    await Future.wait([
      controller.save(siteA, token: jwt(), replaceToken: true),
      controller.save(siteB, token: jwt(), replaceToken: true),
    ]);
    expect(controller.sites.length, 2);
    expect(storage.tokens.keys, containsAll(['a', 'b']));
    final reloaded = SiteController(storage);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.sites.length, 2);
  });
  test('只改名称保留 Token，修改地址清除旧凭据', () async {
    final storage = MemoryStorage([siteA]);
    final controller = SiteController(storage);
    addTearDown(controller.dispose);
    await controller.load();
    storage.tokens['a'] = jwt();
    await controller.save(siteA.copyWith(name: '新名称'));
    expect(await controller.token('a'), isNotNull);
    await controller.save(siteA.copyWith(baseUrl: 'https://new.example.com'));
    expect(await controller.token('a'), isNull);
  });
  test('过期或损坏 Token 仅清理所属站点，删除也独立生效', () async {
    final storage = MemoryStorage([siteA, siteB]);
    final controller = SiteController(storage);
    addTearDown(controller.dispose);
    await controller.load();
    storage.tokens['a'] = jwt(expired: true);
    storage.tokens['b'] = jwt();
    expect(await controller.token('a'), isNull);
    expect(await controller.token('b'), isNotNull);
    storage.tokens['a'] = 'malformed';
    expect(await controller.token('a'), isNull);
    await controller.remove(siteA);
    expect(controller.sites.single.id, 'b');
    expect(storage.tokens['b'], isNotNull);
  });
  test('序列化不包含 Token 或密码', () {
    final encoded = siteA
        .copyWith(status: SiteStatus.connected, lastVisit: DateTime(2026))
        .toJson();
    expect(encoded.keys, isNot(contains('token')));
    expect(encoded.keys, isNot(contains('password')));
    expect(MonitorSite.fromJson(encoded).baseUrl, siteA.baseUrl);
  });

  test('默认主页保存到设备偏好，重新创建存储后保留且可清除', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = DeviceSiteStorage();
    expect(await storage.readDefaultSiteId(), isNull);
    await storage.save([siteA, siteB]);
    await storage.writeDefaultSiteId('b');
    final reloaded = SiteController(DeviceSiteStorage());
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.defaultSite?.id, 'b');
    await reloaded.setDefaultSite(null);
    expect(await DeviceSiteStorage().readDefaultSiteId(), isNull);
  });

  test('默认站点唯一，编辑后保留，删除默认站点清除选择', () async {
    final storage = MemoryStorage([siteA, siteB]);
    final controller = SiteController(storage);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setDefaultSite('a');
    await controller.setDefaultSite('b');
    expect(controller.defaultSiteId, 'b');
    await controller.save(siteB.copyWith(name: '新名称'));
    expect(controller.defaultSite?.name, '新名称');
    final reloaded = SiteController(storage);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.defaultSiteId, 'b');
    await controller.remove(siteA);
    expect(controller.defaultSiteId, 'b');
    await controller.remove(siteB);
    expect(controller.defaultSite, isNull);
    expect(storage.defaultSiteId, isNull);
  });

  test('失效默认 ID 不作为主页，未知站点不可设为默认', () async {
    final storage = MemoryStorage([siteA])..defaultSiteId = 'deleted';
    final controller = SiteController(storage);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.defaultSiteId, isNull);
    expect(controller.defaultSite, isNull);
    await expectLater(controller.setDefaultSite('unknown'), throwsStateError);
    expect(controller.defaultSiteId, isNull);
    await controller.setDefaultSite('a');
    expect(controller.defaultSite?.id, 'a');
  });
}
