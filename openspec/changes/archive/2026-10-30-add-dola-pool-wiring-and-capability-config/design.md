## Context

三个已定位的事实：

1. `DolaAccountPoolPanel` 在 `lib/` 下零引用；`DolaAccountStore.init()` 无生产调用；工坊设置的 `_enginesFor()` video 分支只有 `system-video` / `local-kenburns-ffmpeg` / `kling-i2v`。
2. Dola 的能力查找链是硬编码的：`_wrap(dolaAdapter, dolaAdapter.id)` 不传 provider → `resolve(provider: null, id)` → `forModel()` → 常量。它**没有**用户配置层，而 SenseAudio / Agnes 有（`AiProviderConfig.mediaCapabilities`，存在 `ai_config.json`，AI 配置页可编辑）。
3. `WindowServices.required` 的注释明确要求"新增平台级单例时必须更新对应窗口的条目"，漏一项的症状正是"该功能在子窗口里静默失效"——与用户报告的"找不到功能"同类。

`004ea27` 那份能力声明的错误根源：把「我们的适配器没实现图片上传」读成「Dola 不支持参考图」。上游 `dola-pool2/README.md` 与 `protocol/dola_pure_api.py:1336-1400` 证明两个型号都支持参考图（上游上限 10 张），`seedance-2.5` 时长是 5/10/30。

## Goals / Non-Goals

**Goals**

- 让号池能被打开、被选中、被调度
- 让能力矩阵不再对 Dola 说谎
- 让号池能力可配，且配置优先于内置预设

**Non-Goals**

- 不实现参考图的 ImageX 上传（`prepare_upload` → `ApplyImageUpload` → TOS → `CommitImageUpload` + AWS4 签名）。本 change 只让能力矩阵不再拒绝这类请求
- 不引入 Docker 部署形态（方案 A 已放弃，上游仓库保留为协议参考）
- 不改 `dola-pool2` 本身

## Decisions

### 决策 1：`maxReferenceImages` 改可空，用 `null` 表示不限制

原设计 `0` = 不支持。但"明确不支持"与"没测过上限"是两件事，用 `0` 表达后者会让 UI 显示"不支持参考图"这句假话，用户于是根本不用 Dola 做片段级生成。

```
0     → 明确不支持，携带即拒
null  → 不限制，放行任意数量
正数  → 有上限，超过即拒
```

Dola 用 `null`：上游文档说 10 张，但我们没实测过上限，也没做上线控制。与其编一个数字，不如承认没测。

**破坏面**：`int` → `int?`，36 处引用。所有 preset 显式给出值（不依赖默认），序列化把 `null` 写为缺省；`ai_config_page.dart:1566` 的空壳判断要从 `== 0` 改为 `== 0 || == null`；`studio_settings_dialog.dart:347` 的展示文案要分三种状态。

**为什么不用一个虚构大数**：UI 会显示"最多支持 100 张参考图"，那是比"不支持"更坏的假话——它给了用户错误的预期。

### 决策 2：配置层挂在号池自己的 store，不走 provider 链路

号池不是 provider：provider 的语义是"一个 baseUrl + 一个密钥"，号池是 N 个 sessionid 的调度池。塞进 `AiProviderConfig` 会让 `keychainKeyId`、`baseUrl` 这些字段全部失去意义。

新增 `DolaConfigStore`，与 `DolaAccountStore` 并列：

```
AppPaths.dolaDir/
  dola_accounts.json      ← 账号元数据（sessionid 在 Keychain）
  dola_capabilities.json  ← 能力覆盖（本 change 新增）
```

覆盖优先级：用户覆盖 > 内置预设 > 协议保守默认。第三条由既有的 `MediaCapabilityResolver` 提供，前两条通过让 `_wrap` 传入一个"号池配置"来源实现。

**`AppPaths.dolaDir` 也是本 change 新增**——`dola_accounts.json` 现在直接躺在 `AppPaths.root` 根下，与其他工具的目录约定不一致。

### 决策 3：能力查找不改 resolver 的签名

`MediaCapabilityResolver.resolve(AiProviderConfigLike?, String)` 的入参是"最小提供者形状"抽象。让 `DolaConfigStore` 也实现这个抽象（`protocolId` + `mediaCapabilities`），resolver 一行不用改。

这比给 resolver 加第三参数干净：加参数的后果是每个调用点都要多传一个东西，而多数调用点没有号池配置可传。

### 决策 4：适配器兜底按型号取合法集合

`_snapDuration` 现在硬编码 `_legalDurations = [5, 10, 15]`。改为按 `_model` 选集合：

```dart
static List<int> get _legalDurations =>
    _model.contains('2.0') ? const [5, 10, 15] : const [5, 10, 30];
```

两层兜底的关系不变：适配器内是单独使用时的保险，`_wrap` 是主路径。测试同时覆盖两条，断言同一请求给同一结果。

### 决策 5：初始化挂 `WindowServices.required`

主窗口 + `aiVideoStudio` 窗口 + 任何可能触发号池出片的窗口，清单里加 `DolaAccountStore` 与 `DolaConfigStore`。

`initFor` 已有 fail-soft（单项失败不阻断 runApp，只打日志），所以号池初始化失败不会黑屏——但这意味着"号池显示为空"需要可诊断。spec 因此要求记录明确错误信号，而不是静默返回空列表。

### 决策 6：用失败测试钉住"参考图上传未实现"

能力矩阵声明支持参考图，但适配器还没实现 ImageX 上传。这个中间状态必须可见：

```dart
test('Dola 参考图上传尚未实现', () {
  // 能力矩阵已声明支持，适配器还未实现上传。
  // 这条测试现在是红的——它标记的是待办，不是疏漏。
  expect(dolaUploadsImages, isFalse);
}, skip: false);
```

不 skip：跳过的测试等于不存在。让它红着，每次全量跑都提醒一次。

## Risks / Trade-offs

- **[Risk] 声明支持但适配器忽略 → 比拒绝更糟** → 用户带 3 张参考图请求 Dola，适配器静默只用文本，拿到一个不一致的片段，且没有任何提示。缓解：适配器在收到超出自身实现能力的请求时**显式抛错**，错误文本说明"参考图上传尚未实现，请改用其他引擎或等待后续版本"。这比静默忽略诚实，也比在能力矩阵里撒谎正确。
- **[Risk] `int?` 破坏面超出预期** → 36 处引用里测试占 20 处。先用 `dart analyze` 全量过一遍再改，不允许有任何一处依赖 `0` 的隐式默认。
- **[Trade-off] 新增 `DolaConfigStore` 是第三套配置机制**（前两套是 `SettingsStore.readToolConfig` 与 `AiProviderConfig`）→ 接受。号池的配置与账号同生命周期，混进任一套都会扭曲那一套的语义。
- **[Risk] 30 秒档位触发片段拼接** → `dola-video-engine` spec 已有「Watermark Removal and Segment Stitching」requirement，说 30 秒会拆两段 15 秒再 FFmpeg 拼接。我们的适配器**没实现这个**。开启 30 秒档位后用户请求 30 秒会拿到什么？必须确认——这也是失败测试要钉住的第二件事。

## Migration Plan

1. `maxReferenceImages` 改 `int?`，全部 preset 显式化，`dart analyze` 清零
2. `AppPaths.dolaDir` + `DolaConfigStore`
3. 能力声明按型号拆分 + 可空上限 + `forModel` 前缀归一到具体型号
4. `_wrap` 的 Dola 分支传入号池配置来源
5. 适配器 `_snapDuration` 按型号 + 超能力请求显式抛错
6. 两条失败测试（参考图上传、30 秒拼接）
7. `WindowServices.required` 接线
8. AI 配置页 tab + 工坊设置引擎选项
9. 全量回归 + 部署

回滚：revert 单 commit，无数据迁移（`dola_capabilities.json` 是新文件，删除即可）。

## Open Questions

（无——30 秒档位的去留已在下方「决策 7」定论。）

## 决策 7：30 秒档位暂不声明

`seedance-2.5` 上游支持 30 秒，但走两段 15 秒 + FFmpeg 拼接，适配器未实现。选择**暂不声明**：声明一个必然抛错的值，比不声明更让用户困惑——用户看到"支持 30 秒"于是按 30 秒规划分镜，提交时才知道不行。

5/10 秒已覆盖常规片段时长（分镜 3-5 秒、片段 8-15 秒）。30 秒与拼接实现属于同一批工作，留给后续 change 一起上。

代价是 `seedance-2.5` 与 `seedance-2.0` 的合法集合只差 15 秒这一项（5/10 vs 5/10/15），区分数度降低。接受——型号差异仍然真实存在，且 2.0 的 15 秒是我们现在就能用的。

<details>
<summary>被否决的方案：声明 30 秒并让适配器抛错</summary>

> **30 秒档位要不要现在开？** `seedance-2.5` 上游支持 30 秒，但需要两段 15 秒拼接（`dola_pure_api.py` 的拼接逻辑 + FFmpeg），我们的适配器没实现。两个选择：
>
> - **开**：能力矩阵说支持 30 秒，适配器收到 30 秒请求时显式抛错「30 秒档位需片段拼接，尚未实现」——用户至少知道为什么
> - **不开**：`seedance-2.5` 只声明 5/10，等拼接实现后再补 30
>
> 我倾向**不开**：声明一个必然抛错的值，比不声明更让用户困惑。而 5/10 秒已经覆盖工坊的常规片段时长（分镜 3-5 秒，片段 8-15 秒）。30 秒留给后续 change，与拼接实现一起上。
>
> 这个选择会改 spec 里 `seedance-2.5` 的时长集合，所以先问。

否决原因：用户确认不开。「至少知道为什么」这个好处不足以抵消「按 30 秒规划了分镜却提交不了」的成本。

</details> `seedance-2.5` 上游支持 30 秒，但需要两段 15 秒拼接（`dola_pure_api.py` 的拼接逻辑 + FFmpeg），我们的适配器没实现。两个选择：

- **开**：能力矩阵说支持 30 秒，适配器收到 30 秒请求时显式抛错「30 秒档位需片段拼接，尚未实现」——用户至少知道为什么
- **不开**：`seedance-2.5` 只声明 5/10，等拼接实现后再补 30

我倾向**不开**：声明一个必然抛错的值，比不声明更让用户困惑。而 5/10 秒已经覆盖工坊的常规片段时长（分镜 3-5 秒，片段 8-15 秒）。30 秒留给后续 change，与拼接实现一起上。

这个选择会改 spec 里 `seedance-2.5` 的时长集合，所以先问。
