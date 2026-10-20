## MODIFIED Requirements

### Requirement: 中转站 Agnes Image 2.5 Flash 图像生成适配
系统 SHALL 在图像生成适配层按型号自适应支持 Agnes 图像模型（`agnes-image-2.0-flash`、`agnes-image-2.1-flash`、`agnes-image-2.5-flash`）。当使用其中任一型号时，系统 SHALL 发送符合供应商规范的请求体：`size` 使用档位值（1K/2K/3K/4K），`ratio` 使用受支持的宽高比，`extra_body.response_format: "url"`。当分镜关联一个或多个角色时，系统 SHALL 将该分镜关联的所有角色的定妆参考图作为公共 URL 或 Data URI 传入 `extra_body.image` 数组中，并在构图提示词中分别声明主客体方位与互动关系，严禁只截取第一位角色而丢失配角。

该适配 SHALL 依据型号的能力声明选择尺寸与宽高比，而不是对所有 Agnes 型号套用同一组参数。Agnes 图像模型的能力 SHALL 与 Agnes 视频模型分开声明，MUST NOT 共用一份声明。

图像生成 SHALL 在调用记录中留痕，即使该接口为同步形态、不返回任务标识。

#### Scenario: 成功调用 Agnes Image 生成关键帧
- **WHEN** 任务队列执行关键帧生图任务且当前系统图像模型为任一 Agnes 图像型号
- **THEN** 系统向 `/v1/images/generations` 发送包含档位式 size 与 ratio 的请求，成功下载返回的图片 URL 并保存为本地分镜首帧图片

#### Scenario: 同步生图也留调用记录
- **WHEN** 用户通过 Agnes 图像接口生成关键帧
- **THEN** 系统 SHALL 记录该次调用，其远端任务标识为空
- **AND** 记录 SHALL 含供应商标识、型号、提示词与产出路径

#### Scenario: 图像与视频能力分别声明
- **WHEN** 系统查询某个 Agnes 图像型号的能力声明
- **THEN** 所得声明 SHALL 描述图像模型的尺寸与宽高比能力
- **AND** MUST NOT 返回 Agnes 视频模型的时长、模式或参考媒体限制

#### Scenario: 多角色同框注入全部参考图
- **WHEN** 某分镜同时关联"姜七夜"与"余小白"两位角色执行关键帧生图
- **THEN** 系统发送的生图请求体 `extra_body.image` SHALL 同时包含两位角色的参考图 URL/DataURI
- **AND** 生图提示词中明确描述两位角色的主次构图与前后空间位置关系

### Requirement: Agnes 视频生成的异步任务适配

系统 SHALL 按 Agnes 视频异步任务生命周期适配 `agnes-video-2.5` 与 `agnes-video-2.5-flash`：创建任务后保存供应商返回的视频标识，按文档推荐方式查询任务（查询请求 SHALL 携带型号名，使首帧与参考模式同样可查），直至状态为完成或失败；完成后从响应的顶层地址取回视频。

系统提交视频生成请求时，视频提示词（`prompt`）SHALL 包含完整的角色发声指令与台词对白文本、五维运镜动量与环境光影，严禁使用纯英文无声图像生图词覆盖对白提示词。请求中的视频时长（`duration`）SHALL 根据分镜规划时长在 4 至 12 秒之间动态传递，不得无差别钳制在 4 秒。

轮询 SHALL 遵守 capability `async-video-task-ledger`：创建成功即持久化台账、重启后不重复创建、超时不放弃、错误按可重试性分类。

规整请求参数时，系统 SHALL 依据型号分档：`agnes-video-2.5-flash` 的输出分辨率档位 SHALL 固定为 720P，且 SHALL NOT 提交参考视频；`agnes-video-2.5` SHALL 支持 720P/1080P/1K/2K 与首尾帧。

#### Scenario: 按推荐方式查询 Agnes 视频任务
- **WHEN** 系统轮询一个已创建的首帧模式 Agnes 视频任务
- **THEN** 查询请求 SHALL 携带型号名
- **AND** 系统 SHALL 以响应中的对外状态字段与顶层视频地址判定完成并取回产物

#### Scenario: Flash 型号固定 720P 且不含参考视频
- **WHEN** 系统为 `agnes-video-2.5-flash` 组装视频生成请求
- **THEN** 输出分辨率档位 SHALL 固定为 720P
- **AND** 请求 MUST NOT 包含参考视频内容

#### Scenario: 任务标识在创建后即被记录
- **WHEN** Agnes 视频任务创建成功
- **THEN** 系统 SHALL 在开始轮询前把视频标识写入台账
- **AND** 应用重启后 SHALL 依据该标识继续轮询而不重新创建任务

#### Scenario: 视频生成携带台词发声指令与动态时长
- **WHEN** 系统为包含台词"余小白，我迟早得叫你姐夫"且预估时长为 6 秒的分镜发起视频生成
- **THEN** 提交至 Agnes 的请求 prompt SHALL 包含明确的角色发声与台词标记（如 `[台词]: 姜七夜说道：“余小白，我迟早得叫你姐夫”`）
- **AND** 请求体中的时长参数为 6 秒

## ADDED Requirements

### Requirement: 视频生成提示词声画全要素组装规范

系统 SHALL 在分镜视频生成前执行专门的声画全要素 Prompt 组装。组装结构 SHALL 严格遵循：
1. 【环境与光影】：继承五维决策中的光源方位、色温与环境质感；
2. 【画面动势与微动作】：具象化角色的起止物理动作，标注动作速度与受力变化；
3. 【摄影运镜轨迹】：包含推拉摇移、仰俯视角及焦点转移过程；
4. 【角色台词发声指令】：当分镜包含台词时，显式注明说话人姓名、说话语气口吻（如戏谑、咆哮、轻声呢喃）以及标准加引号的完整台词文本，以引导原生多模态视频大模型同步生成唇形口型与对白声音。

#### Scenario: 视频提示词包含对白发声与运镜全要素
- **WHEN** 系统为分镜组装视频生成提示词
- **THEN** 最终送入视频大模型的提示词中同时包含画面动作、摄影运镜轨迹与带角色标签的对白发声指令，未发生要素缺失
