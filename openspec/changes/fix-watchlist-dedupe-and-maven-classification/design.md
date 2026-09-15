## Context

三个缺陷的定位与证据见 proposal.md 的 Why 与 What Changes，此处只记录实现层面的边界。

当前数据流：

```
discoverProjectRoots()
├─ _walkDiscover(HOME, depth≤5)        → 自然根集合
├─ for root in watchlist: raw.add()     → 直接追加，不做前缀判断
└─ _dedupeNested(withoutHome)          → 按字典序排序后，前缀匹配者丢弃
                                          ↑ 缺陷 1：watchlist 宽容器条目在这里吞掉子根
```

`_dedupeNested` 本身的排序-前缀去重是对的（它就是为「HOME 自身不作为根」这条规格服务的），缺陷在于 watchlist 条目以「无条件追加」的方式进入同一集合，享受了与其他根完全相同的去重待遇。

配置继承的数据流：

```
getSlimerProjectArtifactConfig()
└─ _inheritCleanBuildsConfigIfNeeded(json)
    ├─ if flag == true: return                 ↑ 缺陷 2a：一次性标志
    ├─ if extraRoots 为空: 合并 12 根          ↑ 缺陷 2b：空值守卫
    └─ flag = true; write
```

## Goals / Non-Goals

**Goals**

- watchlist 条目不再吞掉其下自然发现的项目根
- Maven / Java 项目在 UI 上以独立技术栈组呈现
- 既有已完成继承但承接键非空的用户，配置在下一次读取时自愈

**Non-Goals**

- **不改动 Tier B 的预算数值或超时策略**。一个过宽的 watchlist 条目若真成为单根，可能触及 4s 预算 / 20000 次访问上限而触发 `incomplete`（是否必然超时见 D4，未实测）——但这属于预算机制按规格工作（"扫描超时 / 未完整"显式上报），不是本变更要修的东西。交集语义使这一场景基本不再出现；剩余的边界场景（watchlist 根下确无自然根）由既有超时机制兜底。
- **不引入 Spring 识别**（见 proposal）。
- **不调整技术栈分组的呈现形态**（组行 + 展开明细的两层结构保持不变）。
- **不做 `clean-builds.json` 之外的其他被移除工具继承**（目前仅此一处合并）。

## Decisions

### D1: watchlist 与自然根做交集，而不是并集后去重

```
自然根集合 R（已 _dedupeNested）
watchlist 集合 W

result = R ∪ { w ∈ W | ∀ r ∈ R, ¬(r startsWith w) }
```

watchlist 条目只有在**其下没有任何自然根**时才自身作为根加入。这使 watchlist 回到 D2/D4 设计里"manifest 门控的逃生口"定位——它存在的意义是覆盖无 manifest 的项目，而不是充当父前缀。

**替代方案 1：watchlist 条目完全不参与去重。** 更简单，但会让 `~/Workspace` 与 `~/Workspace/ctf-gitlab/dc-promotion` 同时成为根。Tier B 对两者各设独立预算，重复遍历同一批文件，且保留清单按根粒度生效时语义混乱（用户取消了 dc-promotion，但父根仍在列表里覆盖它）。

**替代方案 2：watchlist 也走 manifest 门控。** 彻底，但违背设计里"D2 代价的缓解"——watchlist 就是给无 manifest 项目用的逃生口。

**边界情况**：watchlist 条目本身就是自然根时，交集会丢弃 watchlist 条目、保留自然根，等价无害。watchlist 根下的自然根因深度上限而未被发现时，该 watchlist 条目无子，保留——这正是逃生口的预期行为。

### D2: `_detectTechStack` 增加 maven 分支，优先级置于 gradle 之后

优先级（最具体的实际构建信号优先）：

```
.gradle / build.gradle / build.gradle.kts  → gradleAndroid
pubspec.yaml / .dart_tool / xcodeproj      → flutterDart
pom.xml                                    → maven        ← 新增
package.json / node_modules / dist         → node
                                            → other
```

`pom.xml` 置于 flutter 之后是因为 Android 项目常见 `build.gradle` + `settings.gradle` + 子模块，而 gradle 信号比 pom 更能描述实际构建方式；flutter 与 node 之间无交叉，maven 插在 flutter 之后 node 之前，对既有分类结果无影响（既有分支的命中条件完全不含 `pom.xml`）。

**为什么用 `pom.xml` 而非 `pom.xml` + `settings.xml` + `src/main/java`**：Tier A 的门控信号表已经只认 `pom.xml` 一项。技术栈推导应与发现层保持同源——若发现层认了 `pom.xml` 就够当根，推导层也应认它。要求 `src/main/java` 会让 Tier A 发现的 Maven 根在 Tier B 变成 `other`，重现本变更要修的 bug。

### D3: 继承改为无条件并集，flag 语义收窄为"已提示"

```
// 之前
if (json['slimmerInheritedFromCleanBuilds'] == true) return;
if (extraRoots 为空) 合并;
json['slimmerInheritedFromCleanBuilds'] = true;

// 之后
合并 = union(extraRoots, cleanBuildsRoots)   // 按值去重
写回
if (flag 未置位) { flag = true; 一次性提示 }  // 提示，不是门闸
```

并集合并天然幂等（按值去重，重复执行不产生重复条目），所以移除空值守卫后，重复启动只是重复执行一次廉价的集合操作。`artifactOptions` 同样改为并集——虽然当前 `clean-builds.json` 无该字段可继承，但语义应与 `extraRoots` 一致，避免未来同类字段再犯。

**替代方案：flag 置位时跳过，但提供手工修复路径。** 需要用户自己动手改 JSON，且 12 个根已经被吞过一次——再要求用户手工补救不合宜。并集合并使配置自愈，零用户操作。

**为什么不新增 flag（如 `slimmerInheritedV2`）**：并集是幂等的，不需要版本位。新增 flag 会把"是否已继承"重新变成门闸，只是门闸换了一个名字。

### D4: 巨型根的超时风险不在本变更内修

交集语义落地后，`~/Workspace` 这种宽容器条目会被交集丢弃（其下有大量自然根），Tier B 不再收到它。剩余的边界场景是"用户显式添加的 watchlist 根，其下确无任何自然根"——此时 Tier B 收到单根，4s 预算可能不够，但该场景符合规格要求的显式超时上报，且用户是主动添加的，知情成本由用户承担。

**注意**：此处关于宽容器根"是否会超时"是推断而非实测——Tier B 的 4s 预算与 20000 次访问上限足以让深树超时，也可能在预算内完成，取决于子项目实际体积与剪枝后的访问数。任务 2.6 要求实测这一行为；若实测显示宽容器根在预算内可完成，则本条仅是防御性说明，不影响 D1 的正确性。

不在本变更引入"自动下钻"或"预算自适应"，避免把性能参数调整混进一个正确性修复里。

## Risks / Trade-offs

- **[watchlist 交集丢弃用户显式意图]** → 用户添加 `~/Workspace` 可能本意是"我要扫这一整片"。缓解：交集语义下，`~/Workspace` 下的子项目**每个都会**成为独立条目，覆盖范围不减反增（此前是被压成 1 个 `incomplete` 条目）；条目数量增加但每条都可独立操作、独立标记保留。这是行为改善而非退化。
- **[继承并集后根数突增，Tier A/B 耗时上升]** → 并集补回 12 个根，但它们大多已有自然根覆盖（如 `ctf-gitlab` 下已有多个自然根），实际净增有限。缓解：交集语义使"有子则弃父"，被补回的宽容器根（如 `Workspace`）多数会因有子根而被丢弃。
- **[一次性提示时机]** → 无条件并集意味着提示只能挂在 flag 首次置位时，此时用户可能已经手动加过条目，"已继承 N 个旧项目根"这条提示与用户认知可能不符。缓解：提示措辞用"已从旧配置补充"而非"已迁移"，且仅出现在配置设置区，不打断扫描流程。
- **[`pom.xml` 误判]** → 极少数场景下 `pom.xml` 出现在非 Maven 目录（如文档示例目录）。缓解：Tier A 同样认 `pom.xml`，即发现层与技术栈层同源；误判影响仅体现在分组归属，不影响产物是否被识别（产物识别看目录名，与 manifest 无关）。
- **[两个待归档变更与本变更的 spec 交叉]** → 本变更修改的三条需求在 base spec 中尚不存在（`merge-clean-builds-into-slimmer` 以 ADDED 声明，`fix-tier-a-discovery` 以 MODIFIED 修订，二者均未归档）。三者必须按 merge → tier-a-discovery → 本变更 的顺序归档，否则 MODIFIED 找不到目标或 ADDED 被 MODIFIED 覆盖。

## Migration Plan

1. 实现 D1（`discoverProjectRoots` 交集）、D2（`_detectTechStack` maven 分支 + 枚举值）、D3（`_inheritCleanBuildsConfigIfNeeded` 并集 + flag 语义收窄）。
2. 新增测试：watchlist 有子根时弃父、watchlist 无子根时保留、Maven 根归入 maven 组、承接键非空时继承仍并入、flag 已置位时继承仍补齐。
3. 本机实测：真实配置下根集合恢复情况（基线：自然发现 782 根，watchlist 吞根后 553 根；预期交集语义下恢复到接近 782，且 `~/Workspace` 不再是条目）。
4. 部署后验证：Maven / Java 组在 UI 上可见且非空；`~/Workspace` 不再作为单一条目出现；`extraRoots` 中 12 个旧根已补回。
5. **回滚**：git revert。数据侧——D3 的并集合并已写入 `smart-disk-slimmer.json`，revert 后旧版代码读到的是含 12 根的配置，行为等价于"用户手动补过"，无破坏性；D1/D2 纯代码，无数据迁移。
6. 归档顺序：本变更排在 `merge-clean-builds-into-slimmer` 与 `fix-tier-a-discovery` 之后。

## Open Questions

- 继承并集时是否需要把被补回的根在 UI 设置区标记为"来自旧配置"以便用户区分来源 → 不影响规格与任务分解，实现期按现有 `extraRoots` 展示形态决定。
- `extraRoots` 的展示是否需要提示"该条目下已发现 N 个子项目，将作为独立条目扫描" → 呈现细节，可后续独立变更。
- 技术栈是否需要再细分（如 Android 与纯 JVM/Gradle 分开）→ 当前 5 组已覆盖本机实际分布，待实测再判断。
