# 审核说明（英文可直接填写）

PandaCCD is an on-device retro camera and photo editor. No account or login is required. There is no user feed, advertising service, subscription system, or cloud beauty service in this version.

Camera access is used for preview, photos, and Live capture. Microphone access is requested only when Live sound is enabled. Photos add access is used to save results; broader Photos access is used only where needed for user-authorized asset access and linked deletion. Users can continue using locally saved results if Photos export is denied.

To test: open the app, grant Camera access, select a camera-inspired style, and take a photo. Results are saved by default; open the in-app album to edit them. Tap the beauty icon to adjust smoothing, tone evening, brightening, and lower-jaw shaping. Face detection and image effects run on the device. Up to eight detected faces can be processed; incomplete lower-jaw geometry is not artificially reshaped.

Face data: preview coordinates are used in memory. Face boxes, outline points, and mouth coordinates may also be retained in a photo's local editing record so the edit can be restored. No identity matching is performed. This data is not uploaded or shared with advertising or analytics providers. Deleting the corresponding in-app photo removes the associated source image, edit record, and local motion resources. OS backups and separately exported copies remain subject to the user's system settings.

Live: enable the Live icon and optionally enable sound in Settings. The camera temporarily buffers motion around the shutter. After capture, the app processes the motion on-device using the selected look and exports a paired still/video asset to Photos when authorized. Processing may pause in the background and resume in the foreground. For sharing a complete Apple Live Photo, use the system Photos app; in-app sharing also offers a static image or motion video.

Camera-inspired names describe independently tuned styles and do not imply camera-brand sponsorship or an exact color reproduction. Marketing screenshots use clearly identified AI-generated demo input processed by the app; they do not claim to be unedited phone-camera samples.

Developer contact: Pan Xinglin (潘星霖), pan_xinglin@126.com.

## 需在后台另填

审核联系人姓名：潘星霖。

审核联系邮箱：pan_xinglin@126.com。

审核联系电话：需要开发者提供真实可联系号码；不猜测、不用示例号码提交。

演示账号：不需要；在后台说明无需登录。

隐私政策和支持网址：部署 website 文件后填写真实公开 HTTPS URL。

## TestFlight 描述

PandaCCD是一款在设备上处理的复古相机，支持机型风格、可调美颜、Live动态照片、照片编辑和本地相册。

请重点检查：多人合拍是否分别美颜；前后镜头与四个握持方向；Live开关及连续拍摄；拍完切后台后返回生成；系统相册保存、播放、权限拒绝、分享和删除联动。

若遇到问题，请通过 pan_xinglin@126.com 提供机型、iOS版本、应用版本及复现步骤。截图或录屏请先遮盖私人内容。测试版可能存在问题，重要照片请另行备份。
