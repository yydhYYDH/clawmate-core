# HarmonyOS → OpenHarmony 提示词盲测

## 输入与产物

- `../harmonyos-starter/docs/08-oh-migration-prompt.md`：完整提示词，含可删除的盲测约束段。
- `student-prompt.md`：给学生的版本，仅删除盲测段，其余要求相同。
- `frozen-prompt.txt`：实际发给独立实现会话的冻结提示词。
- `baseline-manifest.json`：参考 OH 与原 starter 的源码哈希，检查过程没有修改它们。
- `blind-input-manifest.json`：独立副本初始输入哈希。
- `acceptance.test.cjs`：未提供给实现会话的独立行为验收。
- `starter-check.log`、`oh-reference-check.log`：原工程测试基线。
- `held-out-starter.log`：独立行为验收在原 starter 上的结果。
- `held-out-blind.log`：冻结产物的 5 项独立业务验收，全部通过。
- `hdc-handshake.test.cjs`、`hdc-handshake-blind.log`：冻结后协议回放，两项失败。
- `VALIDATION.md`：完整结论与已知差异；首轮**未完全对齐**。
- `blind-output/`：首轮冻结源码包、未签名 HAP、原始报告、访问记录与日志。

盲测工作目录：`/private/tmp/clawmate-oh-blind-20261022`，独立包名 `com.clawmate.ohblind`。实现会话未继承教师会话历史，只得到 starter 副本、冻结提示词和工具链位置。个人 HarmonyOS 签名配置在副本创建时已移除。副本中源版本历史 `reports/` 不作为实现输入读取；实现者单独记录实际访问资源。

## 判定原则

“一致”指可观察功能与关键异常行为，不指文件逐字相同。基线已有能力和四项教学目标分别核对。现有 OH 主工程的默认规划目录没有课程浏览器；独立 RoboPi 浏览器有下载代码，但已有记录只验证浏览与搜索。因此不能声称参考版早已完整验收四项教学功能。

实现冻结后再运行独立验收、阅读输出并对照参考版。教师发现的问题写入验收报告，不回灌给原盲测会话修补后再冒充首轮结果。

## 复现独立行为检查

```sh
MIGRATION_TARGET=/absolute/path/to/migrated-project \
  /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  --test migration-validation/acceptance.test.cjs
```

这些用例通过模块替身验证真实业务循环，不能代替设备端 HDC 认证、图库、后台任务、模型、网页、备忘录或文件下载验收。
