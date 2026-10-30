## ADDED Requirements

### Requirement: 道具资产卡接入分镜出场与参考解析
道具资产卡（`PropCard`）SHALL 提供标准的素材候选枚举接口，枚举器（`AssetMaterialEnumerator.forProp`）SHALL 列出道具目录下所有磁盘真实存在的参考图文件。

系统 SHALL 保证分镜中引用的 `propId` 与 IP 资产库中的道具卡保持联动；当道具卡被删除时，分镜出场资产列表中 SHALL 容错展示或自动清理失效的绑定。

#### Scenario: 枚举道具参考图候选
- **WHEN** 用户在分镜资产行选择道具素材下拉列表
- **THEN** 系统 SHALL 枚举该道具目录下真实存在的全部参考图，若存在多张则按上传/生成顺序清晰列出

#### Scenario: 引用不存在的道具时容错
- **WHEN** 分镜数据中包含已被删除的道具 id
- **THEN** 系统 SHALL 友好标记为失效道具或跳过该素材，MUST NOT 导致分镜看板加载中断或崩溃
