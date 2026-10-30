## ADDED Requirements

### Requirement: 制作类型全矩阵风格锁与约束系统

系统 SHALL 为所有 `StudioProductionType`（`drama` 真人剧情、`anime` 二次元/动态漫、`narration` 图文解说、`anime3d` 3D国漫/次世代虚拟剧）提供专属的风格基准锁（Style Tokens）、负向抑制词（Negative Tokens）、三视图与场景渲染规范，并在全链路（小说提取、IP资产生成、分镜关键帧、视频生成）中自动生效。

#### Scenario: 3D国漫 (anime3d) 风格锁注入
- **WHEN** 剧集类型为 `anime3d`
- **THEN** 系统 SHALL 默认注入 `3D CGI animation, modern Chinese fantasy donghua, exquisite 3D render, Unreal Engine 5 render, Octane render, subsurface scattering skin, delicate hair strands, glowing elemental VFX, cinematic lighting` 为正向风格基准，负向默认注入 `2D, flat anime, cartoon, sketch, live-action photo, plastic clay, low-poly, stiff puppet, glossy plastic skin`，视频生成默认强调飘逸长发与粒子剑气特效

#### Scenario: 真人短剧 (drama) 风格锁与负向互斥
- **WHEN** 剧集类型为 `drama`
- **THEN** 系统 SHALL 默认注入 `cinematic film still, photorealistic 8k, live-action cinematography, natural skin texture, realistic micro-expressions, 35mm lens` 为正向风格基准，负向显式抑制 `anime, cartoon, 3D render, CGI, doll, plastic skin, illustration, painting, drawing, unreal engine`，严防跑偏为动漫或 CG

#### Scenario: 二次元/动态漫 (anime) 风格锁
- **WHEN** 剧集类型为 `anime`
- **THEN** 系统 SHALL 默认注入 `high quality anime aesthetic, Japanese anime art style, crisp cel-shaded lines, vibrant anime coloring, Makoto Shinkai lighting, Ufotable visual flair`，负向抑制 `photorealistic, live-action, 3D CGI, realism, real human photo`

#### Scenario: 图文解说 (narration) 风格锁
- **WHEN** 剧集类型为 `narration`
- **THEN** 系统 SHALL 默认注入 `high-end documentary illustration, editorial conceptual art, atmospheric digital painting, storybook realism, textured brushwork, elegant lighting`，负向抑制 `messy, anime, cartoonish, low-brow, chaotic composition`

#### Scenario: IP主库角色与场景生图自动继承类型风格
- **WHEN** 用户在任何剧集的 IP 主库（角色卡、场景库、道具库、三视图）触发 AI 生图
- **THEN** 系统 SHALL 自动组合该剧集所属制作类型的风格基线与负向抑制词，避免各资产子库风格割裂
