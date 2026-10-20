## Context

详见 `proposal.md`。当前 `V8WorkToolbox` 的 AI 视听引擎在执行剧本与分镜拆解时，存在两处核心结构瓶颈：
1. **代码层粗暴降级**：`ai_constraint_engine.dart` 中的 `convertScenesToShots` 将所有镜头的机位与运镜硬编码为 `'static'`、`'平视定机位'`、`'主体居中'`，抹杀了模型的大脑推理；
2. **提示词规范维度不足**：原剧本拆解 Prompt 缺乏系统化的影视导演视听语言规范（高低视角俯仰、轴线正反打、动势承接与心理距离），导致模型缺乏明确的标准字段指导；
3. **内心独白（OS）声画混淆**：`beat.voiceType == 'inner_voice'` 遗失为普通对白，触发开口嘴型动画；
4. **真人实拍世界观缺失**：预设中无古装仙侠与爆款短剧实拍选项，且制作形态被默认置为 `anime3d`，向负向词注入 `live-action photo`。

## Goals / Non-Goals

**Goals:**
- **建立导演级视听指令体系与多维 Schema**：在小说改编、剧本拆解与单镜提示词中注入专业的影视视听语言维度体系（景别、视角高度俯仰、动态运镜轨迹、空间构图与视线正反打、发声类型）。
- **无损分镜管道透传（Pass-through）**：重构 `convertScenesToShots`，忠实提取并透传 AI 导演的视听决策，严禁代码硬编码覆写。
- **内心独白（OS）声画物理隔离**：全链路保留 `inner_voice` 标识，界面格式化为 `角色（内心 OS）：内容`，生图与生视频提示词装配中强制注入闭口沉思微表情指令，禁绝张嘴对口型。
- **真人影视世界观与制作形态解禁**：新增【真人古装·仙侠影视大片】与【真人爆款·实拍短剧】风格预设；世界观面板开放制作形态切换；装配负向词时对真人实拍形态安全解禁。

**Non-Goals:**
- 不替换底层 AI 图像与视频模型中转接口（Agnes / Seedance）。
- 不实现三维虚拟摄影机交互轨迹绘制编辑器。

## Decisions

### 1. 软件定“视听维度契约”，大模型做“导演语义推理”
- **决策**：彻底放弃在 Dart 代码中靠关键词硬编码（如 `if text.contains('案前')`）的启发式推导，改在 LLM System Prompt 中建立完整的**影视导演视听词典与镜头语法推理规则**（包含大远景到大特写景别体系、高空俯拍到仰角低机位视角、推拉摇移升降手持运镜轨迹、黄金分割与视线正反打匹配规则）。
- **替代方案考虑**：曾考虑在代码中维护复杂的正则与规则匹配引擎。但影视视听语言千变万化，代码穷尽成本极高且极度脆弱，大语言模型才是理解物理空间（楼上与街面、刀锋与格挡）的最优解。

### 2. 重构 `convertScenesToShots` 管道无损透传
- **决策**：修改 `convertScenesToShots` 逻辑，直接读取 `beat.cameraMove`、`beat.cameraStaging`、`beat.screenPosition`、`beat.shotSize`、`beat.gazeDirection`、`beat.voiceType`；仅当字段缺失或为空时提供符合上下文的自适应后备。
- **替代方案考虑**：保留硬编码但增加更多条件分支。被否决，因硬编码严重破坏了分镜的多样性与镜头动感。

### 3. 内心独白（OS）全流程标准化与闭口微表情注入
- **决策**：
  1. 数据流：如果 `beat.voiceType == 'inner_voice'` 或台词包含 `内心 OS`/`心声`，分镜台词统一格式化为 `角色（内心 OS）：台词`；
  2. 提示词装配：`PromptAssembler` 针对包含 `（内心 OS）` 或 `voiceType == 'inner_voice'` 的镜头，在生图提示词中注入闭口凝思、眼神内敛的微表情，在生视频提示词中注入 `画面主体保持自然闭口与从容微表情，严禁开口嘴型与画内文字，镜头展现人物深邃神态`。
- **效果**：解决 AI 视频模型把内心独白误当成张嘴讲话的行业通病。

### 4. 扩充真人影视风格预设与解耦制作形态负向词
- **决策**：
  1. 在 `StudioPresetStore.aestheticStyles` 中新增：
     - `costume_drama_realism`（真人古装·仙侠影视大片）：真实电影级质感、汉服纹理细节、唯美电影布光、真实人脸质感；
     - `live_action_short_drama`（真人爆款·实拍短剧）：现代都市实拍、高对比度商业布光、真实演员质感、清晰面部特写；
  2. 在 `series_page.dart` 的“世界观与风格”配置面板中，增加“制作形态（实拍/3D/2D）”下拉选择；
  3. 在 `PromptAssembler` 中增加守卫：当制作形态为 `live_action` 或所选风格属于实拍电影系列时，严禁向负向词注入 `live-action photo`、`photo` 等真实感封杀词。

## Risks / Trade-offs

- **[Risk 1] 模型输出的运镜或机位术语不规范**  
  → **Mitigation**：在 System Prompt 的 JSON Schema 中给出标准化枚举列表（如 `static`, `push_in`, `pull_out`, `pan_left`, `pan_right`, `tracking`, `crane_up`, `crane_down`, `handheld` 等），并附带中文映射，同时在解析层做容错映射归一化。
- **[Risk 2] 历史存量项目中的制作形态默认为 `anime3d`，切换风格后仍被误伤**  
  → **Mitigation**：在 `PromptAssembler` 中采用“双重判定”：若 `production_type == 'live_action'` **或** 当前所选风格属于真人实拍分类，均视为真人模式，自动剔除真实人脸与摄影负向词。
