## MODIFIED Requirements

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
