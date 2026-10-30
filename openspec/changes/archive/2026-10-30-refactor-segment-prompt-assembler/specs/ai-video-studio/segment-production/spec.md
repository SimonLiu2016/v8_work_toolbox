## MODIFIED Requirements

### Requirement: 片段提示词组装

系统 SHALL 为每个片段组装一份高保真且无冲突的视频提示词。该提示词 SHALL 包含：已去重且无冲突的美学画质基线、单一物理主场景描述、出场角色的视觉锚点与规范的素材占位符 `<Picture N>`、按自然叙事流整合的分镜动作描述，以及与分镜调度一致的机位动态。

系统在组装片段提示词时 SHALL 遵守以下规则：
1. **官方素材指代规范**：参考图引用必须采用 `<Picture N>` 格式，SHALL NOT 使用 `{{ref N}}` 等非官方标记；引用编号必须与片段实际上传的媒体列表顺序一一对应。
2. **纯视觉画面指令脱敏**：提示词中 SHALL NOT 包含对白台词（如 `dialogue: ...`）、剧本镜号前缀（如 `shot N |`）、机位代码标头（如 `camera:`）或管道符分割符，台词由配音/TTS 管线处理。
3. **主场景锁定与空镜排他词过滤**：每个片段仅绑定单一主物理场景，SHALL NOT 并列堆叠多个异地场景；当片段存在出场角色时，系统 SHALL 自动过滤场景提示词中的 `empty room`、`no humans`、`unoccupied`、`nobody` 等空镜头排他词。
4. **语义短语去重与冲突排除**：系统 SHALL 对画质基线词与风格词进行短语级去重，SHALL NOT 连续重复堆砌相同句式，且 SHALL NOT 在同一提示词中同时声明冲突的渲染管线（如同时声明 UE5 与 Octane）。
5. **参数与运镜协调**：提示词中 SHALL NOT 出现 `total duration Xs` 等重复描述 API 参数的文本；当分镜自身设定了明确运镜时，系统 SHALL 屏蔽全局默认的激进运镜，以分镜实际运镜为准。

#### Scenario: 片段提示词包含真实参考图编号

- **WHEN** 某片段出场角色「林宁」与场景「雨夜巷道」，且两者均有参考图
- **THEN** 系统生成的片段提示词 SHALL 以 `<Picture 1>`、`<Picture 2>` 形式指代这两张图，并分别标注用途，且引用顺序与实际传入生成接口的参考图顺序一致

#### Scenario: 缺少参考图时不静默降级

- **WHEN** 某片段出场的角色没有基准参考图
- **THEN** 系统 SHALL 在片段上标记「缺参考图」并阻止该片段的视频生成，同时提示用户先为该角色生成参考图，而不是以无参考模式提交生成

#### Scenario: 自动过滤空镜排他词与台词

- **WHEN** 某片段出场角色且其场景提示词中包含 `empty room, architectural interior, no humans`，且分镜包含台词 `dialogue: 站住！`
- **THEN** 系统生成的片段提示词中 SHALL 剔除 `no humans` 与 `empty room`
- **AND** 提示词中 SHALL NOT 包含 `dialogue: 站住！` 或任何带有 `dialogue:` 前缀的内容

#### Scenario: 短语级智能去重

- **WHEN** 剧集风格词与制作类型默认画质词存在重复的风格短语（如均包含 `Unreal Engine 5 render, cinematic lighting`）
- **THEN** 系统在组装提示词时 SHALL 自动合并去重，每个独立风格短语在最终提示词中仅出现一次
