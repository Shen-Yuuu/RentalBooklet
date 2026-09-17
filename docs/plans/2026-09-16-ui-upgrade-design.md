# UI 升级设计（2026-09-16）

## 目标

对 RentalBooklet 前端 UI/布局/组件做整体现代化重构：升级 targetSdk 至 26.0.0（HarmonyOS 7.0），采用 API 26 旗舰特性（悬浮 TabBar）+ API ≤21 现代能力（SymbolGlyph、深色模式、响应式栅格、动效），保持 6.0.1(21) 设备兼容。

## 决策记录

- 策略：**激进升级**——targetSdk 26.0.0，compatibleSdkVersion 保持 6.0.1(21)
- API 26-only 特性按官方兼容指导封装在独立自定义组件中，`deviceInfo.sdkApiVersion >= 26` 运行时分支，21 设备永不实例化新组件
- 风格：**简洁工具风**——品牌蓝 #4A90D9 单强调色、大圆角卡片、细阴影、克制配色
- 顺手修复产品文档"深浅色跟随系统"承诺：补齐 dark/ 资源目录实现真深色模式

## 架构

### 1. 版本与兼容
- build-profile.json5：`targetSdkVersion: "26.0.0"`
- `common/DeviceCapability.ets`：`isApi26Plus`（deviceInfo.sdkApiVersion >= 26）

### 2. 设计令牌
- `resources/base/element/color.json` 语义色：brand、brand_pressed、success、warning、danger、bg_page、bg_card、text_pri/text_sec/text_ter、divider
- `resources/dark/element/color.json` 深色对应
- `common/ui/Theme.ets`：字号/圆角/间距常量、通用 @Builder（卡片容器、状态徽标、chevron 行）

### 3. 底部导航双分支
- API 26+：`Tabs.barFloatingStyle(FloatingTabBarStyle)` 悬浮胶囊 + systemMaterial 毛玻璃
- API <26：常规 Tabs + SymbolGlyph 自定义 tabBar（选中品牌色）
- 两实现独立组件，Index 运行时选择

### 4. SymbolGlyph 图标系统
- Tab（house/doc_text/gearshape）、chevron_right 替代 Text('›')、状态图标（checkmark_seal/timer/camera 等）

### 5. 页面重构（全部替换硬编码色 → 语义令牌）
- HomeTab：卡片阴影+图标、胶囊 CTA、GridRow 平板双列
- RecordsTab：Search 过滤 + SegmentButton 分段筛选 + 状态图标
- SceneSelectPage：场景卡片 SymbolGlyph
- SettingsTab：存储 Progress 进度条、分组卡片
- 其余 11 个页面/组件：令牌替换 + 徽标组件化

### 6. 动效（API 12 springMotion）
- 卡片按压缩放反馈、Tab 内容 TransitionEffect、列表项出现转场

## 验证口径

arkts_check 全量零违例 + assembleHap（26 编译通过）+ hvigor test 131 用例全通过。UI 层无单测；API 26 特性在 21 设备走 legacy 分支。
