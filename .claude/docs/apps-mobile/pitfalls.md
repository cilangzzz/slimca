# apps-mobile 已知坑点与注意事项

## 1. 构建与工程

### 1.1 出包必须在 apps/mobile 目录执行
`flutter build apk` 等命令必须在 `apps/mobile/` 内运行（pub workspace 成员包）。在仓库根
执行会打到 workspace 而非 app 目标。示例：
```bash
cd apps/mobile
flutter build apk --dart-define=... （全部键一次给齐）
```

### 1.2 Gradle 镜像链（两处文件都要在）
`android/settings.gradle.kts`（pluginManagement.repositories）与 `android/build.gradle.kts`
（allprojects.repositories）**双处**都配了阿里云镜像优先、官方源兜底（2026-11-17 实测
google()/mavenCentral() 直连不稳）。新增仓库配置漏一处就会超时。另有：
- `flutter_local_notifications` 要求 **core library desugaring**（app/build.gradle.kts
  `isCoreLibraryDesugaringEnabled + desugar_jdk_libs 2.1.4`，commit d9b4428）——缺了 AAR
  元数据检查挂；
- `wakelock_plus` 钉 `^1.4.0`（1.5+ 需 Dart 3.10/Flutter 3.38，Dart 3.8 上限）；
  `dynamic_color` 由 ui_kit 钉 1.8.1（上游 release 构建脚本 bug）。

### 1.3 Android 权限与通知 id
- 权限分级声明在 AndroidManifest：CAMERA（uses-feature required=false）、
  READ_MEDIA_IMAGES / READ_MEDIA_VISUAL_USER_SELECTED / READ_EXTERNAL_STORAGE(maxSdk=32)、
  POST_NOTIFICATIONS（W13）。改动权限需同步跑
  `test/photo_permission_manifest_test.dart` / `notification_permission_manifest_test.dart`。
- 待办提醒通知 id 用 **FNV-1a 派生**（`notificationIdFor`），绝不能用 `String.hashCode`
  （跨进程/平台不稳定，重启后无法对账取消）；训练常驻通知固定 id `0x5714`（专用段，不撞 FNV）。

## 2. 配置与凭据

### 2.1 dart-define 是编译期常量且缺省静默
- `String.fromEnvironment` 运行期/测试**不可改写**——测试必须显式参数注入覆盖；
- **全部键缺省静默回落桩/回环，不报错**：AI 无 KEY→`HeuristicFakeLlmAdapter`；拍照无凭据→
  百度位恒失败桩+Vision 离线桩；同步无凭据→`LocalLoopbackBackend`。**极易误以为接通真实
  通道**——冒烟验证要看 `syncBackendLabelProvider`（settings 页状态行）与解析结果
  `provider` 字段（'fake-vision'/'baidu'/'openai-vision'）。
- 出真实包必须**一次给齐**全部 10 个键（见 [data-model.md](data-model.md) §2），
  漏键的那条通道就静默退化为桩。

### 2.2 凭据安全
真实密钥只经 dart-define 注入，代码/文档/测试一律写键名占位；`http` 传输层错误只上抛
类型化 message（响应体/原文/图片字节禁入异常与遥测，§3.9）。

## 3. 装配顺序与 DI

### 3.1 bootstrap 装配顺序是硬约束
顺序 = **开库 → device_id → HLC 时钟 → 账本种子 → 投影 → 主题预载 → 内置包种子 → 遥测 →
留存锚点 → 两开关 → 同步栈 → 附件清扫 → 通知调度 → 计时器底座**。依赖链不可调换：
- device_id 先于 HlcClock（时钟构造需要 nodeId）；
- `daySummaryProjectionProvider` 与 captureGateway 必须共用**同一投影实例**（否则记一笔
  后快照不联动）；
- `hlcClockProvider`/`syncEngineProvider`/`syncCoordinatorProvider` 缺省 **throw
  StateError**——未走 bootstrap 的环境（新测试/新入口）直接崩，这是刻意的装配护栏；
- `initialThemeSettingsProvider` 必须 override 预载值，否则首帧主题闪跳（违反零闪跳承诺）。

### 3.2 main() 的挂接次序
崩溃钩子在 `runApp` **之前**挂（装配期异常不在钩子覆盖内）；`FrameTelemetry.attach`
仅非 debug（debug JIT 数字失真）；同步/提醒 coordinator 用 `unawaited(start())`——
本地优先，绝不让同步阻塞 UI。

## 4. 业务红线

### 4.1 IAP 代码保留但 UI 不露出
V1 UX 插曲（d6650f8）从设置页**整块移除**「升级 Slimca Pro」付费墙与裸「恢复购买」入口。
`lib/billing/` 四文件与 `billing_fake_test.dart` **保留不删**（真实通道待商店账号）。
新增设置页入口时不要把付费墙加回来；恢复购买仅当已有购买记录才可显示。

### 4.2 隐私开关缺省口径
- raw_input 上云**默认关**（原文不出设备；关=仅发规范化文本，缓存键不变解析结果不变）；
- 拍照原图即焚**默认开**（合规缺省；关=登记焚毁前本机留档副本，仅本地、永不上传）；
- 两开关坏值一律回落**更严档**（自愈永不放宽）；settings 是本地件永不同步。

### 4.3 金额/热量/日期口径与写路径纪律
- 金额一律分、热量一律 INTEGER kcal、日期一律 `yyyy-MM-dd` TEXT（字典序=时间序）；
  展示换算只走 `common/format.dart`；
- 所有写路径：业务行+outbox 同事务、软删墓碑、money 行确认后不可变（supersede 修正链）；
  绕过 `SyncOutboxWriter` 自写 outbox 时务必在同一事务内。

### 4.4 重复待办调度窗口
RRULE 展开窗口 = max(锚点,今天) → 今天+30 天，单待办上限 32 实例——**窗口尾部断排是已知
语义**（临近时下次 todos 变更自然补排）；过期实例不补发；MONTHLY 无效日（2/30）跳过当月
不终止。通知内容（标题/正文）属本地通知内容，不入遥测。

## 5. 测试纪律（新写测试必读）

- 禁真实平台通道/网络/通知/相机/计时器——一律 override Fake
  （`FakeReminderScheduler`/`FakeKeepAwakeService`/`FakeWorkoutTimerNotifier`/
  `FakeTranscriber`/`FakeBillingService`/`NoopTelemetryService`/`FakeImageSource`）；
- 计时断言用 `workoutClockProvider` 注入时钟 + `tester.pump` 推进，禁真实 Timer；
- 全局 `slimcaRouter` 是单例——跨用例携带 Tab 位（StatefulShellRoute 保栈），
  每用例先 `go('/')` 复位；
- 弹簧抽屉测试先 `pumpAndSettle` 收敛 springSnappy 220ms 再 tap（否则命中落屏外 miss）；
- FakeAsync zone 不投递真实文件 IO——轮询 helper 用 pump+runAsync 交替桥接
  （参照 e2e_photo_capture_test）。

## 6. 版本与联调状态（remaining 速查）

真实 Supabase 联调 / 百度+Vision 凭据 / 真实 IAP 商店账号 / 端侧 ASR 真机 / 通知与计时器
真机验收 / OCR 真实识别 / FrameTelemetry 真机帧率数字——均待外部凭据或真机，代码已就绪。
