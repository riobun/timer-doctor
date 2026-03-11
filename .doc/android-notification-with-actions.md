# Android 带操作按钮通知的实现思路

## 背景：为什么这么复杂？

Android 上的 Flutter 应用同时运行着多个独立的 Dart 虚拟机（引擎）：

```
┌─────────────────────────────────────────┐
│           Android 进程                   │
│                                         │
│  Engine #1（主线程）                     │
│  ├─ 负责 UI 渲染                         │
│  └─ flutter_local_notifications 在这里   │
│                                         │
│  Engine #2（flutter_background_service） │
│  ├─ 后台计时、保持进程不死                │
│  └─ 独立的 Dart 运行环境                 │
│                                         │
│  Engine #3（通知回调，临时）              │
│  └─ 用户点击通知按钮时短暂启动            │
└─────────────────────────────────────────┘
```

这三个引擎**完全互相隔离**，变量不共享，函数不互通。这是后面所有坑的根源。

---

## 一、通知的分类

Android 上有两类通知：

| 类型 | 说明 | 用途 |
|---|---|---|
| **前台服务通知**（Foreground Service） | 服务运行期间常驻通知栏，用户不能主动删除 | `flutter_background_service` 的常驻通知（显示「专注中 24:59」） |
| **普通通知** | 用户可以划掉，可以带操作按钮 | 计时结束时弹出的「时间到！」通知 |

---

## 二、操作按钮的工作原理

通知的操作按钮本质上是一个 **`PendingIntent`**（待执行的意图）。

```
用户点击按钮
    ↓
Android 触发 PendingIntent
    ↓
┌─────────────────────────────────────┐
│ PendingIntent 有两种类型             │
│                                     │
│ FLAG_ACTIVITY  → 打开/切换到某个界面  │
│ FLAG_BROADCAST → 发送广播给 Receiver │
└─────────────────────────────────────┘
```

我们用 **广播（Broadcast）** 类型，因为不需要打开界面，只需要在后台处理逻辑。

---

## 三、为什么不直接用 flutter_local_notifications？

`flutter_local_notifications` 也支持操作按钮。理论上：
- 按钮点击 → 触发 `onDidReceiveNotificationResponse` 回调（app 在前台时）
- 按钮点击 → 触发 `onDidReceiveBackgroundNotificationResponse` 回调（app 在后台时）

**但在本项目里失效了**，原因是：

```
app 启动时：
  Engine #1 调用 plugin.initialize() → 插件内部保存了 Engine #1 的引用

后台服务启动时：
  Engine #2 也调用过 plugin.initialize() → 覆盖了 Engine #1 的引用！
  （后来修掉了这个，Engine #2 不再调用 initialize()）

但即使修掉这个问题，按钮点击依然没反应 ——
  因为 flutter_background_service 的广播接收器和
  flutter_local_notifications 的广播接收器之间存在未知冲突，
  导致通知按钮的 PendingIntent 根本没有触发。
  （在模拟器上尤为明显）
```

---

## 四、最终方案：完全绕开 flutter_local_notifications，自己写原生代码

### 整体链路

```
计时结束
  ↓
Engine #2 → service.invoke('complete') → Engine #1
  ↓
Engine #1 通过 MethodChannel 调用 Kotlin
  ↓
MainActivity.showTimerCompleteNotification()
  用 NotificationCompat.Builder 原生构建通知
  每个按钮对应一个 BroadcastIntent，指向 TimerActionReceiver
  ↓
用户点击按钮
  ↓
Android 发广播 → TimerActionReceiver.onReceive()
  写入 SharedPreferences["flutter.pending_action"] = "action_snooze"
  ↓
Engine #2 的 actionPoller（每秒一次）
  读 SharedPreferences → 发现 pending_action → 执行对应逻辑
```

### 关键代码（Kotlin）

```kotlin
// 1. 为每个按钮创建广播 PendingIntent
fun broadcastIntent(actionId: String): PendingIntent {
    val intent = Intent(this, TimerActionReceiver::class.java).apply {
        putExtra("action_id", actionId)
    }
    return PendingIntent.getBroadcast(
        this, actionId.hashCode(), intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE  // ← 必须加这个！
    )
}

// 2. 构建通知
NotificationCompat.Builder(this, channelId)
    .addAction(0, "立刻开始", broadcastIntent("action_start_now"))
    .addAction(0, "休息5分钟", broadcastIntent("action_snooze"))
    .build()
```

```kotlin
// 3. BroadcastReceiver 接收按钮点击
class TimerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val actionId = intent.getStringExtra("action_id") ?: return
        // 写入 Flutter 的 SharedPreferences
        // 注意：Flutter 的 key 有 "flutter." 前缀！
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.pending_action", actionId).apply()
        // 顺便取消通知
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(1)
    }
}
```

### Flutter 侧通过 MethodChannel 调用 Kotlin

```dart
// Dart 侧：触发通知
const _channel = MethodChannel('timer_doctor/notification');
await _channel.invokeMethod('showTimerComplete', {'snoozeMinutes': 5});

// Kotlin 侧：在 configureFlutterEngine 里注册
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_doctor/notification")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "showTimerComplete" -> {
                val snoozeMinutes = call.argument<Int>("snoozeMinutes") ?: 5
                showTimerCompleteNotification(snoozeMinutes)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

---

## 五、坑的汇总

### 坑 1：PendingIntent 在 Android 12+ 必须声明 mutability

```kotlin
// ✅ 正确
PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

// ❌ 错误（Android 12+ 会抛异常或静默失败）
PendingIntent.FLAG_UPDATE_CURRENT
```

### 坑 2：BroadcastReceiver 必须在 AndroidManifest.xml 里声明

```xml
<receiver
    android:name=".TimerActionReceiver"
    android:exported="false" />  <!-- 只接收本 app 内部广播，不暴露给外部 -->
```

忘记声明的话，按钮点击完全没反应，没有任何错误提示。

### 坑 3：Flutter SharedPreferences 的 key 有前缀

Flutter 的 `SharedPreferences` 插件在原生层存储时，所有 key 会自动加 `flutter.` 前缀：

```kotlin
// Flutter 侧写：prefs.setString('pending_action', value)
// 原生侧读：  prefs.getString("flutter.pending_action", null)  ← 必须加前缀

// 原生侧写，Flutter 侧读：
prefs.edit().putString("flutter.pending_action", value).apply()  // 原生写，加前缀
prefs.getString('pending_action')  // Flutter 读，不加前缀
```

### 坑 4：前台服务通知延迟（Android 12+）

`foregroundServiceType="specialUse"` 的前台服务通知会故意延迟约 10 秒才显示。
改成 `mediaPlayback` 类型可以绕过这个限制：

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="mediaPlayback"
    ... />
```

### 坑 5：flutter_background_service 的引擎不能初始化通知插件

Engine #2 启动时，`flutter_background_service_android` 这个插件会检测到当前不在主隔离（main isolate）里并抛出异常：

```
Exception: This class should only be used in the main isolate (UI App)
```

这会导致 Engine #2 里所有插件的注册不稳定。因此：
- **不能在 Engine #2 里调用 `flutter_local_notifications` 的 `initialize()` 或 `show()`**
- 通知必须全部交给 Engine #1 处理
- Engine #2 只负责计时逻辑，通过 `service.invoke('complete', ...)` 通知 Engine #1 去展示通知

### 坑 6：Engine #3（通知后台回调）需要手动初始化 Flutter

用户点击通知按钮时，如果 app 已经被杀死，系统会启动一个临时的新引擎（Engine #3）来执行回调函数。这个引擎里 Flutter 框架没有自动初始化，必须手动调用：

```dart
@pragma('vm:entry-point')  // ← 防止编译器 tree-shaking 删掉这个函数
void onNotificationActionBackground(NotificationResponse response) async {
    WidgetsFlutterBinding.ensureInitialized();   // ← 必须，否则 Platform Channel 不可用
    DartPluginRegistrant.ensureInitialized();    // ← 必须，否则插件无法调用原生代码
    // 然后才能安全使用 SharedPreferences 等插件
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_action', response.actionId ?? '');
}
```

缺少这两行，`SharedPreferences.getInstance()` 会静默失败，action 就此丢失，没有任何报错。

---

## 六、本项目的架构图（完整）

```
┌──────────────────────────────────────────────────────────┐
│  用户操作：点击「开始计时」                                │
└──────────────────────┬───────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────┐
│  Engine #1（主线程）                                      │
│  startTimer() → svc.startService() → svc.invoke('start') │
└──────────────────────┬───────────────────────────────────┘
                       ↓ IPC（进程内通信）
┌──────────────────────────────────────────────────────────┐
│  Engine #2（后台服务）                                    │
│  接收 'start' 事件 → 启动 Timer.periodic 倒计时           │
│  每秒 → service.invoke('tick') → Engine #1 更新 UI        │
│  计时结束 → service.invoke('complete') → Engine #1        │
│  actionPoller 每秒轮询 SharedPreferences                  │
└──────────────────────┬───────────────────────────────────┘
                       ↓ invoke('complete')
┌──────────────────────────────────────────────────────────┐
│  Engine #1（主线程）                                      │
│  收到 complete → MethodChannel → Kotlin 展示通知          │
└──────────────────────┬───────────────────────────────────┘
                       ↓ MethodChannel
┌──────────────────────────────────────────────────────────┐
│  Kotlin（MainActivity）                                   │
│  NotificationCompat.Builder → 展示带按钮通知              │
│  每个按钮 = BroadcastIntent → TimerActionReceiver         │
└──────────────────────┬───────────────────────────────────┘
                       ↓ 用户点击按钮
┌──────────────────────────────────────────────────────────┐
│  TimerActionReceiver（BroadcastReceiver）                 │
│  写入 SharedPreferences["flutter.pending_action"]         │
└──────────────────────┬───────────────────────────────────┘
                       ↓ 1秒内
┌──────────────────────────────────────────────────────────┐
│  Engine #2 actionPoller                                   │
│  读到 pending_action → handleAction() → 执行对应逻辑      │
│  → service.invoke('ui_snooze' / 'ui_start_now') → #1 更新 UI │
└──────────────────────────────────────────────────────────┘
```
