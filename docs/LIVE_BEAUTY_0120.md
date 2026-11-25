# 0.12.0：可调人像美颜与直接拍摄 Live

日期：2026-11-03；版本：0.12.0+20。保留原有奶油白、绿色界面和拍后进入编辑页的默认行为。

## 使用

- 取景页点“一键美颜”开启；旁边的参数按钮分别调整瘦脸、磨皮、匀肤、提亮和总强度，“恢复推荐”恢复自然人像组合。关闭后保留参数。编辑页也可调节。
- 点“LIVE 关”开启动态拍照，首次等待约1.3秒预录；之后按快门，保存快门前约1.3秒、后约1.2秒的画面。Live 声音在设置中开关，首次录音按需申请麦克风权限；拒绝后仍可拍无声 Live。
- 设置中的“拍后直接保存”仍默认关闭。开启后不进编辑页，照片先入作品库，动态部分后台生成，可继续拍摄；最多同时保留两项待处理任务。
- 作品库显示 LIVE 标记，详情页可播放动态、再次编辑、分享视频或静态图。Android 可分享封装后的动态照片；iOS 的完整 Live 分享使用系统照片入口。
- 生成失败时保留已存照片及动态源片段，不把失败结果当成成功的 Live；可通过重新编辑保存重试。删除作品会同时清理关联动态资源。

## 美颜实现

参考成熟产品将人像处理拆成独立参数的做法，不把美颜等同于全图曝光。Android ML Kit、iOS Vision 在设备本地识别人脸与脸颊轮廓；Dart/GLSL 根据轮廓做局部逆向变形，结合保边平滑、肤色均匀化、适度提亮与皮肤区域颗粒抑制。默认推荐瘦脸25、磨皮70、匀肤45、提亮30、总强度55；旧配方继续兼容，旧照片不会自动增加瘦脸。

未识别人脸时不进行局部瘦脸或人像磨皮。最多处理两张脸；侧脸、遮挡和小脸不保证与成熟商业人像SDK等效，也不包含五官重塑、妆容或生成式补脸。用户需用实际肤质、光线与前后摄像头检查效果。

预览识别采用节流和坐标平滑，不逐帧在CPU上做滤镜。支持视频录制与图像流同时运行的设备提供实时人脸效果；部分设备不支持两者并行时，会提示预览识别受限，成片仍独立检测并处理。

## Live 管线与格式

Flutter 官方 camera 负责摄像头和录制，维护短时滚动缓冲。Live 请求30fps，成片以24fps导出，动态长边最多1280像素（16:9时为720p），封面保留原有静态导出分辨率。照片与视频共用GLSL、LUT、美颜、裁剪和水印。音轨在可用时保留，后台串行处理，避免多个编码器并行占用。

资源包含封面、处理后的MP4、编辑配方及未加滤镜的视频编辑源。该编辑源已统一方向、裁短、缩放并重采样，**不是无损的相机原始视频备份**。失败恢复资源可包含原始录制片段。应用退出时不承诺尚未完成任务自动续跑；已有封面和动态源仍保留在作品库。

| 系统相册 | 实现 | 本次验证 |
|---|---|---|
| Google/通用 Android | Google Motion Photo V2 XMP、旧MicroVideo字段、JPEG+MP4 | 封装、偏移、Android MediaStore字节保留通过；未验真实厂商相册播放 |
| 小米 | 新旧字段兼容封装，自动识别或设置手选 | 格式单测；小米真机相册待验 |
| OPPO/一加/realme | Oplus标记、MPF索引、Google兼容字段 | 与参考二进制夹具逐字节比对通过；厂商真机待验 |
| 三星 | MotionPhoto_Data/Version、SEFH索引和SEFT尾部 | 与参考二进制夹具逐字节比对通过；三星真机待验 |
| vivo/华为/荣耀等 | 通用Motion Photo回退 | 不承诺原生相册识别为动态；应用内及视频分享可用 |
| iOS | JPEG/MOV同一资源标识、still-image-time定时元数据、Photos Live资源保存 | Apple媒体辅助代码在Mac运行通过，完整iOS构建/照片库/真机待验 |

Android手动格式选项供个别系统相册不识别时切换；格式实现不能代替厂商相册验收。纯HarmonyOS不在Flutter Android APK覆盖范围内。平台桥只做人脸识别、像素传输、媒体编解码及Apple配对，核心滤镜和瘦脸仍为Dart/GLSL；这是用户已授权的平台能力扩展。

## 验证记录

- Flutter静态分析通过；69项Dart/Widget测试通过。
- Android36 ARM64模拟器原生媒体集成通过：实际ML Kit检测、人像效果输出、OpenGLES上下方向哨兵、硬件编码接口、音轨合并、Live前后录制、后台连续拍摄、四个方向、前置带声音及MediaStore字节一致。
- 生成视频的照片/动态关键帧比较中，原方向优于90/180/270度旋转及水平/垂直翻转；前置同样通过。该证据来自模拟器图案，不替代真机人像视觉验收。
- Apple Vision/AVFoundation辅助源在Mac编译执行：检测到人脸、写入视频、图像/MOV资源ID一致，存在视频/声音/定时元数据轨；RGBA编码方向哨兵通过。SwiftPM清单解析通过。
- 本机没有完整Xcode，**未完成iOS App编译及iPhone Photos验收**。Android品牌相册、实体闪光灯配合Live、真机温升/耗电/低端性能、复杂人像效果仍待验证。
- 正常Android调试APK构建通过；非测试入口，QA人像和视频不打入安装包。测试夹具仅供集成验证。

原生集成：`flutter test integration_test/media_pipeline_test.dart -d <设备>`，并同时运行 `tool/drive_media_pipeline_test.py --log <日志> --output <tar>`，仅用于可清空的测试安装。测试结束后需重新构建正常 `lib/main.dart` 安装包。

界面截图：[取景页](screenshots/live-enabled-0120.png)、[美颜参数](screenshots/beauty-controls-0120.png)。原生测试输出见[验证摘录](qa/media-0120.txt)。

## 参考与许可

- [Google Motion Photo规范](https://developer.android.com/media/platform/motion-photo-format)：主格式依据。
- [Apple Live Photo采集与保存](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos)：配对与Photos依据。
- [腾讯人像美颜参数](https://trtc.io/zh/document/45400)：独立调节思路参考，未集成付费SDK。
- [OPPO封装参考](https://github.com/Young-Spark/oppo-live-photo-maker) 与 [Samsung封装参考](https://github.com/PetrVys/MotionPhoto2)：MIT，许可证随包保留；不包含品牌SDK。
- [小米Live Photo SDK说明](https://dev.mi.com/xiaomihyperos/livephoto)：不将小米接口误当跨品牌标准，未申请商业接入。
