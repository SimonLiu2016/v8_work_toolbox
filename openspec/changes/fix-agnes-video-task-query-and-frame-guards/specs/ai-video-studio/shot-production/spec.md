## MODIFIED Requirements

### Requirement: Agnes 视频生成的异步任务适配

系统 SHALL 按 Agnes 视频异步任务生命周期适配 `agnes-video-2.5` 与 `agnes-video-2.5-flash`：创建任务后保存供应商返回的视频标识，按文档推荐方式查询任务（查询请求 SHALL 携带型号名，使首帧与参考模式同样可查），直至状态为完成或失败；完成后从响应的顶层地址取回视频。

轮询 SHALL 遵守 capability `async-video-task-ledger`：创建成功即持久化台账、重启后不重复创建、超时不放弃、错误按可重试性分类。

系统 SHALL 在解析查询响应前甄别该响应是否为错误体；供应商以 HTTP 200 返回错误码时，系统 MUST NOT 将其当作任务状态继续轮询。阶段切换 SHALL 依据响应中表示处理开始的时间戳字段，而不是状态字符串的枚举匹配。查询地址 SHALL 从主查询路径的顶层字段读取；使用兜底查询路径时 SHALL 按其自身的响应形态读取地址字段。

系统在提交图生视频请求前 SHALL 校验首帧尺寸满足供应商下限，不满足时给出指明"关键帧尺寸过小"的错误。

#### Scenario: 按推荐方式查询 Agnes 视频任务
- **WHEN** 系统轮询一个已创建的首帧模式 Agnes 视频任务
- **THEN** 查询请求 SHALL 携带型号名
- **AND** 系统 SHALL 以响应中的对外状态字段与顶层视频地址判定完成并取回产物

#### Scenario: 限流错误体不被当作任务状态
- **WHEN** 查询返回携带限流错误码的响应体
- **THEN** 系统 SHALL 识别其为限流错误并退避
- **AND** MUST NOT 依据该响应更新进度或阶段

#### Scenario: 阶段切换以开始时间戳为准
- **WHEN** 查询响应中表示处理开始的时间戳由空值变为非空
- **THEN** 系统 SHALL 把该任务从排队阶段切到生成阶段
- **AND** 切换 MUST NOT 依赖状态字符串是否等于某个特定值

#### Scenario: 过小首帧被本地拒绝
- **WHEN** 用户提交的关键帧边长小于供应商下限
- **THEN** 系统 SHALL 在本地拒绝并说明关键帧尺寸过小
- **AND** MUST NOT 把指向 `first_frame` 参数的供应商错误透出给用户

#### Scenario: Flash 型号固定 720P 且不含参考视频
- **WHEN** 系统为 `agnes-video-2.5-flash` 组装视频生成请求
- **THEN** 输出分辨率档位 SHALL 固定为 720P
- **AND** 请求 MUST NOT 包含参考视频内容

#### Scenario: 任务标识在创建后即被记录
- **WHEN** Agnes 视频任务创建成功
- **THEN** 系统 SHALL 在开始轮询前把视频标识写入台账
- **AND** 应用重启后 SHALL 依据该标识继续轮询而不重新创建任务

### Requirement: 中转站 Agnes Image 2.5 Flash 图像生成适配
系统 SHALL 在图像生成适配层按型号自适应支持 Agnes 图像模型（`agnes-image-2.0-flash`、`agnes-image-2.1-flash`、`agnes-image-2.5-flash`）。当使用其中任一型号时，系统 SHALL 发送符合供应商规范的请求体：`size` 使用档位值（1K/2K/3K/4K），`ratio` 使用受支持的宽高比，`extra_body.response_format: "url"`。当分镜关联角色存在定妆参考图时，系统 SHALL 将其作为公共 URL 或 Data URI 传入 `extra_body.image` 数组中。

该适配 SHALL 依据型号的能力声明选择尺寸与宽高比，而不是对所有 Agnes 型号套用同一组参数。Agnes 图像模型的能力 SHALL 与 Agnes 视频模型分开声明，MUST NOT 共用一份声明。

#### Scenario: 成功调用 Agnes Image 生成关键帧
- **WHEN** 任务队列执行关键帧生图任务且当前系统图像模型为任一 Agnes 图像型号
- **THEN** 系统向 `/v1/images/generations` 发送包含档位式 size 与 ratio 的请求，成功下载返回的图片 URL 并保存为本地分镜首帧图片

#### Scenario: 图像与视频能力分别声明
- **WHEN** 系统查询某个 Agnes 图像型号的能力声明
- **THEN** 所得声明 SHALL 描述图像模型的尺寸与宽高比能力
- **AND** MUST NOT 返回 Agnes 视频模型的时长、模式或参考媒体限制
