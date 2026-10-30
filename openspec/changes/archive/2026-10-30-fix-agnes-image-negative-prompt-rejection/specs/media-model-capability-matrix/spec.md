## MODIFIED Requirements

### Requirement: 模型能力声明
系统 SHALL 为每个已配置的图像与视频模型维护一份能力声明，字段 SHALL 至少包含：支持的生成模式集合、支持的时长集合（视频）、支持的分辨率集合（视频）、支持的画幅比例集合、可接受的参考图数量上限、是否支持首帧、是否支持尾帧、是否支持原生音频、是否支持负向提示词（图像）。

能力声明 SHALL 可按模型 id 覆盖；未声明的模型 SHALL 按其协议类型取一组保守默认值，而不是使用适配器内写死的常量。

能力声明 SHALL 描述模型真实可达的能力。当适配器尚未实现某项声明的能力时，该字段 SHALL 保持为不支持，直到适配器能够实际提交对应参数为止；SHALL NOT 以「模型文档说支持」为由声明一个没有任何代码路径可达的能力。

`是否支持原生音频` SHALL 描述模型输出是否带原生音轨，SHALL NOT 用于描述模型是否接受音频参考输入——后者属于生成模式与参考媒体数量的范畴。

`是否支持负向提示词` SHALL 描述图像模型是否接受负向提示词（`negative_prompt`）参数。当模型显式不支持负向提示词时，适配器在向其服务提交文生图或图生图请求时 SHALL NOT 携带 `negative_prompt` 字段。

#### Scenario: 视频模型声明时长与分辨率

- **WHEN** 某供应商配置了视频模型 `seedance-2.0`
- **THEN** 系统能读出该模型支持的时长集合与每个时长可用的分辨率集合，用于请求前的规整

#### Scenario: 未声明模型有保守默认

- **WHEN** 用户配置了一个系统未内置能力声明的视频模型
- **THEN** 系统取该协议类型的保守默认（如最短时长、最低分辨率、单一参考图），并在能力展示处标注为「默认能力，未经确认」

#### Scenario: 同族型号按限制分档

- **WHEN** 某供应商同时提供标准型号与受限型号（如固定分辨率档位、不支持参考视频、参考图数量上限更低）
- **THEN** 受限型号 SHALL 命中其独立声明
- **AND** 系统 MUST NOT 对两个型号套用同一组能力参数

#### Scenario: 图像型号不继承视频能力

- **WHEN** 系统查询某个图像型号的能力声明
- **THEN** 所得声明 SHALL 描述图像模型的尺寸档位与宽高比
- **AND** MUST NOT 返回视频模型的时长、生成模式或参考媒体限制

#### Scenario: Agnes 视频型号的尾帧能力

- **WHEN** 系统为 `agnes-video-2.5` 或 `agnes-video-2.5-flash` 解析能力声明
- **THEN** 声明 SHALL 标记支持尾帧，且视频适配器 SHALL 实际能够提交尾帧参数

#### Scenario: Flash 型号的分辨率档位

- **WHEN** 系统为 `agnes-video-2.5-flash` 解析能力声明
- **THEN** 声明 SHALL 仅包含 `720P` 一档，而 `agnes-video-2.5` SHALL 包含 `720P` / `1080P` / `1K` / `2K` 四档

#### Scenario: 音频参考能力与原生音频输出分离

- **WHEN** 系统为某个接受音频参考输入但不输出音轨的模型解析能力声明
- **THEN** 原生音频字段 SHALL 为不支持，而参考媒体的接受能力 SHALL 由生成模式与参考数量上限表达

#### Scenario: Agnes 图像型号不支持负向提示词

- **WHEN** 系统为 `agnes-image-2.0-flash`、`agnes-image-2.1-flash` 或 `agnes-image-2.5-flash` 解析能力声明
- **THEN** 声明 SHALL 标记 `supportsNegativePrompt: false`
- **AND** 适配器在构建请求体时 SHALL 剔除 `negative_prompt`，避免触发上游队列字段非法错误 (HTTP 400)
