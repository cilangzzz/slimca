# 全局配置文档（_config）

> Slimca 无独立配置模块：配置 = dart-define 编译期注入 + 工厂内缺省值 + Gradle 镜像 + CI 工作流。
> 凭据一律键名占位（见 dart-define 注入），禁止写入真实值；`.env*` 已被 .gitignore 排除。

## 环境

无 profile/dev-prod 体系，环境由「是否注入 dart-define 凭据」区分（代码零改动切换装配）：

| 环境 | 激活方式 | 部署位置 | 用途 |
|------|---------|---------|------|
| 缺省开发 | 不注入任何 dart-define | 本机/模拟器 | 离线可跑：AI=Heuristic 离线桩、同步=LocalLoopback、拍照=离线演示桩 |
| 联调 | `flutter run --dart-define=KEY=VALUE ...` | 真机/模拟器 | 真实 AI/同步/OCR 链路（已联调 DeepSeek，通道 id=deepseek-flash） |
| 出包 | `cd apps/mobile && flutter build apk --dart-define=...` | Android 真机 | release APK |
| CI | 无凭据注入 | GitHub Actions ubuntu-latest | analyze + test + debug APK 产物 |

## 配置文件清单

| 文件 | 内容 | 环境差异 |
|------|------|---------|
| pubspec.yaml（根） | pub workspace 声明，聚合 10 成员包，Dart ^3.8.0 | 无 |
| apps/mobile/pubspec.yaml | 应用依赖 + 版本号 `version: 1.1.0+2`（--build-name/--build-number 可覆盖） | 无 |
| packages/*/pubspec.yaml | 各包依赖，`resolution: workspace` | 无 |
| */analysis_options.yaml ×10 | 统一 flutter_lints（包内仅 include 一行，apps/mobile 为模板全量），无自定义规则 | 无 |
| apps/mobile/android/gradle/wrapper/gradle-wrapper.properties | Gradle 8.12 发行包走腾讯镜像 `mirrors.cloud.tencent.com/gradle` | 无 |
| apps/mobile/android/settings.gradle.kts | 插件仓库镜像 + AGP 8.7.3 / Kotlin 2.1.0 / flutter-plugin-loader 1.0.0 | 无 |
| apps/mobile/android/build.gradle.kts | allprojects 仓库镜像 + build 目录重定向至 apps/mobile/build | 无 |
| apps/mobile/android/app/build.gradle.kts | applicationId、JDK 11 + desugaring、签名 | release 签名暂用 debug key（待办） |
| apps/mobile/android/local.properties | flutter.sdk / Android SDK 路径，Flutter 工具自动生成 | 已 git-ignore，每机各自生成 |
| .github/workflows/ci.yml | CI 流水线（详见下节） | 无 |

注意：**仓库无任何 build.yaml** —— drift codegen 走 drift_dev 默认配置，改表后在 `packages/core_db` 目录执行 `dart run build_runner build -d` 重新生成 `app_database.g.dart`。

## 关键配置项

### dart-define 键（`String.fromEnvironment` 编译期常量）

| 键 | 作用 | 缺省行为 | 装配点 |
|----|------|---------|--------|
| SLIMCA_SUPABASE_URL | Supabase 项目端点 | 空串 | sync/sync_backend_factory.dart |
| SLIMCA_SUPABASE_ANON_KEY | Supabase 匿名 key | 空串 | 同上（与 URL 成对：齐备→SupabaseSyncBackend 托管同步；任一缺失→LocalLoopbackBackend 本地回环） |
| SLIMCA_AI_BASE | 文本解析 OpenAI 兼容端点根路径 | `https://api.openai.com/v1` | ai/capture_parser_factory.dart |
| SLIMCA_AI_KEY | 文本解析 API key | 空串 | 空串→HeuristicFakeLlmAdapter（默认 mock，零网络）；已联调 DeepSeek |
| SLIMCA_AI_MODEL | 文本解析模型名 | `gpt-4o-mini` | 等于缺省模型→response_format=json_schema 档；自定义模型→自动降 json_object 档（core_ai 校验器兜底正确性） |
| SLIMCA_VISION_BASE_URL | 拍照兜底位 Vision LLM 端点 | `https://api.openai.com/v1` | ai/photo_parser_factory.dart |
| SLIMCA_VISION_API_KEY | Vision LLM key | 空串 | 空串→OfflineStubVisionCapturePhotoParser（离线演示桩） |
| SLIMCA_VISION_MODEL | Vision 模型名 | `qwen-vl-plus`（唯一带 defaultValue 的键） | 同上 |
| SLIMCA_BAIDU_API_KEY | 百度菜品识别（拍照先行位） | 空串 | 与 SECRET 齐备→BaiduDishCapturePhotoParser；否则 UnconfiguredBaidu 桩恒结构化失败，由 fallback 位接手 |
| SLIMCA_BAIDU_SECRET_KEY | 百度 Secret Key（client_credentials 换 token） | 空串 | 同上 |

文本路径超时 5s、百度 token 5s/识别 8s、Vision 10s（写死在工厂常量，非配置项）。

### CI（.github/workflows/ci.yml，单 job）

- 触发：push/PR 全部；`permissions: contents: read`；concurrency 按 ref 去重（PR 新 push 取消旧 run）
- 工具链：ubuntu-latest + JDK 17（Temurin）+ Flutter 3.32.0 stable（flutter-action@v2，pub cache 开启）
- 步骤：根目录 `pub get` → `analyze` → `test`（for 循环遍历 apps/mobile 与 packages/* 中含 test/ 的包逐包执行，新增包自动纳入）→ `build apk --debug`（working-directory: apps/mobile）→ 上传 artifact 保留 14 天
- iOS 签名/golden 不在 CI（设计口径走 Codemagic 云 Mac，未接入）

### 依赖版本 pin（升级即挂，勿动）

| 包 | pin | 原因 |
|----|-----|------|
| dynamic_color（ui_kit） | 精确 1.8.1 | 1.9.0 上游 android/build.gradle.kts 有 bug（kotlin 插件未应用 + 硬编码 AGP 8.13.1），release 构建必挂 |
| wakelock_plus（apps/mobile） | ^1.4.0 上限 | 1.5+ 需 Dart 3.10/Flutter 3.38，与 Dart 3.8 工具链不兼容 |

### 运行期开关（配置但非 dart-define）

raw_input 上云闸门 `RawInputPolicy`（apps/mobile/lib/app/providers.dart 的 rawInputPolicyProvider）：默认关（原图即用即焚），控制食物照片是否进入云解析路径；设置页运行期切换，与编译期配置无关。

## 环境差异矩阵

| 配置组 | 缺省开发 | 联调 | CI |
|--------|---------|------|-----|
| AI 文本解析 | HeuristicFakeLlmAdapter 离线桩 | OpenAI 兼容真实端点 | 离线桩 |
| 拍照解析 | 离线演示桩（confidence 0.35 强制校核） | 百度先行 + Vision 兜底（Fallback 组合） | 离线桩 |
| 同步后端 | LocalLoopbackBackend（内存回环） | SupabaseSyncBackend（托管 RPC） | LocalLoopback |
| raw_input 上云 | 关 | 可开（设置页） | 关 |
| 产物 | flutter run debug | release APK | debug APK artifact |
| 凭据来源 | 无 | --dart-define 命令行注入 | 无（secrets 未接入） |

## 坑点

1. **dart-define 是编译期常量**：运行期/测试不可改写；测试覆盖须走工厂显式参数注入（各 *_factory.dart 预留参数）。
2. **漏注入不报错**：键缺失静默回落 mock/离线桩，极易误判「AI/同步在真跑」——联调前先用 settings 页状态行（describeSyncBackend）核对当前装配。
3. **自定义 AI 模型的 response_format 自动降档**：SLIMCA_AI_MODEL ≠ gpt-4o-mini 时 json_schema→json_object，个别兼容端点不支持信封属预期行为。
4. **出包必须 `cd apps/mobile`**：仓库根执行 `flutter build` 不产 APK（CI 以 working-directory 保证）。
5. **Gradle 镜像顺序敏感**：阿里云镜像（google/central/gradle-plugin 三仓）在前、官方源兜底——2026-11-17 实测 google()/mavenCentral() 直连不稳，勿「顺手清理」镜像配置；Gradle 发行包同理走腾讯镜像。
6. **release 签名暂用 debug key**（app/build.gradle.kts buildTypes.release TODO）——正式上架前必须配置正式签名。
7. 改 core_db 表结构后必须在 packages/core_db 重跑 build_runner（无 build.yaml，默认配置）。

## 相关文档

- AI 装配与降级链路：[core_ai/README.md](core_ai/README.md)
- 同步后端与 SyncConfig：[feature_sync/README.md](feature_sync/README.md)
- 壳层 providers 装配全景：[apps-mobile/README.md](apps-mobile/README.md)
- 云端表结构与 sync RPC：[server-supabase/README.md](server-supabase/README.md)
