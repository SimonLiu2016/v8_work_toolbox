## MODIFIED Requirements

### Requirement: Studio Engine Selection Persistence
系统 SHALL 持久化存储用户在工坊设置对话框中选择的图像生成与视频生成引擎偏好。视频引擎的可选项 SHALL 包含 Dola 免费号池的各型号。

#### Scenario: Reopening studio settings dialog
- **WHEN** 用户在工坊设置中将视频引擎从跟随系统切换为 Dola 免费号池并关闭弹窗
- **THEN** 再次打开该设置弹窗或重新进入分镜看板时，选中的引擎依然为 Dola 免费号池

#### Scenario: Dola 号池出现在可选项里
- **WHEN** 用户打开工坊设置的视频引擎下拉
- **THEN** 列表中包含 Dola 免费号池的型号选项，而不只有跟随系统、本地动效与可灵

### Requirement: Standard VideoGenAdapter Contract Compliance
The Dola video generation adapter SHALL comply with the standard `VideoGenAdapter` contract and declare its model capabilities through the media capability matrix rather than hard-coded clamps. The adapter's internal fallback SHALL agree with the matrix's intent for the same request.

Capability declarations SHALL distinguish between the two Dola model versions, because their legal duration sets differ:

- `seedance-2.5`：合法时长为 5 / 10 秒。上游另支持 30 秒，但该档位需要两段 15 秒拼接，适配器尚未实现，因此暂不声明
- `seedance-2.0`：合法时长为 5 / 10 / 15 秒

The adapter SHALL NOT declare a single duration set for both versions, and SHALL NOT clip a request into a value the upstream would reject.

#### Scenario: Generate video with keyframe and prompt
- **WHEN** AI 视频工坊向适配器传入首帧图片、分镜提示词与生成时长（如 10 秒）
- **THEN** 适配器自动调度可用账号提交请求，以 3~5 秒周期轮询上游状态，并在成功后下载成片至指定目标路径并返回 File 对象

#### Scenario: Task cancellation during polling
- **WHEN** 用户在工坊队列中主动取消正在轮询的 Dola 视频任务
- **THEN** 适配器立刻中断轮询循环，释放当前任务占用的账号资源并向调用方抛出取消异常

#### Scenario: Adapter fallback agrees with the matrix
- **WHEN** the same duration request is submitted both directly to the adapter and through the factory (which applies matrix normalization)
- **THEN** both paths produce the same submitted duration

#### Scenario: Model versions have distinct duration sets
- **WHEN** the system looks up capabilities for `dola-pool-seedance-2.5` and for `dola-pool-seedance-2.0`
- **THEN** the two legal duration sets differ, and neither contains a value the upstream rejects

#### Scenario: Request for an unsupported duration is snapped
- **WHEN** a user requests 8 seconds on a model whose legal set is 5 / 10 / 15
- **THEN** the adapter submits 5 seconds (the largest legal value not exceeding the request) and records the snap
