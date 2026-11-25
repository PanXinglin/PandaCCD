# CCD机型与风格调研（0.3.0）

日期：2026-10-26。

## 选择依据

本次优先选择近期中文CCD讨论中反复出现的G12、IXUS95 IS、IXUS130、W350/W830，再加入有明确官方色彩模式资料的F200EXR。没有取得可核验的全市场销量或小红书平台总榜，所以不把这六款写成严格的热度排名，也不引用二手价格作为销量证据。

近期讨论线索：[2026年佳能/索尼CCD社区整理](https://post.smzdm.com/p/a823nr27/)、[G12与常见CCD机型讨论](https://post.smzdm.com/p/al3q4wdp/)、[W系列讨论](https://post.smzdm.com/p/aqrn5dkk/)。这些是社区讨论入口，含对其他平台内容的转述，不能当作厂家色彩定义或准确销量数据。

## 本次加入的机型

| 机型 | 年代与传感器 | 应用内的风格方向（原创调优） | 建议场景 |
|---|---|---|---|
| 佳能 PowerShot G12 | 2010，1/1.7英寸CCD | 自然肤色、轻微红橙/蓝色增强、低颗粒 | 日常人像、旅行 |
| 佳能 Digital IXUS95 IS | 2009，1/2.3英寸CCD | 选择日光暖肤方向，柔亮部和轻抬阴影 | 晴天人像、校园 |
| 佳能 Digital IXUS130 / SD1400 IS | 2010，1/2.3英寸CCD | 选择社区常见的清透偏粉取向、明亮中间调 | 人像、聚会；闪光灯单独选择 |
| 索尼 Cyber-shot DSC-W350 | 2010，1/2.3英寸Super HAD CCD | 选择蓝绿清爽的日光取向，略增强对比与色彩 | 蓝天、绿植、城市街头 |
| 索尼 Cyber-shot DSC-W830 | 2014，1/2.3英寸Super HAD CCD | 明亮、低对比、较轻颗粒的日常取向 | 明亮室内、日常人像 |
| 富士 FinePix F200EXR | 2009，1/1.6英寸Super CCD EXR | 参考其VIVID模式的高饱和、高对比方向，增强蓝绿 | 自然风景、旅行 |

表中风格方向是本应用的设计选择，不代表相机在所有光线、白平衡和拍摄模式下的固定输出。手机已有ISP处理的照片也与原CCD传感器输入不同。没有同场景色卡、实机配对采样或厂家色彩配置文件，不能宣称像素级复刻。

## 核验资料与样张入口

- **G12**：[Canon Camera Museum](https://global.canon/en/c-museum/product/dcc596.html)确认年代、CCD与DIGIC4；[Imaging Resource原始评测](https://www.imaging-resource.com/cameras/canon-g12-review/)给出实验室色彩观察，适量增强部分颜色且有细微色相变化；[原机样张](https://www.imaging-resource.com/cameras/canon-g12-review/gallery/)可查看多种ISO和光线。
- **IXUS95 IS**：[Canon Camera Museum，SD1200 IS同机型](https://global.canon/en/c-museum/product/dcc570.html)确认CCD与型号对应；[Photography Blog实测与样张](https://www.photographyblog.com/reviews/canon_digital_ixus_95_is_review)涵盖日光、闪光和夜景。暖肤是本应用的日光风格选择，不是官方定义。
- **IXUS130**：[Canon官方说明书入口](https://asia.canon/en/support/0300312002)确认SD1400 IS/IXUS130对应；[Cameralabs实拍](https://www.cameralabs.com/canon_powershot_sd1400_is_ixus_130/3/)及[Photography Blog](https://www.photographyblog.com/reviews/canon_digital_ixus_130_review)提供JPEG、闪光、夜景例子。偏粉取向参考社区审美，未做实机标定。
- **W350**：[Sony官方发布资料](https://www.sony.com.hk/press/pdf/20100113_07e.pdf)确认Super HAD CCD；[Cameralabs同场景比较](https://www.cameralabs.com/sony_cyber-shot_dsc_w350/2/)及[原机样张](https://www.cameralabs.com/sony_cyber-shot_dsc_w350/3/)可比较风景、人像和不同ISO。其日光人像也可能偏暖，不能把所有W350照片都解释为冷调。
- **W830**：[Sony官方规格](https://www.sony.jp/cyber-shot/products/DSC-W830/spec.html)确认CCD；[Cameralabs实测与样张](https://www.cameralabs.com/sony_cyber-shot_w830/3/)为参考。应用里的柔和由全局色调实现，不是人脸识别磨皮。
- **F200EXR**：[富士官方手册](https://dl.fujifilm-x.com/support/manual/f/finepix_f200exr_manual_01.pdf)第65页区分STANDARD/VIVID/SOFT；VIVID强调饱和度和对比，更适合自然风景。[Impress原机实拍](https://dc.watch.impress.co.jp/cda/review/2009/02/13/10199.html)列出不同模式与曝光。应用未复刻富士专有胶片模拟算法。

参考图的版权归原作者；本工程不打包这些照片，也不把它们作为应用自有样张。部分网页下载受限制，本次依据可访问的评测、样张页面与官方规格交叉整理，不声称已取得所有原始JPEG。

## 实现与兼容

- 六款使用独立HALD PNG与独立参数；在`tool/generate_luts.py`中用原创曲线和选择性色相/饱和度调整生成。实时预览和保存继续共用Dart/GLSL，没有新增原生滤镜。
- 界面显示“机型名＋风格说明”；点击顶部机型区域或暗房的机型库，可查看年代、CCD类型、场景与说明。机型灵感与创意风格分组。
- 保留原有5款创意滤镜及其ID、LUT和自定义参数。0.1/0.2版本的选择序号通过旧ID列表迁移，避免插入新机型后串成其他滤镜。
- 0.3版本起保存稳定`selectedId`，后续增减排序不再影响当前选择。旧照片仍通过原ID识别；新机型预设JSON需要支持该机型的应用版本。
- 水印显示G12/IXUS95等标识并注明INSPIRED。未获得品牌授权、未使用品牌Logo，不宣称原厂滤镜。
- 六款在相同生成色块上进行GPU输出对比测试，验证输出互不相同且中性灰无严重偏色。该验证是工程检查，不是相机还原精度认证。

## 界面截图

[相机页机型名称与风格](screenshots/model-presets-camera.png) · [完整机型库](screenshots/model-library.png)。截图来自Android模拟器，取景内容是模拟器摄像头图案，不是机型原始样张。
