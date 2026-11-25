# 架构与滤镜扩展

## 分层

- `domain/preset.dart`：6款机型灵感+5款创意预设、机型元信息、归一化参数、版本化Recipe、Watermark。选择状态保存稳定selectedId；旧版数字序号通过legacyPresetIds迁移。
- `services/app_state.dart`：ChangeNotifier 管理选择、参数、定制 LUT 和持久化；无第三方状态框架。
- `services/camera_session.dart`：官方 camera 插件、串行生命周期/快门/镜头/降档操作，编辑和选择文件期间暂停相机。
- `services/filter_engine.dart`：HALD 输入校验、GPU 预览参数绑定、照片解码、GLSL 绘制、变换与像素日期戳。
- `services/library.dart`：应用沙盒作品库、原图与参数写入；成片和设置使用临时文件 rename 提交。
- `ui/`：相机、暗房、作品库、详情、设置，以及复用组件。

## GPU 路径

预览：`camera → CameraPreview Texture → ImageFiltered(ImageFilter.shader) → GLSL → 屏幕`。

导出：照片压缩数据 → Flutter 图像解码（长边 ≤2560）→ 相同 GLSL `Canvas` 绘制 → 中心裁剪/旋转 → 日期与水印 → PNG → 沙盒 → AlbumSync → photo_manager 系统相册（gal仅用于写入授权）。只有拍后导出读取编码字节；预览不逐帧回读 CPU。

0.7.0将滤镜变换与水印记录进同一Picture，只生成一张输出ui.Image再编码PNG，移除完整中间图。saveCapture通过Image.clone租用已载入LUT的句柄，图像处理结束后先释放源图和租用句柄，再等待文件/系统相册；新PhotoEntry直接加入已加载列表，初始化及进入相册时才做目录刷新。FilterEngine.lastRenderTimings用于诊断合成及读回+编码两段时间，不参与效果或UI决策。

CapturePhase区分idle/capturing/saving；快门接受点击时轻触觉，原始照片文件成功返回后增加独立shots信号，ShutterPulse在预览层绘制短暗闪并等待首帧落地。该层不进入导出路径，尊重减少动画。CaptureButtonFace保留图标，250ms后才显示进度环；单张完成前仍限制下一张，避免无界后台导出队列。

ImageFilter 首个 vec2 和 sampler0 由引擎填写；Canvas 导出显式绑定同样位置。sampler1 是 HALD。需要支持 ImageFilter.shader 的 Flutter SDK 与 Impeller；不支持时显示说明并允许导入/示例编辑，不能假装实时滤镜可用。

参数按 `parameterDefaults` 顺序绑定 float uniforms。更改顺序或增删参数时同步修改 shader 与绑定方法，并运行 identity LUT 色彩测试。

## HALD 格式

支持 level 2–8 的标准 HALD PNG：正方形边长 `level³`，3D 立方边长 `level²`；红最快、绿其次、蓝最慢。线性序号 `r + g*N + b*N*N`，转二维 `(index % side, floor(index / side))`；八点 RGB 三线性插值。

例如 level 4：64×64 PNG，16³ 颜色。内置11款和identity由 `python3 tool/generate_luts.py` 可重复生成。六款机型灵感使用独立色相/饱和度/色调曲线，旧五款保留原公式。参数与LUT均为原创调优；没有复制第三方LUT或把参考照片打包进应用。

PS/DaVinci 常见导出是 `.cube` 或 8×8 分块 PNG，并不一定是 HALD。请用标准 identity HALD 在调色工具中应用颜色变换并无损导出，保持像素顺序与尺寸、不裁剪/缩放、不叠加颗粒/文字。不直接接受 `.cube`、条带 PNG 或其他布局；仅凭 PNG 扩展名不能判定 HALD 正确性。

设置 → 载入自定义 HALD LUT，仅替换当前机型。导出预设把 PNG base64 内嵌 JSON；在另一端导入无需共享本地路径。JSON 最大24MB、LUT最大16MB，参数须为有限0–1值，不接受未知版本和未知参数。

## 内存与存储

拍后解码限制像素数量、相册缩略图 cacheWidth420、离开编辑释放 ui.Image、shader和中间渲染图像主动 dispose。长时稳定性仍需 profile 真机测试。内置作品库保存在应用 documents；卸载应用会丢失本地作品，请保存到系统相册。删除应用副本不会删除系统相册副本。

保留原图时，作品旁写 `.original`。再次编辑优先读取原图；未保留原图则以已合成水印的成片作为输入，旧水印无法无损撤回。导出默认清除源 EXIF；不写定位信息。应用无账号/云端/照片上传接口。

0.5.0新增PhotoEdit快照：原图旁写`.edit.json`，记录原始机型参数、自定义HALD、水印、拍摄日期及旋转/裁剪。直接保存始终保留原图和快照；从相册再次编辑使用原记录，独立于当前机型。编辑结果作为新作品保存，拍摄日期用于水印，独立的保存时间用于文件名避免覆盖原作品。删除作品同时删除对应原图和快照。普通编辑流程由“同时保留原图”控制。

CameraTextureFit让CameraPreview自行决定比例，再等比容纳于取景框，避免方向事件不同步时被双轴紧约束拉伸。窗口/显示尺寸变化稳定450ms后重新枚举和初始化相机，普通宽高互换不反复初始化。大屏释放手机重力方向请求，拍照不临时锁定方向。具体边界见FOLDABLE_SUPPORT.md。

0.6.0相机重建前通过RepaintBoundary获取一次逻辑像素比例1的取景快照，覆盖新纹理准备期间，完成或销毁时释放；不是逐帧回读。几何状态区分已应用与观察值，短暂变化若返回原值则取消重建。闪光启用/自动使用30fps会话、拍前恢复自动曝光，关闭后按原目标恢复；分辨率降档独立于闪光帧率。

Watermark保留旧red/left/top字段兼容历史设置，新增text与includeModel。共用watermarkLabel与paintWatermark确保预览/保存文字一致；共用WatermarkChoices确保设置/暗房的颜色、位置和文字选择方式一致。新字段进入设置与PhotoEdit快照；缺少字段时恢复PandaCCD及机型名。

## 相册资源关联（0.9.0）

PhotoEntry旁的`.png.system.json`记录version和系统资源ids，与原图/编辑记录独立。写入临时文件后rename提交，不改旧照片名、编辑快照或原图。AlbumSync串行处理导出、旧照片关联、删除及外部删除核对；已存在或暂不可读的已关联记录不再重复导出。

进入作品库、点击刷新及作品库/详情从后台恢复时核对系统删除，只在完整权限下、所有已关联ID确定缺失时清理本地成片/原图/参数。限制权限、权限撤回、查询异常均视为unknown，保留作品。删除已关联作品时，先等待系统删除成功再清理本地；系统取消/部分失败保留本地。ID存在时还核对预期文件名，防止备份迁移后资源ID指向另一张照片。

旧版本没有资源ID，只有用户主动点关联旧照片才扫描照片元信息；仅同名候选读取原文件并按SHA-256比较，不读取不相干照片内容。无匹配不等于删除。核心拍摄链不扫描系统相册或旧作品。照片授权之外不请求媒体管理特殊权限、视频、音频或定位。

## 稳定取景与设计组件（0.10.0）

CameraPage的canvas和控制面板固定在同一Stack下，CompactPresetStrip保留State并切换滚动方向；横竖屏不会销毁CameraPreview与快门元素。geometry签名排除窗口宽高，只包含物理显示与折叠状态。CameraSession对inactive提供可取消300ms缓冲，真实后台状态和显式pause即时释放；参数/LUT不变时复用预览shader。

AlbumSync.removeMany先查询选择集，只汇总已知系统ID发起一次删除请求；按返回成功ID决定每张本地文件是否清理，拒绝整批时保留整批本地。GalleryPage选择集以路径标识，刷新时清除不存在项；权限弹窗期间不并发刷新。

ui/design_system.dart提供主题、SettingsSection和BrandHeading；ui/about_page.dart集中版本、隐私与许可证，domain/app_info.dart为界面版本源。Flutter技术栈和全部Dart/GLSL滤镜不变。
