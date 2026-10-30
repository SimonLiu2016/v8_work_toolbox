## 1. 数据模型与存储

- [x] 1.1 `models/real_meeting_models.dart`：定义 `RealMeeting`（id、标题、来源路径、总时长、关键词、槽位列表、轮次列表）、`SpeakerSlot`（槽位标识、默认显示名）、`SpeakerSetting`（显示名、音色、是否"我"）、`InsertedAnswer`（锚点轮下标、提问轮下标、身份、英文、中文原文、音频文件名、失效标记）、`MyIdentity`（显示名、音色）
- [x] 1.2 三个模型的 `toJson` / `fromJson`，字段缺失时逐项回落而不是整条丢弃（与 `Clip.fromJson` 同风格）
- [x] 1.3 `services/real_meeting_store.dart`：`meetings/` `settings/` `answers/` 三类文件的原子读写（临时文件 + rename），单个文件损坏返回 null 而不是抛异常
- [x] 1.4 `app_paths.dart` 登记 `realMeetingDir` / `turnsDir` / `vocabularyIndexFile` / `myIdentityFile`，并加入启动时创建的目录清单
- [x] 1.5 覆盖层合并逻辑：`RealMeeting + SpeakerSetting? → 生效的显示名与音色`，删除覆盖层后回落默认值

## 2. 逐字稿解析

- [x] 2.1 `services/transcript_parser.dart`：解析标题、`转写时长`、`关键词` 段、`发言人 N HH:MM:SS` + 正文的轮次序列
- [x] 2.2 NBSP（`U+00A0`）归一化为普通空格——用样例文稿做断言：必须解析出 152 轮、6 个槽位
- [x] 2.3 时间戳单调性校验；倒序或格式异常时报告行号与原因，不进入合成
- [x] 2.4 会议标识派生：来源路径 + 内容哈希；内容未变判定与"更新"分支的入口
- [x] 2.5 单元测试：样例文稿解析、NBSP 变体、时间戳倒序、缺「关键词」段

## 3. 续句分组

- [x] 3.1 `services/continuation_merger.dart`：纯函数 `List<List<int>> groupTurnIndices(List<SpeakerTurn>)`，规则为首字符非大写 ∧ 上一轮不以 `.` `?` `!` 结尾
- [x] 3.2 组内音色取组首轮；组内各轮回填时共享组的起止毫秒
- [x] 3.3 单元测试：样例中 `...during` / `the...I can take` 被合并；`...that's the plan.` / `Okay, next topic.` 不被合并

## 4. 逐轮合成与整篇重建

- [x] 4.1 `services/real_meeting_baker.dart`：按续句组逐组合成，写入 `real_meetings/turns/<id>/t<group>.mp3`（持久目录，不写缓存目录）
- [x] 4.2 移植 `RehearsalBaker` 的四条防线：空音频重试 2 次、HTTP 451 降级到 120 字碎片、HTTP 402 fast-fail、900 字按句切分
- [x] 4.3 单组合成失败写 1200ms 静音占位并标记失败轮，保证后续组时间轴不塌
- [x] 4.4 续跑：已有且非空的 `t<group>.mp3` 直接复用，只补缺失组；进度回调给"已完成组数 / 总组数"
- [x] 4.5 `rebuildAudio(meetingId)`：按"原稿组顺序 + 回答锚点"生成拼接序列 → concat → 逐段探时长 → 重算每轮 `startMs/endMs` → 重建 `Clip` 并写回索引
- [x] 4.6 单元测试：伪 TTS 引擎下——续跑跳过已合成组、插入后时间戳整体后移、删除回答后时间戳复原

## 5. 说话人设定与我的身份

- [x] 5.1 覆盖层的读写接入 UI 状态；改名后只重建 `Clip`（不重新合成）
- [x] 5.2 改音色后只重合成该槽位所属的组，再重建整篇音频
- [x] 5.3 `my_identity.json` 读写，默认 `{name: "我", voiceId: "boyinnansheng"}`（与 `RehearsalVoices` 的 `simon` 同一绑定）
- [x] 5.4 把某槽位标记为"我"：该槽位改用 `MyIdentity` 的显示名与音色
- [x] 5.5 「我的身份」设置入口（全局设置，跨会议恒等）

## 6. 词汇索引

- [x] 6.1 `services/meeting_vocabulary_index.dart`：从会议数据提取词条 → `perMeeting` 与 `postings` 两级结构
- [x] 6.2 分词与归一化：复用 `TermHighlighter` 的词边界正则；归一化为小写、去引号与所有格附缀，同时保留原文形态
- [x] 6.3 内置停用词表（约 100 词）；噪声折叠三条件（语料内 ≤1 次 ∧ 不在停用词 ∧ 不在该会议关键词段）
- [x] 6.4 增量维护：导入加一个 `perMeeting` key，删除会议移除该 key；插入回答默认不计入，可切换
- [x] 6.5 全量重建入口：索引缺失/损坏时从 `meetings/*.json` 重建；测试断言重建结果与增量结果一致
- [x] 6.6 反查 API：词 → `[(meetingId, turnIndex, speaker, startMs, sentence)]`，按会议时间与轮次排序

## 7. 选段回答生成

- [x] 7.1 `services/answer_generator.dart`：复用 `RehearsalTextGenerator` 注入式 LLM 抽象
- [x] 7.2 Prompt 组装：会议标题 + 关键词 + 目标轮之前 N 轮（按 token 预算取窗口）+ 目标轮；超预算时明确告知截断位置
- [x] 7.3 直接生成路径：输出英文回答草稿，禁止编造数字/版本号/人名，信息不足处用 `[待补充: ...]` 占位
- [x] 7.4 中译英路径：中文原文 → 英文译文，两条文本一并返回并都保存
- [x] 7.5 解析与校验：输出为空或明显不是英文时给出可读错误，不把模型废话当回答存下去

## 8. 插入回答

- [x] 8.1 插入动作：合成该段 → 写 `answers/<id>.json` → `rebuildAudio` → 更新索引
- [x] 8.2 编辑回答文本后只重合成该段并重建
- [x] 8.3 重新生成（换一个 AI 版本）与删除回答；删除后重建复原
- [x] 8.4 锚点越界（文稿更新后轮次变少）时把回答标记为失效并在界面提示，不静默删除

## 9. 界面

- [x] 9.1 素材库类型筛选加第三项「真实会议」；`Clip` 的 `scene == realMeeting` 映射到该类型
- [x] 9.2 `ui/real_meeting_import_panel.dart`：文件选择、解析预览（轮次数 / 槽位数 / 时长 / 关键词）、导入与合成进度、续跑与失败轮重试
- [x] 9.3 `ui/real_meeting_practice_page.dart`：逐字稿按轮展示（说话人显示名、术语高亮、点轮跳转）、回答轮标注「我的回答」、选中一轮后出现"提问"操作条
- [x] 9.4 回答面板：两种方式（AI 回答 / 中文→英文）、英文可编辑、中文原文对照展示、插入按钮
- [x] 9.5 `ui/vocabulary_browser_page.dart`：词频列表（停用词开关、噪声分组折叠/展开）、单词详情（分场明细 + 反查句子），点结果跳到该会议该轮播放
- [x] 9.6 播放器对接：长音频按轮 seek（复用既有 `_seekToTurn`），确认 60 分钟音频的进度条与断点记忆正常

## 10. 验证与收尾

- [x] 10.1 用样例文稿 `逐字稿_原文_20261020.md` 端到端跑通：导入 → 改名 → 合成 → 词表 → 查词跳转 → 选段回答 → 插入 → 播放 → 删除回答
- [x] 10.2 界面冒烟：清空缓存后插入回答仍不重新合成既有轮次（D4 的关键约束）
- [x] 10.3 `flutter analyze` 无新增告警；新增测试与既有测试全绿
- [x] 10.4 更新 `openspec/specs/it-meeting-listening-tool/spec.md` 的归档合并说明：与在途 `add-meeting-material-rehearsal` 的「素材库容纳两类内容」合并为三类
