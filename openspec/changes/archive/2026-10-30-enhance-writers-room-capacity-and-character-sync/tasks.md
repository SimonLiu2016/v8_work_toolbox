## 1. 约束引擎契约与提示词升级 (AiConstraintEngine)

- [x] 1.1 扩展 `_promptWritersRoomMasterExtract` 提示词与 JSON Schema，加入推荐集数、推荐理由、核心角色列表与网状人物关系定义
- [x] 1.2 增强 `_SchemaValidators.writersRoomMasterExtract` 校验与归一化逻辑，兼容推荐集数智能兜底、角色列表解析与关系矩阵规范化
- [x] 1.3 强化 `_promptWritersRoomSeasonBeats` 提示词，支持 60~100+ 集长剧宏观节拍与断章悬念规划
- [x] 1.4 编写或更新单元测试，验证 Schema 校验器对推荐集数、角色设定及关系图谱的解析与自愈能力

## 2. 编剧研讨室界面与集数交互重构 (WritersRoomDialog)

- [x] 2.1 移除硬编码的 30 集上限，重构篇章控制栏的集数交互（支持 AI 推荐集数标签一键采纳、常用档位切换及自定义集数弹窗输入）
- [x] 2.2 在研讨室分析结果区新增「角色谱系与关系矩阵」可视化卡片组件，直观展示角色定位、性格特质、外貌描述与人物关系张力
- [x] 2.3 更新状态管理与大纲规划触发逻辑，确保选定或自定义任意集数后能无缝重新驱动大纲规划

## 3. 角色一键沉淀至 IP 资产库与联动 (CharacterCard Sync)

- [x] 3.1 在 `WritersRoomDialog` 中实现角色同步至 IP 库方法 `_syncCharactersToIpLibrary`，包含同名角色安全合并与已有视觉资产保护逻辑
- [x] 3.2 在研讨室操作区域与分集定稿流程中提供「同步角色至 IP 库」操作入口与操作反馈
- [x] 3.3 编写测试验证角色卡正确持久化到剧集 IP 目录，确保不覆盖原有参考图并正确补全性格与 Prompt

## 4. 全流程验证与本地应用构建部署

- [x] 4.1 运行相关单元测试确保全部用例通过
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证功能在真实 macOS 环境中正常生效
