## 1. 统一工坊提示词模板存储与数据模型

- [x] 1.1 在 `AppPaths` 注册 `promptTemplatesFile`，并在 `studio_models.dart` 中定义 `StudioPromptTemplate` 与 `StudioImageDimensionPreset` 数据模型。
- [x] 1.2 在 `StudioPresetStore` 中扩展提示词模板的加载、出厂 5 大内置模板自愈、用户覆盖持久化与全局 Stream 广播。
- [x] 1.3 编写 `StudioPresetStore` 提示词模板出厂自愈与修改持久化单元测试。

## 2. 系统提示词动态化、全年龄骨骼自适应与体态解绑

- [x] 2.1 重构 `CharacterTurnaroundPrompt`，移除对“身材修长挺拔”的硬编码绑架，改为动态从 `StudioPresetStore` 读取三视图排版模板。
- [x] 2.2 在 `PromptAssembler` 中升级全年龄段（幼童/少年/青年/中年/老年）纯中文骨骼身量自适应解析器，对少年阶段注入“接近成人的半成熟骨架，骨骼正在拔高抽条，非低幼儿童”的强力防低幼约束，阻断余小白等角色退化为幼童。
- [x] 2.3 重构 `ScenePromptBuilder`、`PropPromptBuilder` 与 `AiConstraintEngine`，从 Dart 静态硬编码常量切换为从 `StudioPresetStore` 动态加载模板。
- [x] 2.4 编写全年龄骨骼自适应解析器与微胖/矮壮体态语义保护的针对性单元测试。

## 3. 预设管理中心（UI）扩展系统提示词标签页

- [x] 3.1 改造 `StudioPresetManagementDialog`，增加第三个 Tab「系统提示词与规则」。
- [x] 3.2 交付分类导航（资产生成规范、导演调度规范）、多行文本编辑器、出厂默认对比与「保存生效」能力。
- [x] 3.3 交付单项与全局「恢复出厂默认」功能，提供即时状态重置、持久化与轻量级提示。

## 4. 场景图 16:9 纠偏与 IP 主库全局生图规格控制

- [x] 4.1 封装通用的 `ImageDimensionSelector` 下拉规格组件，枚举 1K~4K 分辨率档位与 16:9/9:16/1:1/4:3/21:9 宽高比，并直通映射 Agnes 尺寸规范。
- [x] 4.2 修复 `series_page.dart` 中场景单视角生成与 7 方位空间批量生图漏传宽高参数的缺陷，默认绑定 2K · 16:9 宽画幅。
- [x] 4.3 在角色三视图操作栏、场景视角编辑栏与道具卡生成区挂载 `ImageDimensionSelector`，支持创作者手动自由指定生图规格。

## 5. 全局回归测试与本地发布

- [x] 5.1 运行角色三视图、年龄守卫、道具与场景生图相关的所有单元测试套件，确保全部通过。
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 重新构建并替换本地 `/Applications/V8WorkToolbox.app`，验证 AOT md5 一致性。
