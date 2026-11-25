# -*- coding: utf-8 -*-
"""Create a portable source handoff, excluding local signing and capture tooling."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import re
root=Path(__file__).resolve().parents[1]
version,build=re.search(r'^version: ([^+]+)\+(\d+)',(root/'pubspec.yaml').read_text(),re.M).groups()
prefix=f'PandaCCD-{version}-source/'
out=root/'dist'/f'panda-ccd-{version}-ios-source.zip'
skip={'.DS_Store','.dart_tool','.gradle','.git','.idea','build','Pods','ephemeral','xcuserdata','.swiftpm','.build','.flutter-plugins-dependencies','Generated.xcconfig','flutter_export_environment.sh','local.properties','key.properties','store_capture'}
bad_ext={'.mobileprovision','.provisionprofile','.p12','.cer','.keystore','.jks','.xcuserstate','.pem','.key','.log'}
files=[root/p for p in ['pubspec.yaml','pubspec.lock','README.md','analysis_options.yaml','.metadata','.gitignore','docs/ARCHITECTURE.md','docs/THIRD_PARTY.md','docs/CCD_MODEL_STYLES.md']]
for name in ('lib','shaders','assets','packages','third_party','android','ios','test','integration_test','tool','.github'):
 files.extend(p for p in (root/name).rglob('*') if p.is_file() and not p.is_symlink() and not set(p.relative_to(root).parts)&skip and p.suffix not in bad_ext and p.name!='store_assets_capture_test.dart')
intro=f'''# PandaCCD iPhone 安装说明\n\n这是 {version}（build {build}）的 Flutter 工程源码。请在安装者自己的 Mac 上用 Codex 打开整个文件夹，连接并信任自己的 iPhone。使用自己的 Apple 账号在 Xcode 选择自动签名团队，并将 Bundle Identifier 改为该账号下唯一可用的 ID。\n\n可直接发给 Codex：\n> 请核对本机 Flutter、Xcode 与当前 iPhone 的兼容性，为此 Flutter 项目获取依赖，使用我自己的 Apple 账号自动签名，构建正常 lib/main.dart 的 Release 并安装到当前连接的 iPhone。不要导入其他人的证书或账号。需要我输入密码或信任开发者时请明确告知。\n\n该源码包包含本地 Flutter 插件修改和 Dart/GLSL 核心；不要只发送 ios 子目录。使用 Flutter 3.47.8 / Dart 3.13.7 开发，iOS 最低15。某些 Xcode 不支持旧 iOS 真机配对，需要先核对兼容版本。个人免费签名到期后需重新签名安装。\n\n本包排除了原开发者团队配置、签名证书、描述文件、本机路径与缓存。第三方依赖需通过 flutter pub get 获取。\n'''
with ZipFile(out,'w',ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(set(files)):
  rel=p.relative_to(root).as_posix()
  if rel=='ios/Runner.xcodeproj/project.pbxproj':
   z.writestr(prefix+rel,re.sub(r'^\s*DEVELOPMENT_TEAM = [A-Z0-9]+;\n','',p.read_text(),flags=re.M))
  else:z.write(p,prefix+rel)
 z.writestr(prefix+'开始安装.md',intro)
with ZipFile(out) as z:
 assert z.testzip() is None
 assert not any(set(Path(p).parts)&skip or Path(p).suffix in bad_ext for p in z.namelist())
 assert b'DEVELOPMENT_TEAM' not in z.read(prefix+'ios/Runner.xcodeproj/project.pbxproj')
 assert f'version: {version}+{build}'.encode() in z.read(prefix+'pubspec.yaml')
print(out,out.stat().st_size)
