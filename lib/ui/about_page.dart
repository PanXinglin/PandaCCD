import 'package:flutter/material.dart';
import '../domain/app_info.dart';
import 'design_system.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于PandaCCD')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const BrandHeading(subtitle: '把日常，拍成旧时光。'),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 24),
                child: SelectableText(
                  '${AppInfo.versionLabel} · BUILD ${AppInfo.build}',
                  style: TextStyle(
                    fontSize: 11,
                    color: PandaDesign.muted,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SettingsSection(
                title: '一台口袋里的复古相机',
                children: [
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '用不同机型灵感、细腻颗粒和复古日期戳，记录平凡又值得珍藏的瞬间。\n\n内置风格是独立调优的创作效果，不代表相机品牌授权，也不是原机色彩的精确复刻。',
                      style: TextStyle(fontSize: 14, height: 1.8),
                    ),
                  ),
                ],
              ),
              const SettingsSection(
                title: '照片与隐私',
                children: [
                  ListTile(
                    leading: Icon(Icons.phone_android_outlined),
                    title: Text('照片留在你的设备'),
                    subtitle: Text(
                      '没有账号，不上传照片。人脸检测在设备上处理；仅开启Live声音时录音，不申请通知权限。',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.camera_alt_outlined),
                    title: Text('按需使用权限'),
                    subtitle: Text(
                      '拍照时使用相机，Live声音按需使用麦克风；保存时申请相册写入。删除联动按需申请照片访问权限。',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.link_outlined),
                    title: Text('删除联动可以关闭'),
                    subtitle: Text(
                      '在设置中关闭后，两边独立删除。权限不足或无法核对时保留本地作品；已关联作品的联动删除也会清理本地原图和编辑记录。',
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: '致谢',
                children: [
                  ListTile(
                    leading: const Icon(Icons.code_outlined),
                    title: const Text('开源许可证'),
                    subtitle: const Text('依赖组件、动态照片格式与快门声音来源'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppInfo.name,
                      applicationVersion: AppInfo.version,
                    ),
                  ),
                ],
              ),
              const Center(
                child: Text(
                  'PandaCCD / POCKET MEMORIES',
                  style: TextStyle(
                    fontSize: 10,
                    color: PandaDesign.muted,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
  );
}
