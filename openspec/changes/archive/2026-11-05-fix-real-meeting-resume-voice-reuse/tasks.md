## 1. 续跑复用条件

- [x] 1.1 在 `RealMeetingBaker.bake` 的复用分支增加音色一致性判断：仅当 `previousGroups[i].voiceId == voice` 时才 `continue` 复用；`voiceId` 为空串的组视为不一致，自然落入重烘分支。
- [x] 1.2 确认重烘走普通（非 forced）路径的既有语义保持不变：目标文件直接写入、失败时写静音占位并置 `failed: true`、成功时回写 `voiceId: voice`；不额外引入 forced 集合。

## 2. 测试

- [x] 2.1 单测：已落盘音色与期望音色一致的组不发起合成（断言引擎调用次数与组数对应关系）。
- [x] 2.2 单测：已落盘音色与期望音色不一致的组（如 `step_boy` / `zhixingjiejie` / `mimo_default` → `白桦`）触发重合成，且重烘后 `TurnGroupAudio.voiceId` 更新为期望音色。
- [x] 2.3 单测：落盘 `voiceId` 为空串的历史组触发重合成，重烘后记录本次实际音色。
- [x] 2.4 单测：一次重新合成完成后，`RealMeetingService.pendingGroups` 返回空列表（待更新归零）。
- [x] 2.5 回归：取消（`shouldCancel`）后再次合成能继续完成剩余不一致组，且未完成组的落盘音色仍为旧值（待更新如实反映）。

## 3. 验证与部署

- [x] 3.1 运行 `test/it_meeting_listening/` 下真实会议相关测试，确认全量通过。
- [x] 3.2 用「10-29 项目周例会」(`rm_45006ed0a3df8b35`) 实测：重新合成后整篇音频各说话人音色可区分，待更新归零；记录首轮重烘耗时与组数。
- [x] 3.3 按项目规范执行 `./scripts/deploy_local.sh` 编译部署并验证生效。
