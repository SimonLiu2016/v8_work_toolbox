## Why

MacBook Pro 内置麦克风及常见会议拾音设备在现实房间环境中，物理环境底噪（风扇、室内空气流动与拾音器增益）通常处于 $-41\text{dB} \sim -32\text{dB}$ 之间。上一版本将静音底线标定在 $-52\text{dB}$，导致即使在室内完全没有人说话时，环境噪底仍被放大计算为高达 0.5~0.6 的电平，导致波形柱持续剧烈跳动，无法真实反映“静音”状态。

## What Changes

- **引入高信噪比静音截止噪门（Noise Gate）**：将有效输入电平的静音基准线上调至 $-31.0\text{dB}$，低于该门限的声音一律归零贴底输出 `0.0`，彻底杜绝环境底噪引起的虚假波形。
- **重定人声动态感知区间**：将有效人声区间设定为 $[-31.0\text{dB}, -10.0\text{dB}]$，结合平滑非线性感知曲线，开口说话时立即爆发出高灵敏、多层次的动态声波，停止说话时迅速平息贴底。
- **优化组件贴底与静止渲染表现**：确保在 `level == 0.0` 时波形平稳收拢为整齐划一的静态休眠基线。

## Capabilities

### Modified Capabilities
- `meeting-recorder`: 修正录音控制与生命周期管理规约，要求当麦克风输入处于环境底噪（低于噪门门限 $-31\text{dB}$）或静音时，波形必须严格归零贴底且无任何跳动。

## Impact

- `lib/tools/meeting_recorder/services/meeting_record_engine.dart`: 调优 `normalizeRmsDb` 门限与归一化逻辑。
- `test/meeting_recorder/meeting_record_engine_test.dart`: 适配门限单测，增加 $-40\text{dB} \sim -32\text{dB}$ 底噪下严格为 0 的断言。
