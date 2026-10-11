# 剪映（CapCut Mac 版）草稿 JSON 结构

本文档记录 `JianyingExporter` 写入的草稿格式，以及它是怎么来的。

> **这是逆向分析的结果，不是剪映的官方契约。** 剪映随时可能改格式；
> 每次导出前的自检（`JianyingExporter.validateDraft`）会在结构不对时改走
> 备用导出，所以格式漂移的表现是"退回素材文件夹"，而不是"用户拿到打不开的
> 目录"。

## 1. 草稿在磁盘上的位置

```
~/Movies/JianyingPro/User Data/Projects/com.lveditor.draft/<draft-uuid>/
├── draft_content.json      # 工程本体：轨道、片段、素材引用
├── draft_meta_info.json    # 草稿元信息（名称、封面、时间）
└── <素材文件>              # 剪映自己导入的素材副本
```

导出器只生成 `draft_content.json` 加一个 `materials/` 软链接目录。用户要么
把整个目录拷到剪映的 Projects 目录下，要么用剪映的「导入草稿」指向它。

## 2. `draft_content.json` 结构

```json
{
  "version": 3,
  "canvas": { "width": 1080, "height": 1920, "ratio": "9:16" },
  "tracks": [ ... ],
  "materials": [ ... ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `version` | int | 草饺内容格式版本。Mac 版 5.x/6.x 实测接受 `3`。改动会导致剪映直接不列出该草稿。 |
| `canvas` | object | 画布尺寸与比例。工坊只出 9:16 竖屏（design.md Non-Goals），所以恒定 1080×1920。 |
| `tracks` | array | 轨道列表，见下。 |
| `materials` | array | 素材引用列表，见下。 |

### 2.1 轨道（`tracks`）

每个轨道一个对象：

```json
{ "type": "video", "segments": [ ... ] }
```

`type` 取值：`video` / `audio` / `text` / `bgm`。同一个 `type` 出现多次时
剪映会并到同名轨道上——所以导出器把台词音频与 BGM 分成两个 `audio`/`bgm`
轨道，避免混在一起。

**片段（`segments[]`）** 是轨道上的时间片：

| 字段 | 类型 | 说明 |
|------|------|------|
| `material_id` | string | 指向 `materials` 里的素材 id。 |
| `start` | int | 片段在**时间轴**上的起点，单位**微秒**。 |
| `duration` | int | 片段时长，微秒。 |
| `source_start` | int | 从素材的第几微秒开始用。工坊的片段都是整段用，恒为 0。 |
| `speed` | number | 倍速。工坊不做变速，恒为 1.0。 |

字幕片段多一个 `text` 字段（字幕正文）。

### 2.2 素材（`materials`）

```json
{ "id": "shot_1.mp4", "path": "shot_1.mp4", "type": "video" }
```

`path` 是相对 `materials/` 目录的文件名。导出器在 `materials/` 下建软链接
指向工坊的 `clips/`、`audio/`，所以：

- 素材仍留在 `AppSupportDir/video_studio/.../clips/` 下，Finder 直接可访问
  （spec「通过系统文件管理器可直接访问原始素材」）；
- 剪映那边读到的是完整文件；
- 用户改 Mask 重新导出，不会在剪映目录里堆一份重复的素材。

软链接失败（跨卷、权限）时退回复制——占盘换可用。

## 3. 时间单位

剪映用**微秒**整数；SRT 用毫秒；工坊内部用毫秒（`audioDurationMs`）。三者
的换算都是精确乘法/除法，没有浮点误差累积，所以 spec 要求的
「字幕时间码与 SRT 误差不超过 50 毫秒」实测误差为 0。

## 4. Ducking

剪映的草稿格式里**没有**「按时间段压 BGM」的字段——它只有音频轨上的一个
布尔开关，让剪映自己做人声避让。所以导出器在 BGM 轨上写 `ducking: true`，
把具体的压混时段计算交给剪映。

这与 FFmpeg 直出路径不同：那边由 `FfmpegComposer.buildDuckingEnableExpr`
按 SRT 时间轴生成精确的 `volume` 滤镜区间。两条路径的 Ducking 精度不一致是
已知的取舍，记录在此以备后面有人来问"为什么导出的草稿压混和 MP4 不一样"。

## 5. 版本变更的处理

格式变化时只改两处：

1. `jianying_exporter.dart` 的 `draftFormatVersion` 常量；
2. 本文档对应表格。

`validateDraft` 的断言同时更新。三者不同步时，测试会先红了提醒。

## 6. 验证方式

- 结构层面：`test/ai_video_studio_jianying_test.dart` 断言时间码累计、
  微秒换算、素材软链接、自检的两种失败分支。
- 真实打开：只能人肉。改动格式后必须在 Mac 的剪映里实际打开一次草稿，
  确认四条轨都在、时间轴对齐。这一步 CI 替不了。
