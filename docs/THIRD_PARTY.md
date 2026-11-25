# 依赖与参考来源

没有复制参考项目源码、LUT、图标或照片。熊猫图形、示例插画、HALD参数和GLSL由本工程独立编写。设置中的开源许可证入口使用Flutter LicenseRegistry读取依赖声明；商店发布前应按锁定依赖版本复核并保留许可证。

## 运行依赖

| 包 | 用途 | 发布者 | 许可证（发布前复核） |
|---|---|---|---|
| Flutter | UI、shader、Canvas、生命周期 | Flutter | BSD-3-Clause |
| camera | 相机纹理、镜头、快门、闪光 | flutter.dev | BSD-3-Clause |
| file_selector | 系统文件选择 | flutter.dev | BSD-3-Clause |
| path_provider | 沙盒目录 | flutter.dev | BSD-3-Clause |
| gal | 系统相册写入与相关授权 | midoridesign.studio | BSD-3-Clause |
| share_plus | 系统分享面板 | fluttercommunity.dev | BSD-3-Clause |
| sensors_plus | 加速度感知握持方向 | fluttercommunity.dev | BSD-3-Clause |
| audioplayers | 预加载、播放快门WAV | blue-fire.xyz | MIT |
| photo_manager | 相册资源ID、查询、删除、旧照片关联 | FlutterCandies | Apache-2.0 |
| crypto | 旧照片关联时比对SHA-256 | dart.dev | BSD-3-Clause |
| vol_spotter | 物理音量键事件 | 见锁定包声明 | MIT |

Flutter官方插件不等于没有平台实现：camera底层由官方插件桥接CameraX/AVFoundation；本工程禁止并没有加入Kotlin/Swift滤镜。gal/share_plus/sensors_plus是社区插件，复用同一套Dart调用，两端没有自写业务平台分支。[sensors_plus](https://pub.dev/packages/sensors_plus)提供Android/iOS加速度信号，握持分类、防抖、生命周期与界面方向请求在Dart中实现；不参与滤镜处理。iOS已配置运动权限用途说明。

来源：[camera](https://pub.dev/packages/camera)、[file_selector](https://pub.dev/packages/file_selector)、[path_provider](https://pub.dev/packages/path_provider)、[gal](https://pub.dev/packages/gal)、[share_plus](https://pub.dev/packages/share_plus)。准确的依赖树与版本见 `pubspec.lock`。

## 方法与参考

- [Flutter Fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)：资源注册、Canvas渲染、ImageFilter输入绑定。
- [ImageFilter.shader](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html)：Impeller要求、首个vec2/sampler自动绑定、OpenGLES方向。
- [FilterLibrary](https://github.com/hgayan7/FilterLibrary)：用户提供的参考，命名滤镜/复古效果方向。本项目未引入其实现和素材。
- [PhotonCamera](https://github.com/bjzhou/PhotonCamera)：用户提供的摄影架构参考。本项目采用独立的Preset/Recipe/参数模型。
- [Retroboy](https://github.com/mikljohansson/retroboy)：用户提供的老硬件效果参考。本项目独立实现固定传感器噪声和有序量化抖动。
- Filter4Free/ONNX：本期未引入。

若后续引入任何第三方源码、训练模型或LUT，须另外核对具体版本的许可证并保留声明；当前文档不授予任何参考项目的再分发权。

## 0.8.0 声音与硬件快门

[audioplayers](https://pub.dev/packages/audioplayers)和[vol_spotter](https://pub.dev/packages/vol_spotter)为社区跨平台插件，是对全部官方插件约束的明确偏差；没有新增自写Kotlin/Swift或滤镜平台分支。通用Flutter HardwareKeyboard在本次安卓系统按键测试中未收到音量键，插件补齐事件来源；注册和拍照条件、长按合并、设置均由Dart实现。

0.8.0的旧快门WAV由工程合成，历史生成器已改名`tool/generate_legacy_shutter_sound.py`，不会覆盖现用资源。iOS音量事件通过插件监听系统音量变化，并非AVCaptureEventInteraction直接硬件事件；没有释放事件，存在音量滑块/音频路由误触与连续按键辨识边界，需真机验证。详见CAMERA_CONTROLS_080.md。

## 0.9.0 相册与声音

photo_manager是社区跨平台插件，新增它是因为gal不返回保存后资源ID、也不提供系统照片查询/删除；这是对全部官方插件要求的明确偏差。核心滤镜继续纯Dart/GLSL。相册只请求照片权限，不请求视频、音频、位置或MANAGE_MEDIA。

现用快门声：**DSLR Shutter fast 006.wav**，作者ristooooo1，[原始作品和CC0声明](https://freesound.org/people/ristooooo1/sounds/539136/)，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。采用[Remotion公开的16位PCM副本](https://remotion.media/shutter-modern.wav)，[来源说明](https://www.remotion.dev/docs/sfx/shutter-modern)。未引入Remotion软件。音频0.489秒、单声道44.1kHz；署名和来源随包保存在assets/licenses/shutter.txt，也注册到应用开源许可证页。快门声的题名不代表佳能等内置机型的原机快门录音。


## 0.12.0 人像与动态媒体

用户授权新增本地 `panda_media` 双端桥：Android ML Kit face-detection16.1.7（随包模型）、MediaCodec/MediaMuxer；iOS Vision/AVFoundation/ImageIO。Flutter官方 camera 采集与录制，video_player播放动态。所有LUT、美颜和瘦脸仍由Dart/GLSL执行；无网络人脸上传。

Android Motion Photo封装参考 [Young-Spark/oppo-live-photo-maker](https://github.com/Young-Spark/oppo-live-photo-maker) 与 [PetrVys/MotionPhoto2](https://github.com/PetrVys/MotionPhoto2)，两者MIT许可在assets/licenses随包登记。自写媒体桥BSD许可同样登记。未引入商业美颜或厂商Live SDK。集成测试人像来源Pexels/Roberto Hund，出处见测试文件，仅测试使用，不打入正式安装包。


## 0.12.2 GPUPixel下颌变形

复用PixPark GPUPixel的FaceReshapeFilter::curveWarp及多点控制思路，提交ef552bf8ce2d0d41fa9b979bfb5c7cf79374ca88。Apache-2.0完整许可及修改说明在assets/licenses/GPUPixel-*随包登记；修改后的GLSL保留署名。适配现有ML Kit/Vision轮廓、嘴部与下巴数据，增加平滑下落、下半脸保护和变形上限。未引入GPUPixel C++引擎、VNN二进制/模型或商业Facebetter/PixelFree SDK，未引入付费激活依赖。核心效果继续为Dart/GLSL。


## 0.13.0 iOS迁移

新增 Flutter 官方 image_picker（BSD-3-Clause）用于iPhone PHPicker；Android导入入口保持原实现。官方 camera_avfoundation 0.10.3+1（BSD-3-Clause）和 vol_spotter_ios 0.2.1（MIT）复制到third_party并保留原许可，局部方向/录音类别改动详见各自PANDA_PATCH.md。现有panda_media桥增加Photos资源写入，避免重复改写配对数据及仅添加权限下读取失败；核心图像效果仍共用Dart/GLSL。iOS系统快门声受设备设置约束，完整Live分享仍使用系统Photos。
