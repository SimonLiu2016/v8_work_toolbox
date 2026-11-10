# 架构与设计：题材标签快速筛选与多维排序

## 1. 模型与枚举扩展
- 定义排序枚举：
  ```dart
  enum DramaSortType {
    defaultOrder('默认排序'),
    scoreDesc('评分最高'),
    episodesDesc('集数最多');

    final String label;
    const DramaSortType(this.label);
  }
  ```

## 2. 控制器状态机 (`CasualShortDramaController`)
- 新增状态属性：
  - `String selectedTag = '';`（空代表全部题材）
  - `DramaSortType sortType = DramaSortType.defaultOrder;`
  - 常量热门标签列表 `static const List<String> popularTags = [...]`
- 排序与过滤流转：
  - `selectTag(String tag)`：若 `selectedTag == tag` 则取消选中，否则设置为当前 tag。通过 `search(tag)` 或 API 拉取该题材并重置分页；
  - `setSortType(DramaSortType sort)`：更新 `sortType`，对当前已加载 `catalogItems` 重新排序并 `notifyListeners()`；
  - 排序器函数：
    ```dart
    void _applySort(List<DramaCard> items) {
      if (sortType == DramaSortType.scoreDesc) {
        items.sort((a, b) => b.score.compareTo(a.score));
      } else if (sortType == DramaSortType.episodesDesc) {
        items.sort((a, b) => b.totalEpisodes.compareTo(a.totalEpisodes));
      }
    }
    ```

## 3. UI 布局呈现 (`CasualShortDramaPage`)
- 在主分类栏与海报网格之间加入二级控制条：
  - 左侧：横向滚动的题材胶囊（全部题材、都市、现代、逆袭、重生、仙侠、古风、系统、后宫、职场、校园等）；
  - 右侧：排序下拉菜单 / 胶囊选择器（默认、评分最高、集数最多）；
- 卡片底部：将单纯的 Text 替换为带微圆角和背景的 `InkWell` 标签胶囊，点击事件阻断外层点击并触发 `selectTag(tag)`。
