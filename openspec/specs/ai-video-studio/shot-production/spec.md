# shot-production Specification

## Purpose

将分镜脚本中的每个分镜与每个片段转化为可视化的关键帧图像和视频，通过任务队列管理批量生成请求，并在角色卡上提供多视角参考图的生成入口以承载跨镜头一致性。

## Requirements

### Requirement: 生图任务队列

系统 SHALL 维护一个本地异步任务队列处理图像生成请求，队列 SHALL 支持以下操作：单镜生成、全集批量生成、重新生成指定分镜。任务 SHALL 显示进度状态（等待中/生成中/完成/失败），失败的任务 SHALL 允许用户手动重试。同时进行的生图 API 并发数 SHALL 可配置（默认 2，可调至 1-5）。

队列 SHALL additionally 支持片段级任务类型，片段级视频任务的并发 SHALL 与生图任务共享同一并发上限配置。

关键帧生成成功后，系统 SHALL 允许用户把该关键帧收进资产库；收进 SHALL 为复制，原分镜产物 SHALL 保持不动。

#### Scenario: 全集批量生图

- **WHEN** 用户在分镜看板点击"批量生成全集关键帧"
- **THEN** 系统 SHALL 将当前集所有未生成关键帧的分镜加入队列并开始处理，用户 SHALL 能在看板上实时看到各分镜的生成进度

#### Scenario: 单镜重新生成

- **WHEN** 用户对已生成关键帧的分镜点击"重新生成"
- **THEN** 系统 SHALL 仅重新生成该分镜的图像，不影响其他分镜已有的生成结果

#### Scenario: 片段级任务在队列中可区分

- **WHEN** 用户提交一个片段视频生成任务和一个分镜关键帧生成任务
- **THEN** 系统 SHALL 在队列面板中以不同图标与标签区分两者，并分别展示各自进度

#### Scenario: 关键帧可收进资产库
- **WHEN** 用户对一个已生成关键帧的分镜触发「收进资产库」
- **THEN** 系统 SHALL 把该关键帧复制进资产库并登记其来源元数据
- **AND** 原分镜的关键帧文件 SHALL 仍然存在并被该分镜继续引用

### Requirement: 差异化动态化策略（图生视频）

系统 SHALL 根据剧集的制作类型选择默认动态化策略：
- `drama`（真人短剧）：默认以**片段**为单元提交图生视频 API，输入为该片段的全部出场角色参考图、场景参考图、片段提示词与目标时长，生成一段覆盖多个分镜的视频
- `anime`（二次元/动态漫）：默认使用 2.5D 本地 Ken Burns 运镜动效（FFmpeg zoompan），免费且即时生成；支持按片段合并为一次生成以减少调用次数
- `narration`（图文解说）：默认使用 Ken Burns 静态推拉动效，不调用任何外部视频生成 API

用户 SHALL 能在单个分镜上手动覆盖默认动态化策略，覆盖后该分镜从所属片段的生成范围移出。

#### Scenario: Drama 类型按片段调用图生视频 API

- **WHEN** 剧集类型为 `drama`，用户已配置可用的视频模型，且对包含 3 个分镜的片段触发视频生成
- **THEN** 系统 SHALL 提交**一次**视频生成请求，请求包含该片段的全部参考图、片段提示词与目标时长，并加入异步队列追踪进度

#### Scenario: Narration 类型按片段合并本地动效

- **WHEN** 剧集类型为 `narration` 且用户对一个包含 3 个分镜的片段触发生成
- **THEN** 系统 SHALL 以该片段的目标时长与首镜关键帧生成一段 Ken Burns 视频，生成耗时 SHALL 不超过 20 秒，不调用任何外部 API

### Requirement: 生成结果预览与确认

系统 SHALL 在分镜看板中以 9:16 竖屏缩略图形式展示已生成的关键帧图像，用户点击后 SHALL 全屏预览。已生成视频片段 SHALL 支持在看板内循环播放预览，用户 SHALL 能在预览状态下直接触发重新生成或标记为"已确认"。

看板 SHALL 提供「按片段」与「按镜头」两种视图；「按片段」视图以片段为可折叠分组，组内展示分镜卡片与片段级媒体预览。

#### Scenario: 按片段视图展示分组与片段媒体

- **WHEN** 用户切换到「按片段」视图
- **THEN** 系统 SHALL 将分镜按所属片段折叠分组，每个片段头部展示目标时长、边界判定理由与片段视频缩略图，展开后展示组内分镜卡片

<!-- 归并自 ai-video-studio 顶层 spec（2026-10-12）。 -->

### Requirement: 中转站 Agnes Image 2.5 Flash 图像生成适配
系统 SHALL 在图像生成适配层按型号自适应支持 Agnes 图像模型（`agnes-image-2.0-flash`、`agnes-image-2.1-flash`、`agnes-image-2.5-flash`）。当使用其中任一型号时，系统 SHALL 发送符合供应商规范的请求体：`size` 使用档位值（1K/2K/3K/4K），`ratio` 使用受支持的宽高比，`extra_body.response_format: "url"`。当分镜关联角色存在定妆参考图时，系统 SHALL 将其作为公共 URL 或 Data URI 传入 `extra_body.image` 数组中。

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

### Requirement: Agnes 视频生成的异步任务适配

系统 SHALL 按 Agnes 视频异步任务生命周期适配 `agnes-video-2.5` 与 `agnes-video-2.5-flash`：创建任务后保存供应商返回的视频标识，按文档推荐方式查询任务（查询请求 SHALL 携带型号名，使首帧与参考模式同样可查），直至状态为完成或失败；完成后从响应的顶层地址取回视频。

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
