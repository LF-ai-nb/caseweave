# 验证记录

日期：2026-08-21

本地工具链：

```text
moon 0.1.20260819
moonc v0.10.9+6e6c44045
moonrun 0.1.20260819
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
moon publish
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
- 覆盖缺口修复：从不完整外部套件生成补测建议
- 约束下修复：补测建议不会违反约束
- 风险感知修复：收益相同时优先高风险路径
- 补测门禁：完整性、补测预算、best-effort partial 计划
- 修复选项校验和 normalize 行为

当前有效 MoonBit 代码规模：

```text
非空、非注释 .mbt 行数：4078
测试数：27，全部通过
```

后续版本发布前建议再次执行：

```bash
moon check
moon build
moon test
moon run cmd/main
moon login
moon publish --dry-run
moon publish
```

本轮 `moon publish --dry-run` 已完成包检查、压缩包解压后复查和服务端 dry-run 校验。服务端返回：

```text
202 Accepted
Dry run completed successfully. No changes were made.
package LF-ai-nb/caseweave version 0.1.0
```

随后已执行正式发布，服务端返回：

```text
200 OK
```

Mooncakes 页面已可访问：`https://mooncakes.io/docs/LF-ai-nb/caseweave`。

注意：当前 CLI 在服务端 dry-run 成功后仍以非零退出码打印 `Error: moon publish failed`；正式 `moon publish` 已正常返回 0。

## 补充差异化自查

日期：2026-08-21

已根据近期黑客松初审反馈中常见的“功能重叠、未披露扩展关系、同名或关联仓库不清”风险补充检查：

- 新增 `docs/DIFFERENTIATION.md`，明确 CaseWeave 不是 Mooncakes 审查、README/许可证校验、来源证明、机器人策略或报名材料审核工具。
- README、API、设计说明、申报书和验收说明已统一使用“覆盖验证”描述项目能力，避免与源码审查或包审查方向混淆。
- 公开仓库未写入外部参赛项目、他人账号、他人姓名或私人联系方式。
- 当前公开仓库和 Mooncakes 包名保持一致：`LF-ai-nb/caseweave`。
