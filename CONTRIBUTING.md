# 参与 PandaCCD

欢迎提交问题、复现步骤和改进建议。报告相机或 Live 问题时，请提供设备型号、系统版本、应用版本和必要的录屏，先遮盖照片、账号和设备标识等私人内容。不要发送密码、验证码、签名证书或 API 密钥。

## 开发约定

- 保持 Android / iOS 共用业务代码，核心滤镜和美颜使用 Dart / GLSL。
- 原生媒体桥只负责人脸识别、编解码和系统媒体配对，不承载滤镜业务逻辑。
- 不提交 `.env`、签名证书、`key.properties`、个人 Team ID 或本机 SDK 路径。
- 新引入的源码、模型、LUT、声音和图片必须确认许可证，并更新 `docs/THIRD_PARTY.md`。
- 尽量保持现有界面与交互；较大视觉调整请先提供可审阅的设计预览。

## 提交前检查

```sh
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
```

涉及物理相机、系统相册、音频或 Live 的改动，还需要在相应真机上验证；模拟器测试不能替代真机验收。
