# 可调美颜与Live图可行性调研

2026-11-02。当前应用0.11.1/build19。本次只调研，不修改应用代码和安装包。

## 结论

可调磨皮、匀肤、提亮可在现有GLSL中拆分。可靠瘦脸需要新增人脸关键点定位和跟踪，局部形变仍可用共享GLSL，不能用整图压窄冒充。Live素材保留、编辑后重新生成、相机新拍是三个不同层级，技术上可做，但各品牌系统相册识别和第三方分享都必须分别验证，不能承诺一个文件通吃所有安卓相册。

## 成熟产品参考和交互建议

[腾讯官方美颜场景参数](https://trtc.io/zh/document/45400)把磨皮、美白、自然瘦脸、窄脸、V脸等分开，推荐参数因风格不同而变化；这些数值不能直接映射到本项目算法。[美图官方相机说明](https://www.meituxiuxiu.com/zh-Hans/academy/camera)将肤质、磨皮、立体、去暗沉列为不同效果。

建议保留一键开启，在美颜面板先提供自然瘦脸、磨皮、匀肤/去暗沉、提亮，各自0—100滑杆、关闭和重置，默认适中，可按住查看原效果。整体开关关闭时保留各滑杆值，再开启恢复。无需为了充数提供尚无实现的五官项目。

[MediaPipe Android人脸关键点](https://developers.google.cn/edge/mediapipe/solutions/vision/face_landmarker/android)和[iOS关键点](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios)都有实时输入方案。建议检测/追踪提供点位，GLSL执行局部形变，包含镜像、四向、侧脸/遮挡、失检淡出、多人和时间稳定性处理。精确引擎与插件选型还需验证，尚未接入。

## Live范围

| 场景 | 可行性与关键工作 |
| --- | --- |
| 导入后保留原Live | 保留原始图像、视频和元数据；照片选择器必须取得完整原资源，不能仅解码封面 |
| 编辑后仍是Live | 封面和视频统一裁剪、方向、滤镜/美颜，重新写配对和封装；瘦脸需要跨帧跟踪，防止脸型跳动 |
| 熊猫CCD新拍Live | 需要快门前缓存、快门后录制、时间戳、可选音频和视频编码，不是拍完额外录一段就等价 |

当前`CameraSession`仅拍静态照片、enableAudio=false；`FilterEngine`只导出PNG，实时预览的shader不会自动烘焙进相机录制的视频；`SystemGallery.save`只保存单一图片。当前工程未具备完整Live链路。

建议内部统一保存原始封面、原始短视频、关键帧时间、方向、声音状态和编辑参数，再由目标系统适配器导出。保存失败保留原资源，禁止丢掉视频后提示Live保存成功。相册展示、批量删除、系统关联、分享都必须把一份Live作为同一个作品处理。

## 平台核查

- [Google Motion Photo格式](https://developer.android.com/media/platform/motion-photo-format)：图片加追加的视频及XMP/容器信息。可作为公开格式基线，但标准存在不等于所有厂商系统相册都能识别。输出需遵守其命名、长度和时间戳要求。
- [小米官方业务说明](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2000)：支持图片与2/3秒视频封装为一个文件，提供解析/合成SDK，合成识别对HyperOS与相册版本有要求。[小米服务页](https://dev.mi.com/xiaomihyperos/livephoto)明确说明不直接兼容其他厂商，官方接入涉及企业实名认证与服务开通；未取得企业接入或实测，不承诺SDK可立即使用。网页targetSdk说明可能滞后，应向实际SDK核对。
- [苹果官方Live Photo拍摄与保存](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos?changes=_9)：照片和配对视频合成为一个Photos资源，需要正确的配对标识和时序信息，不能把任意JPG和MOV随意当成Live。当前本地photo_manager3.12.0已有Darwin saveLivePhoto保存接口，但不是完整的拍摄/配对生成/逐帧滤镜管线；不能把新版插件的行为当成当前版本已验证能力。
- [vivo开放平台视频编辑](https://developers.vivo.com/product/d/video)介绍动态照片能力，但本轮未获得其完整文件规范和具体接入条件。
- [三星官方](https://www.samsung.com/ae/support/mobile-devices/enable-motion-photos-on-my-samsung-phone/)确认Motion Photo功能，但本轮未找到足以承诺跨版本写入兼容的官方完整格式规范。
- OPPO/一加、vivo/iQOO、三星、华为/荣耀：逐品牌/系统相册版本列为待验证，不使用第三方工具“全兼容”宣传作为验收证据。纯鸿蒙原生不是本Android APK/iOS工程自动覆盖的平台。
- [华为官方分享说明](https://consumer.huawei.com/cn/support/content/zh-cn15826621/)明确不支持的设备/应用可能只显示静图；系统相册支持与微信/小红书等分享支持应分别验收。

## 跨平台约束

Flutter/Dart主工程及核心滤镜/局部变形继续复用。新增的人脸检测、视频编解码、Live拍摄和系统相册导出需要双端插件或必要系统桥接；不应沿用“只能现有官方插件、完全不加平台适配”而承诺完整功能。[Flutter官方camera功能列表](https://pub.dev/packages/camera)包含静态拍照、录像和图像流，当前本地相机接口未发现完整Live Photo拍摄及预录制缓存API。

此前授权仅涉及安卓窗口表现，不能扩张为本轮媒体/人脸原生能力的授权。可行性结论不代表已经放宽约束、采购SDK或完成接入。

## 建议顺序与验收

先做可调美颜与可跟踪瘦脸；Live先保留导入原资源，再验证小米系统相册/Google公开基线/iOS保存，之后扩展其他安卓品牌。新拍Live最后单独验证摄像头预缓存与视频处理性能。按真实需求可并行做技术原型，但不在无验证情况下宣称所有品牌兼容。

每个目标至少验证：导入完整原Live、按住播放、封面/视频方向与效果一致、保存后系统识别、重启后仍能播放、删除整组资源、系统删除回流、支持的分享目标保留动态，以及不支持目标明确提供静图/视频导出。高耗电、存储与处理耗时需要真机测试，暂不提供无依据工期或帧率承诺。
