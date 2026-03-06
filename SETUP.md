# Timer Doctor — 安装与运行指南

## 第一步：安装 Flutter

### macOS 推荐方式（使用 Homebrew）

```bash
brew install --cask flutter
```

安装完成后验证：
```bash
flutter doctor
```

> `flutter doctor` 会列出缺少的依赖，按提示补齐即可（主要是 Xcode / Android Studio）。

---

## 第二步：初始化 Flutter 项目脚手架

进入项目目录，运行：

```bash
cd /Users/rio/projects/timer-doctor
flutter create . --project-name timer_doctor
```

这会生成 `android/`、`ios/`、`macos/`、`windows/` 等平台目录。

> ⚠️ `flutter create` 会覆盖 `lib/main.dart`。如果被覆盖，请恢复本项目中已有的版本。

---

## 第三步：安装依赖

```bash
flutter pub get
```

---

## 第四步：平台配置

### macOS

在 `macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements` 中，
确认已有（flutter create 默认已包含）：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

### Android

在 `android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签内添加：

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

### iOS

在 `ios/Runner/Info.plist` 中添加：

```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
```

### Windows

Windows 无需额外配置，`flutter_local_notifications` 自动处理。

---

## 第五步：运行

```bash
# macOS（推荐先从桌面端调试）
flutter run -d macos

# 查看所有可用设备
flutter devices

# 指定设备运行
flutter run -d <device-id>
```

---

## 打包发布

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Android APK
flutter build apk

# iOS（需要 Apple Developer 账号）
flutter build ios
```

---

## 项目结构

```
lib/
├── main.dart                    # 应用入口，初始化通知服务
├── models/
│   └── timer_state.dart         # TimerConfig / TimerState / TimerStatus
├── services/
│   ├── timer_service.dart       # 单例计时器，dart:async Timer
│   └── notification_service.dart # 本地通知（含 3 个操作按钮）
├── providers/
│   └── timer_provider.dart      # Riverpod StateNotifier，业务逻辑
└── screens/
    ├── home_screen.dart         # 主界面
    └── settings_screen.dart     # 设置（时长、快速预设）
```

## 通知操作按钮

| 按钮 | 行为 |
|------|------|
| 停止计时 | 清零计数，回到待机 |
| 立刻开始 | 周期 +1，立即开始新计时 |
| 等 N 分钟 | 进入休息倒计时，结束后自动开始下一轮 |

## 后续可扩展

- [ ] 系统托盘图标（`tray_manager` 包）
- [ ] 音效提醒（`audioplayers` 包）
- [ ] 历史统计图表
- [ ] 移动端后台保活（`flutter_background_service` 包）
