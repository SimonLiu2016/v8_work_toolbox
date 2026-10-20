## 1. 导演合同与数据模型体系建设

- [x] 1.1 在 `lib/tools/ai_video_studio/models/` 新增 `drama_director_contract.dart`，定义五维导演决策（`DirectorDecisions`）、动作六步攻防链（`CombatStep` / `CombatGroup` / `CombatDNA`）、剧本场次与节拍（`DramaScene` / `DramaBeat`）以及保护清单（`ProtectedContract` / `ProtectedFact` / `ProtectedUtterance`）
- [x] 1.2 扩展 `lib/tools/ai_video_studio/models/studio_models.dart` 中的 `ShotContinuity`，新增 `dynamicExitState`（支撑脚、速度矢量、未完成动作相位）并兼容旧版本数据解析
- [x] 1.3 扩展 `StudioShot` 与 `StudioEpisode`，挂载五维导演决策对象、所属场次/节拍关联以及保护清单字段，确保 JSON 序列化向后兼容

## 2. AI 约束引擎与专业 System Prompt 模板库移植

- [x] 2.1 在 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` 中新增任务枚举：`novelDramaChapterAdaptation`（单章影视大纲+场次+保护清单提炼）、`scriptBreakdown5D`（五维导演拆镜）、`actionCombatBreakdown`（动作专项编舞拆镜）
- [x] 2.2 移植 Skill 的 `storyboard.md` 五维决策（物理动势、空间光影、光学调度、时间演变、美学质感）至 `scriptBreakdown` 模板库与 Schema 校验器
- [x] 2.3 移植 Skill 的 `action.md` 与 `combat-choreography.md` 动作编舞逻辑，构建 Combat DNA 与 3~4 招连续接力攻击组模板
- [x] 2.4 移植 Skill 的 `screenplay.md` 逻辑，在小说单章提炼模板中建立原著不可变事实（FACT）与基准对白列表（Utterances）的提取规范

## 3. 平台提示词编译器（PromptAssembler）多通道升级

- [x] 3.1 扩展 `lib/tools/ai_video_studio/services/prompt_assembler.dart`，重构摄影机四段式运动描述（起始运动、跟随对象、触发条件、落点动势）
- [x] 3.2 增加即梦 Seedance 专有格式编译器：输出主体定义、多模态时空动作描述及跨片段剪辑接力（Handoff）参数
- [x] 3.3 增加商用视频模型（可灵 / Runway / CogVideo / MiniMax）自然语言提示词编译器，实现动作因果与光影环境的平滑表述
- [x] 3.4 增强六列分镜数据（H3 CSV）与剪映导出逻辑，确保音视频轨道与切镜时间轴对齐

## 4. 视频可执行性自动化审计关口（C01~C09 质检引擎）

- [x] 4.1 新增 `lib/tools/ai_video_studio/services/director_validation_engine.dart`，实现 C01~C09 规则自动化静态检测
- [x] 4.2 实现时长与台词字数比例计算（C06/C04）、空间 180° 轴线与地标突变检测（C05）以及动作攻防因果完整性核验（C03）
- [x] 4.3 提供 `ValidationReport` 结构化报告，区分 `PASS`、`WARNING` 与 `BLOCKING` 级别，提供具体修改建议

## 5. 服务层深度联调与小说导入管线重塑

- [x] 5.1 重构 `lib/tools/ai_video_studio/services/novel_import_task_service.dart`，将单章影视化提炼升级为“IP主库 + 剧本场次Beats + 保护清单”全案导入
- [x] 5.2 升级 `StudioProjectManager`，支持场次（Scene）/ 节拍（Beat）与保护清单的存储、读取与多集更新

## 6. UI 呈现与分镜看板交互升级

- [x] 6.1 升级 `lib/tools/ai_video_studio/ui/novel_task_drawer.dart`，支持展示小说影视化改编提炼出的场次列表与保护对白清单
- [x] 6.2 升级 `lib/tools/ai_video_studio/ui/storyboard_board.dart`，分镜卡片新增“五维导演视图”与“动作编舞因果链”折叠面板，高亮展示切镜动机与 C01~C09 质检警告
- [x] 6.3 升级 `lib/tools/ai_video_studio/ui/delivery_panel.dart`，支持一键切换并复制即梦 Seedance、商用通用 Prompt 与 H3 六列数据

## 7. 自动化构建、部署与全流程验证

- [x] 7.1 编写或更新针对五维决策与攻防链 Schema 解析的单元测试
- [x] 7.2 运行 `./scripts/deploy_local.sh` 编译 Release、签名、比对 AOT md5 并替换本机应用启动
- [x] 7.3 在本机短视频工坊中导入真实小说章节，端到端验证小说解构 → 剧本场次 → 五维分镜 → 平台 Prompt 导出的全闭环效果
