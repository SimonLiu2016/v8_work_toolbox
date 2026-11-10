# 提案：随心短剧题材标签快速筛选与按评分排序支持

## 1. 背景与动机
随心短剧在具备全库 3300+ 部短剧探索后，用户需要更精细化的找剧工具：
1. **类型标签快速检索**：每部短剧具有“都市”、“现代”、“逆袭”、“重生”等类型标签，用户希望能够在片库中快速按类型过滤，且点击卡片上的标签能立即跳转至同类型短剧；
2. **按分数排序**：短剧包含 7.0~9.8 等评分，用户需要类似主流影视软件的“评分最高”排序功能，快速定位高分佳作。

## 2. 核心方案
1. **多维度题材标签体系 (Genre Tags)**：
   - 提取上游高频题材标签（`全部`、`都市`、`现代`、`逆袭`、`重生`、`古风`、`仙侠`、`系统`、`后宫`、`职场`、`校园`、`脑洞`、`大男主`、`大女主`、`甜宠` 等）；
   - 在片库中展示可滑动的快速标签胶囊栏；
   - 短剧卡片底部的标签升级为可点击胶囊（Clickable Tag Chip），点击任意标签直接进入该标签专题；
2. **多模式排序器 (Sorting)**：
   - 支持三种排序策略：
     - `defaultOrder`（综合推荐 / 最新）
     - `scoreDesc`（评分最高，高分霸榜）
     - `episodesDesc`（集数最多，长篇耐看）
   - 用户切换排序后列表即时更新；触底加载更多时保持排序逻辑连贯。

## 3. 影响范围
- `lib/tools/casual_short_drama/models/drama_models.dart`
- `lib/tools/casual_short_drama/services/casual_short_drama_controller.dart`
- `lib/tools/casual_short_drama/ui/casual_short_drama_page.dart`
- `test/casual_short_drama_api_test.dart`
