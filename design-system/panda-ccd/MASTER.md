# 熊猫CCD界面规范

日期：2026-11-09。技术：Flutter Material 3。覆盖取景、相册、编辑、设置、关于和选择弹层。

## 来源与取舍

按用户要求安装并读取UI/UX Pro Max：`~/.codex/skills/ui-ux-pro-max/SKILL.md`，来源https://github.com/nextlevelbuilder/ui-ux-pro-max-skill 。运行整页设计查询和Flutter栈/批量操作查询。整页模板分别命中像素游戏、网页叙事，与手机相机不吻合，未采用/持久化模板输出。以下是结合现有熊猫CCD品牌制定的方案；使用该skill的移动端触控、对比度、层级、减少动画、稳定状态与安全区规则。

## 视觉

- 取景页采用石墨灰、银白图标和少量暖色状态标记。相册、编辑、设置和关于使用中性雾白底（#F5F6F8）、纯白面板和石墨文字。设置首页提供常用开关和分类入口，编辑预览与工具用细线分隔，工具按风格、细调、构图和水印切换，保存入口固定在顶栏。浅色页面的选择弹层用实色白底，取景弹层沿用石墨玻璃。
- 取景背景 `#111316`，浅色页面背景 `#F4F5F7`，分组 `#FDFDFE`，浮层 `#F8F9FB`，分隔线 `#DCE0E6`，删除按钮 `#AE404A`。
- 4/8dp节奏；分组间距24dp，内容边距16/20dp，分组圆角20dp，选择弹层顶角26dp。
- 使用系统中文字体，主标题21–24sp，控件14sp，辅助12sp。窄卡片的11sp仅用于非核心照片日期/机型标注；支持系统字体缩放和省略。
- Material轮廓图标；点击区域48dp。选择状态同时呈现勾选及边框，不能只靠颜色。
- 取景底栏铺到左右和底边，用渐变承托机型文字和白色快门。系统手势区只铺背景，操作区按安全区留白。参考 [Apple 材质指南](https://developer.apple.com/design/human-interface-guidelines/materials)。
- 熊猫保留小三角鼻，钛银镜头圈放在脸外。0.13.9 用 GPT Image 生成参考图，再以 SVG 简化轮廓与光影，确保小尺寸可辨。应用内标志、启动图和双端桌面图标从同一 SVG 导出，Android 另有适配圆形裁切和主题色的图层。0.14.0 桌面图标改为暖白外底，内圈用石墨灰衬托白脸，耳缘加一条细亮边。0.14.1 保留轮廓，外底改为暖象牙色，镜头圈使用浅香槟铜，黑白五官保持高反差。 0.14.4 桌面图标改用应用内的小标，银白底衬托石墨线条，暖色集中在镜头细圈。参考 [Halide 图标](https://www.lux.camera/halide-mark-iii/)、[Apple 图标规范](https://developer.apple.com/design/human-interface-guidelines/app-icons)和 [Android 自适应图标规范](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。

## 交互

- 画幅、倍率、美颜共用取景下沿的一行。倍率档位固定，当前倍率在档位内更新。点美颜打开同一个含开关和滑杆的面板。常见屏宽下这一行保持 44dp 触控高度。
- 顶部左侧保留窄 CCD 入口，右侧工具浮在画面上。Live 和闪光灯相邻，闪光灯点按在关闭、自动和开启间轮换。快门为实心白圆和外环，前后镜头使用双箭头。
- 作品库常态点开照片；长按或“选择”进入多选，支持全选/取消全选、退出选择、底部删除。确认框说明本地与系统删除范围。
- 批量系统删除合并成一次请求。系统取消保留整批本地数据；部分失败保留未成功项和选择状态，并显示数量。
- 取景、快门和机型列表保持同一元素树；布局只改变位置、尺寸和列表方向。普通旋转不重开相机，物理显示/折叠状态交接仍可刷新。
- 短暂失焦保留纹理300ms；恢复焦点取消释放，真正paused/hidden/detached立刻释放。文件选择/编辑等显式离开取景仍立即暂停。
- 不添加额外旋转入场/淡入动画；风格选择滚动尊重减少动画。设置/关于正文在宽屏限制680dp，空相册小高度可滚动。

图标参考稿：[GPT Image 透明底初稿](../../docs/screenshots/panda-mark-gpt-0139.png)。提示词：

> Create one original premium app icon mark for Panda CCD, a retro digital camera. Transparent background, centered square composition. A recognizable adult giant panda face in soft silver-white and graphite, round dark ears, tilted oval eye patches, tiny natural triangular nose and a short subtle mouth. Set the panda inside one thin brushed-titanium camera lens ring so the camera motif sits outside the face. Clean vector-like silhouettes, restrained highlights, high contrast at 24 pixels, generous margins, no text, no enclosing rounded-square tile, no giant nose, no snout.
