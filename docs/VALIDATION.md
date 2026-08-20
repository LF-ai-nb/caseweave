# 验证记录

日期：2026-08-20

本地工具链：

```text
moon 0.1.20260814
moonc v0.10.8+8606a5800
moonrun 0.1.20260814
```

已执行：

```bash
moon check
moon check --deny-warn
moon build
moon test
moon run cmd/main
moon fmt --check
moon publish --dry-run
```

当前测试覆盖内容：

- 模型输入验证
- 参数和值索引查询
- 测试用例校验
- 约束 DSL 解析、优先级、蕴含、集合语法和错误报告
- 约束名称和值校验
- pairwise 生成完整性
- 生成结果确定性
- 强度 1 和强度 3 覆盖
- 约束剪枝后的覆盖审计
- 不可能模型和候选上限错误
- 覆盖率缺口命名
- CSV、JSON、Markdown 导出转义
- 场景规格解析：参数、约束、包含样例、排除样例、风险权重
- 场景运行：合并必须样例、覆盖审计、风险排序
- 场景质量门禁：严格门禁、失败报告、Markdown 报告
- 场景 lint：无约束、无风险、强度 1、单值参数等弱信号
- 带引号 CSV 值和 malformed spec 错误报告

当前有效 MoonBit 代码规模：

```text
非空、非注释 .mbt 行数：3229
测试数：22，全部通过
```

发布前建议再次执行：

```bash
moon check
moon build
moon test
moon run cmd/main
moon login
moon publish --dry-run
```

本轮 `moon publish --dry-run` 已完成包检查、压缩包解压后复查和服务端 dry-run 校验。服务端返回：

```text
202 Accepted
Dry run completed successfully. No changes were made.
package MX-ai-nb/caseweave version 0.1.0
```

注意：当前 CLI 在服务端 dry-run 成功后仍以非零退出码打印 `Error: moon publish failed`。以服务端 `202 Accepted` 细节判断，包内容和用户名匹配校验已经通过；正式发布前仍建议重新运行 `moon publish --dry-run` 并确认 moon 工具链版本行为。
