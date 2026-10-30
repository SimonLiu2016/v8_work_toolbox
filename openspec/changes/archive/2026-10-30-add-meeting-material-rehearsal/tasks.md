## 1. 数据模型与音色表

- [x] 1.1 `MeetingScene` 新增枚举值 `rehearsal('rehearsal', '排练会议', 'Rehearsal Meeting')`
- [x] 1.2 新建 `models/rehearsal_models.dart`：`RehearsalMaterial`（id、标题、原始路径、解析后文本、导入时间）、`SpeechDraft`（id、材料 id、标题、节列表）、`DraftSection`（标题、正文）、`MeetingScript`（id、材料 id、讲稿 id、场次标题、轮次列表、目标时长）、`ScriptTurn`（说话角色、台词）、`RehearsalRole` 枚举（simon/xiaofeng/songyang/deepan/josh）
- [x] 1.3 新建 `services/rehearsal_voices.dart`：5 角色 → 男声音色硬编码表（从 6 个男声取 5 个，留 1 个备用）；含"全部为男声、音色互不相同、跨会议一致"的注释说明
- [x] 1.4 `app_paths.dart` 登记：排练会议目录 `itMeetingRehearsalDir`、材料缓存目录 `itMeetingMaterialDir`

## 2. 材料导入

- [x] 2.1 新建 `services/material_importer.dart`：`file_picker` 选文件 → 按扩展名分流 `.md` 走 `DocumentParser._parseMarkdown`、`.html` 走 `htmlToMarkdown` 后再解析 → 产出 `RehearsalMaterial`
- [x] 2.2 拒绝非 MD/HTML 扩展名，提示"仅支持 MD 与 HTML 材料"
- [x] 2.3 解析结果为空（无有效文字）时提示"材料内容为空"，不进入待生成状态
- [x] 2.4 记录原始文件路径与文件名到 `RehearsalMaterial` 供出处展示
- [x] 2.5 补测试：MD 导入、HTML 导入、不支持格式被拒、空内容被拒

## 3. 汇报讲稿生成

- [x] 3.1 新建 `services/speech_draft_generator.dart`：调应用 `text` 槽位，prompt 要求"Simon 第一人称英文会议发言稿，按议题分节，口语化，保留材料中的技术名词/数据/客户名，信息不足处用 `[待补充: ...]` 占位，禁止编造"
- [x] 3.2 解析 LLM 输出为 `SpeechDraft`（分节结构）
- [x] 3.3 讲稿落盘（JSON）并可在界面查看/编辑
- [x] 3.4 补测试：给定材料 stub，断言讲稿分节、术语保留、占位标记出现

## 4. 模拟会议剧本生成

- [x] 4.1 新建 `services/meeting_script_generator.dart`：调应用 `text` 槽位，输入「材料 + 讲稿」，prompt 要求 5 角色四段结构（开场/议题推进/Q&A/收尾）、客户方追问质疑、Huawei 侧补充协作、Simon 回应推进、目标轮次区间（先按 120-150 轮，实现时实测校准）
- [x] 4.2 解析 LLM 输出为 `MeetingScript`（每轮含角色与台词）
- [x] 4.3 剧本落盘（JSON）并可在界面查看
- [x] 4.4 生成后按语速折算总时长，偏离 30-60 分钟区间时提示用户（不阻断）
- [x] 4.5 补测试：给定讲稿 stub，断言 5 角色都出现、四段结构覆盖、轮次数量级合理

## 5. 排练语音合成

- [x] 5.1 新建 `services/rehearsal_baker.dart`：逐回合按角色音色合成，**复用 ClipBaker 的四道防线**（空音频重试、内容审查 120 字降级、配额 fast-fail、超长切分）
- [x] 5.2 所有回合音频按序 ffmpeg concat 为一条整场 mp3，回合起止时间由各小节时长累加
- [x] 5.3 单回合失败标记并可单独重试，不毁掉整场
- [x] 5.4 讲稿语音：按节合成，Simon 固定音色，节与音频小节一一对应
- [x] 5.5 补测试：注入假 TTS 引擎，断言轮次顺序、音色按角色分配、失败轮次被标记、拼接调用发生（会议 + 讲稿两组）

## 6. 播放与界面

- [x] 6.1 素材索引支持 `sourceId: 'rehearsal'` 条目（既有 CoderSlingo 素材共存）
- [x] 6.2 素材列表区分「导入的听力素材」与「排练会议」，支持按类型筛选
- [x] 6.3 精听面板展开时，排练会议每轮显示角色名（Simon:/xiaofeng:…）
- [x] 6.4 支持按回合定位：点击剧本某一轮 → 从该轮 startMs 播放
- [x] 6.5 新增材料导入 UI：选择文件 → 生成讲稿 → 生成剧本 → 合成语音，四步进度可见
- [x] 6.6 新增排练会议列表面板：场次、时长、角色数、生成状态
- [x] 6.7 补 widget 测试：材料导入面板、排练列表、按回合定位

## 7. 验收

- [ ] 7.1 端到端：导入一份真实 MD 材料 → 生成讲稿 → 生成剧本 → 合成语音 → 整场可播（由 `redesign-listening-practice-layout` 任务 12.3 验收覆盖）
  - 需用户在部署后的应用里跑（要真实 text/tts 槽位与配额）
- [ ] 7.2 讲稿为英文、分节、保留材料术语，无编造数据（由 `redesign-listening-practice-layout` 任务 12.3 验收覆盖）
  - 分节与术语保留已由 `rehearsal_generators_test.dart` 断言；真实材料的英文质量需用户确认
- [ ] 7.3 剧本 5 角色齐全、四段结构、客户方有追问、时长落在 30-60 分钟区间（由 `redesign-listening-practice-layout` 任务 12.3 验收覆盖）
  - 结构已由 `rehearsal_generators_test.dart` 断言；真实时长需实测 LLM 输出后校准轮次目标
- [x] 7.4 5 角色音色互不相同且跨会议一致
  - 已由 `rehearsal_baker_test.dart`「5 角色音色互不相同」断言；
  - 跨会议一致由 `rehearsal_voices.dart` 的常量表保证（编译期固定，无运行时分配）
- [ ] 7.5 按回合定位准确（点第 N 轮从第 N 轮音频位置起播）（由 `redesign-listening-practice-layout` 任务 12.5 验收覆盖）
  - 时间戳累加逻辑已由 `rehearsal_baker_test.dart` 断言（含失败轮次静音占位不错位）；
  - 真实音频上的听感确认需用户操作
- [ ] 7.6 悬浮窗/热键/断点/变速在排练会议上与既有素材表现一致（由 `redesign-listening-practice-layout` 任务 12.6 验收覆盖）
  - 排练会议走同一条 `Clip` 索引与同一个 `ListeningPlayerController`，外壳零改动；
  - 实际表现需用户在部署后的应用里确认
- [x] 7.7 单回合合成失败可重试，不毁整场
  - 已由 `rehearsal_baker_test.dart`「配额 fast-fail」与「空音频算失败并重试」断言；
  - 失败轮次带静音占位，后续轮次 startMs 不错位（同文件断言）
- [x] 7.8 全量测试回归（注意仓库既有环境依赖型失败）
  - 145 项离线测试全绿（`test/it_meeting_listening/` 除 acceptance/bulk_bake/full_bake/pilot_bake
    四个走真实站点 + 真实 TTS 的验收文件外，加 `test/app_paths_test.dart`）
  - 四个真实管线验收文件需联网与配额，属既有运行方式，不由本次改动引入
