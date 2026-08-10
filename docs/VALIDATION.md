# 验证记录

日期：2026-08-11

本地工具链：

```text
moon 0.1.20260803
Moon compiler v0.10.6
```

已执行：

```bash
moon check
moon check --deny-warn
moon build
moon test
moon run cmd/main
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

发布前建议再次执行：

```bash
moon check
moon build
moon test
moon run cmd/main
moon login
moon publish --dry-run
```

当前环境尚未登录 Mooncakes，`moon publish --dry-run` 会在读取凭证时停止。登录后应重新执行该命令，并把结果补入发布记录。
