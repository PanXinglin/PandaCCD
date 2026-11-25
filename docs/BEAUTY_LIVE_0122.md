# 0.12.2：Live关闭黑屏、可见取景调参和下颌瘦脸

日期：2026-11-03；版本：0.12.2+22。保留原有界面设计。

## 关闭Live后的取景连续性

用户录屏显示Live关闭后，已有控件和网格仍在，实际相机纹理长时间不显示。原实现关闭Live会同时恢复60fps、关闭音频配置、重新打开相机、重新绑定人脸图像流，并解绑CameraX VideoCapture，存在多处Surface切换。

Android现在关闭Live只结束录制并清理未使用的缓存片段，保留相机、Preview和已绑定VideoCapture。录制对象和声音采集会停止，不能把保留UseCase等同于继续录制。当前会话沿用30fps请求，直到退出相机、切换镜头等自然重开时再恢复普通配置。美颜在Android的普通拍照和Live模式下均采用限频、480像素未滤镜取景采样，不为开关美颜反复切换ImageAnalysis。

静态照片的方向锁不再改动录制中或保留的视频流方向；下一段视频启动时再应用对应目标方向，避免静态快门干扰共享取景。iOS继续原有相机/声音配置切换，未照搬CameraX策略。

## 美颜操作区

取消遮挡大部分取景器的弹层。美颜调节直接替换原有底部/右侧机型列表区，使用下颌、磨皮、匀肤、提亮、强度标签和一个实时滑杆。快门、相册和镜头切换保留。关闭按钮或系统返回收起并保存；选择纯净取景同样收起调节栏。

竖屏展开美颜时，取景器与调节区各占独立空间；横屏/展开屏使用右侧操作区。调参期间无遮罩，取景持续可见。原机型列表状态保留，收起后返回原位置。

## 复用开源轮廓变形

调研比较了GPUPixel及现成Flutter美颜SDK。采用[GPUPixel](https://github.com/pixpark/gpupixel)的`FaceReshapeFilter::curveWarp`和多控制点思路，复用于Flutter GLSL；没有引入整套C++引擎、VNN模型或商业Facebetter/PixelFree SDK。Android/iOS核心效果仍共用Dart/GLSL。

原来只有两个腮部控制点，容易局部夹窄。现在读取ML Kit的36点脸部轮廓及嘴部中心、Vision的脸部轮廓及嘴部中心，在嘴部以下生成四对下颌控制点和下巴点。平滑收窄下颌、轻微调整下巴，保护嘴部以上的腮部和颧骨。真实人像对比后下调最高变形量；默认强度保留25，可自行调整。

没有完整轮廓时跳过瘦脸，不能再用旧照片中两个腮部点硬猜下颌。旧照片编辑时会重新识别轮廓。多点轮廓、嘴部、镜像、裁剪及平滑坐标保存在照片编辑记录中；检测和处理在设备本地完成。

来源固定为GPUPixel提交`ef552bf8ce2d0d41fa9b979bfb5c7cf79374ca88`的[src/filter/face_reshape_filter.cc](https://github.com/pixpark/gpupixel/blob/ef552bf8ce2d0d41fa9b979bfb5c7cf79374ca88/src/filter/face_reshape_filter.cc)。Apache-2.0许可及修改说明随包登记于`assets/licenses/GPUPixel-*`；shader带原作者署名与修改说明。

## 验证与边界

- 单元/界面回归覆盖小屏、横屏、展开屏和放大文字；美颜区与取景区无重叠，无遮罩，滑杆可即时启用美颜。下颌逐行宽度连续收窄、上半脸和远处背景保留，无脸/旧轮廓不乱变形。
- Android36 ARM64原生媒体测试：人脸轮廓、GLSL、拍照、动态处理、四向输出、前置带声音及系统相册写入通过。带声音Live关闭后连续15秒检查取景像素，相机实例保留，录制对象已停止、VideoCapture仍绑定，随后普通拍照成功。
- 原生横向大屏下，前后镜头四方向及重复Live切换通过，关闭Live保持同一相机并能读到真实取景；视频动态效果开中末帧检查通过。
- 真实人像0/25/100强度对比已审阅；测试人像仅用于QA，不打入正常安装包。来源：Roberto Hund / [Pexels 5317540](https://www.pexels.com/photo/serious-asian-woman-looking-at-camera-5317540/)。
- Apple Vision辅助源在Mac编译并运行，返回17个轮廓点和嘴部中心；这不是完整iOS App构建或iPhone真机验收。
- 未连接用户小米真机，仍需复测录屏中的场景。侧脸、遮挡和小脸不承诺与商业美颜SDK等效；不包含大眼、妆容或生成式修脸。

界面截图：[竖屏](screenshots/beauty-dock-portrait-0122.png)、[横屏](screenshots/beauty-dock-landscape-0122.png)。测试摘录：[关闭Live与媒体链路](qa/beauty-live-native-0122.txt)、[四向切换](qa/beauty-live-rotation-0122.txt)、[人脸采样](qa/beauty-face-0122.txt)、[Vision轮廓](qa/beauty-vision-0122.txt)。

上述测试不能代替厂商真机相册识别、真实肤质及长期温升验证。Live的格式兼容范围仍见[LIVE_BEAUTY_0120.md](LIVE_BEAUTY_0120.md)。
