# iOS 迁移 0.13.0（build29）

状态：iPhone Duo 模拟器媒体链路测试通过；iPhone 14 Pro 已安装并启动签名后的 Release 0.13.0（29）。实拍验收待完成。

## 保持一致的体验

沿用 Android 0.12.8 的 Flutter 页面、预设、LUT、GLSL、美颜参数、画幅、水印和本地照片结构。相册可左右翻页、批量选择；详情页分享、编辑、删除在顶部，图片占用剩余空间。默认拍后编辑，设置中可选直接保存；Live 后处理队列沿用现有实现。

最低 iOS 15.0，Impeller/Metal。支持 iPhone 安全区域、iPad 可调整窗口；不按未经确认的机型名称判断屏幕形态。保留原有奶油白/绿色视觉。

## 苹果端差异处理

- 官方 camera_avfoundation 0.10.3+1 作为本地依赖保留。取景/分析/视频固定为竖向像素，Flutter 按窗口显示；静态照片独立跟随快门握持方向，录制时也能更新照片方向。详见第三方目录的 PANDA_PATCH.md。
- 前置原始视频有镜像。每段 Live 保存镜像标志，先还原镜像再旋转，处理后保留的重编辑视频不再重复镜像。旧记录没有此字段时按原逻辑读取。
- Vision 接收与取景一致的方向，在识别人脸前还原前置镜像；瘦脸/磨皮仍由共用 GLSL 执行。
- PHPicker 通过 Flutter 官方 image_picker 打开系统照片，不再用 Files 代替 Photos。只取用户选择的照片，不申请全库元数据；选取 Live 作为输入时仍按静态封面编辑，直接拍摄 Live 是完整支持目标。
- 系统 Photos 保存使用现有本地媒体桥中的 PHAssetCreationRequest，直接写入生成好的 JPEG/MOV，保留同一内容标识、封面时刻和音轨。仅添加权限下从创建请求返回 ID，不依赖再次读取照片，不二次改写配对元数据。查阅和删除继续使用 photo_manager，有限权限下不把不可访问照片当作已删除。
- Apple 视频编码接收标记为 sRGB 的滤镜帧，输出带标准 SDR 色彩描述的 H.264；读帧时转换回 sRGB。iPhone Duo 模拟器实测修复了 Live 动态片段比静态封面偏亮的问题。
- iPhone 使用 AVFoundation 系统快门声。不开第二个播放器，避免重复响声或播放器结束后停用录音会话；静音与地区限制由设备决定，设置页如实显示该区别。Android 自定义快门声保持原样。
- 音量按键插件保留已有录音类别，防止开启音量快门时把有声 Live 切成 ambient。KVO 音量监听仍需要真机检查蓝牙路由、音量上下边界和长按。
- iOS 应用内分享静态照片/动态视频；保留完整 Apple Live 的分享沿用系统 Photos 入口，不能把 JPEG 和 MOV 两个附件宣称为完整 Live 分享。

没有新增平台滤镜、云端人脸服务、付费 SDK 或账号体系。

## 已执行的检查

2026-11-08：

- 78 项 Dart/Widget 测试通过，包含四方向前后镜头几何、Live 镜像持久化、GPU 镜像旋转、相册与美颜界面回归。
- 导入选择器变更后，取消恢复相机及 iOS 几何 6 项定向测试通过。
- Flutter analyze 通过；Info.plist 和 Xcode 项目格式检查通过。
- 真实 Apple AVFoundation/Vision 辅助源码在 Mac 编译执行通过：四向镜像像素、视频编码、音轨保留、JPEG/MOV 标识一致、定时封面元数据 0.75 秒、人脸轮廓检测。
- 安装并初始化苹果正式版 Xcode 27.2（27B52）。iOS 和模拟器 SDK 均为 27.2。使用正常 `lib/main.dart` 入口生成 `build/ios/iphonesimulator/Runner.app`；验证 App 签名、版本 0.13.0（29）、模拟器目标和 iOS 15.0 最低版本。
- 同一入口的设备 Release 未签名构建通过，生成 `build/ios/iphoneos/Runner.app`。验证为 iPhoneOS arm64、0.13.0（29）、最低 iOS 15.0，包内包含 CCD shader 和 LUT。编译记录见 [ios-build-0130.txt](qa/ios-build-0130.txt)。没有生成可安装 IPA。

2026-11-09：iPhone Duo（iOS 27.2）模拟器运行 `integration_test/ios_pipeline_test.dart` 通过。覆盖 Metal 滤镜、Apple 编解码、前置镜像与四方向、24 个动态帧与封面的色彩对照及 Apple Live 文件生成。修正色彩转换后，重新运行 Mac Apple 媒体检查和 Flutter 静态分析，均通过。模拟器测试使用合成图案，摄像头实拍和系统相册授权仍需真机确认。

## 可重复执行

`tool/ios_workflow.py` 使用本机 Flutter 和完整 Xcode，不写凭据，不修改系统全局 Xcode 路径。原生构建子进程通过临时工具路径调用同一个 Xcode 的 SDK，避免误用系统默认的命令行工具。

```sh
python3 tool/ios_workflow.py check
python3 tool/ios_workflow.py core
python3 tool/ios_workflow.py simulator
python3 tool/ios_workflow.py unsigned
python3 tool/ios_workflow.py test --device <iOS设备ID>
python3 tool/ios_workflow.py device --device <iPhone设备ID>
```

用户选择连接 iPhone 到 Mac 本机测试。已登录 Xcode，使用实际 Personal Team 完成本机自动签名。iPhone 14 Pro 的开发者模式已启用；安装列表核对版本为 0.13.0（29），签名及设备授权匹配。用户在“设置 → 通用 → VPN 与设备管理”信任开发签名后确认可以打开，`devicectl` 复验启动成功。该测试签名于 2026-11-16 到期，可用同一团队重新签名安装。Release 启动无需连接调试器。

## iPhone 验收，均待执行

- [x] iPhone 14 Pro 正常入口安装及启动。
- [ ] iPhone 小屏/刘海/灵动岛及 iPad 窗口布局，Metal 显示实际 CCD 效果。
- [ ] 前后镜头、四种握持方向、Live 开关：取景不拉伸、不颠倒；封面与动态方向、色彩一致。
- [ ] 磨皮、提亮、下颌调节可见且不挡取景；前置镜像下轮廓跟踪正确。
- [ ] 常开闪光、自动、关闭；音量上下键；系统快门声；连续拍摄及后台队列。
- [ ] 仅添加、有限访问、拒绝相册权限：本地成片保留，系统 Live 可播放；确认删除只影响用户选中的关联照片。
- [ ] Live 带声/无声/麦克风拒绝；关 Live 后无持续麦克风占用；切后台再返回、锁屏、电话中断恢复。
- [ ] Photos 导入和取消后恢复取景；相册滑动、编辑、分享、删除；iPad 分享弹窗锚点正常。

## 官方依据

- [Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)
- [Flutter Swift Package Manager](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)
- [Apple 本机运行与自动签名](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Apple Live Photos 保存](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos)
- [Photos 资源创建](https://developer.apple.com/documentation/photos/phassetcreationrequest)
- [Flutter 官方 image_picker](https://pub.dev/packages/image_picker)
