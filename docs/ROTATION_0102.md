# 0.10.2：外屏按钮方向、内屏系统强制旋转

2026-10-29，build14。原有设计保留，不实施A/B/C/D视觉方案。

用户反馈0.10.1外屏已不再切换整页，但相机图标方向反了；内屏仍会切换整页，画面与按钮一起闪。

## 本版修改

- 修正握持与图标的旋转符号：左横握持时图标顺时针90°，右横握持时逆时针90°，使图标朝向现实中的上方。
- 展开内屏不再主动放开竖向偏好；在Android大屏忽略方向请求时，也通过Flutter中的CameraViewport抵消窗口转向，保持相机操作区的物理位置。
- 预览单独抵消外围场景变换，保留官方插件的传感器/显示方向变换和拍照方向，避免二次旋转与压扁。
- 状态栏、导航栏与挖孔边距换算到稳定场景坐标；操作区布局阈值使用完整逻辑窗口，不因旋转后边缘位置变化突然切换侧栏。
- 删除按显示尺寸/挖孔/折叠状态变化就重开相机的路径；正常窗口变化只更新布局。
- 删除失焦300ms后关闭相机的定时器。inactive仍可见时保留预览；hidden/paused/detached和显式进入选图/编辑/相册时立即释放。

## 验证

- flutter analyze：无问题；flutter test：57项通过。
- 图标方向回归：左/右握持分别断言+0.25/-0.25圈。
- 强制大窗口转向：逻辑场景尺寸、控件元素身份和点击动作保留，场景补偿加图标旋转后与系统正向一致。
- Android API36模拟器，1800×2200、420dpi、最短边686dp，系统ignoreOrientationRequest=true。
- 实际系统左横→竖→右横→竖，使用真实CameraOrientation及官方相机插件；转向等待期间和完成后的逐帧检查均保留同一相机、纹理、预览、快门、机型列表对象。
- 实际拍照横图640×480、竖图480×640（该集成测试固定medium/30fps，隔离性能降档）。
- 展开系统通知栏持续2秒再收起，跨inactive/resumed仍保留相机及控件；hidden释放另有单元覆盖。
- 使用main.dart正常入口重新构建版本0.10.2/build14，非集成测试包。

## 边界

目前没有连接用户的小米折叠屏或三星折叠屏；不能把模拟器结果当成这些设备已无闪动。系统自身的屏幕旋转动画也不受Flutter组件完全控制。iOS原生构建/真机转向仍待验证。此次未改Kotlin/Swift，不增加原生滤镜与平台业务分支。

官方依据：
- https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html
- https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html
- https://developer.android.com/media/camera/camera2/camera-preview

## 正常包逐帧录屏的新发现

`docs/screenshots/inner-rotation-0102.mp4`为正常main.dart包的实际系统转向录屏。10fps接触表显示：相机对象保留之外，系统仍会把整个应用窗口截图旋转/交叉淡化。因此“对象未销毁”不能当作视觉无闪动的结论，本版不能宣称完全解决。

Android官方WindowManager.LayoutParams提供ROTATION_ANIMATION_SEAMLESS，明确面向相机取景场景，但它不是Flutter SystemChrome已公开的窗口属性。拟议最小原生启动壳改动见`docs/proposals/android-camera-window.patch`，尚未应用或验证，需先确认是否允许超出最初“不写平台分支定制逻辑”的限制。滤镜与相机访问仍在Dart/GLSL和官方插件内。

https://developer.android.com/reference/android/view/WindowManager.LayoutParams#ROTATION_ANIMATION_SEAMLESS

2026-10-30补记：用户已明确允许最小安卓窗口配置，后续实现与验证记录见ROTATION_0103.md。
