# 0.10.0 多选、旋转与界面改版

## 新功能

作品库右上角“选择”或长按照片进入多选。点击照片勾选/取消，可全选；返回键先退出选择。底部删除按钮展示数量，确认框说明哪些已关联照片会从系统同步删除，哪些仅删除本地。系统取消时整批本地文件保留；部分成功会保留失败项及其选择状态。删除仍遵循0.9.0的关联与授权规则，不按猜测处理未关联的系统副本。

设置增加“关于熊猫CCD”，包含版本/构建号、产品说明、照片/权限说明及开源许可证。版本展示统一用AppInfo，修复许可证页原先遗留的旧版本字符串。

## 旋转原因与实现

旧布局在Row和直接canvas之间切换，导致取景和两套控件被重新挂载。现在根部始终是同一Stack，控制面板、快门、机型列表、取景保留元素，调整定位和列表方向。普通窗口旋转/系统栏尺寸变化不视作物理显示切换；只对物理显示尺寸、display ID、像素密度或折叠状态交接刷新会话。

原生测试额外捕获到旋转期间短暂inactive→resumed。旧CameraSession对所有非resumed都立即release，造成重建和按钮变灰。现在inactive设置300ms可取消释放，paused/hidden/detached仍立即释放；显式离开取景如相册/编辑继续立即暂停。UI Shader只在参数或LUT变化时重建，旧句柄在帧结束后释放。

原生测试要求同一CameraController、CameraPreview元素、快门元素和CompactPresetStrip State贯穿竖→横→竖，保留当前机型，再拍照成功。该验证并非系统旋转动画零耗时/所有真机每帧无闪烁的证明；折叠换屏与真机性能仍需实测。

## 视觉与来源

按用户要求安装并应用UI/UX Pro Max的移动端与Flutter指引，保留奶油白、竹叶绿和熊猫标识。新版统一分组、字号、圆角、48dp触控和辅助文字，照片选择有勾选与边框。设计方案见design-system/panda-ccd/MASTER.md；整页网页模板不适用于相机，未直接套用。

## 验证入口

- `flutter test`：批量单请求/取消/部分成功/未知权限/本地删除、界面选择/全选/取消/确认、关于与大字体、取景元素跨方向保留、短失焦与后台释放；原有滤镜、水印、画幅、保存提示稳定性继续回归。
- `flutter test integration_test/batch_rotation_test.dart -d <测试模拟器> --enable-impeller --dart-define=PANDA_TRACE_ROTATION=true`，输出日志后用`tool/drive_batch_rotation_test.py <adb> <日志>`驱动。仅用于可丢弃模拟器：生成3张测试照片，拒绝一次系统批量删除、再允许删除，检查系统资源/本地原图，随后竖横切换并拍照。
- 正常安装包从`lib/main.dart`构建，不包含集成测试入口和诊断开关。iOS未构建或真机验证，无自写平台滤镜或业务分支。

## 正常安装包界面

- screenshots/camera-portrait-0100.png：竖屏取景。
- screenshots/gallery-selection-0100.png：正常包拍两张后全选。
- screenshots/settings-0100.png / screenshots/about-0100.png：设置与关于，版本0.10.0/build12。

以上为Android模拟器虚拟场景，不是实机风景样张。
