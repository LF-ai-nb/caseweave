# 黑客松验收说明

## 项目定位

CaseWeave 是一个确定性组合测试矩阵生成器。它服务于配置测试、兼容性测试和发布前冒烟测试，把庞大的笛卡尔积压缩成可验证的覆盖矩阵。当前版本进一步支持场景规格、业务风险排序、覆盖缺口修复和 CI 质量门禁，能把“模型 → 矩阵 → 覆盖验证 → 风险解释 → 补测计划 → 门禁报告”串成完整测试计划。

## 与常见项目的差异

项目没有选择通用算法题、格式转换器、随机测试工具、覆盖率报告或提交材料自查工具，而是聚焦“配置组合爆炸”这一工程测试痛点。它的产物不是随机样本，也不是已有测试的结果汇总，而是一份能解释覆盖率、能导出、能按风险排序、能修复覆盖缺口、能被 CI 检查的测试计划。

已按 Mooncakes/GitHub 上常见 MoonBit 测试类方向做过查重式对比：相邻项目主要集中在性质测试、状态机测试、TAP/覆盖率报告、提交自查、测试充分性门禁和 novelty 分析。CaseWeave 的核心能力是确定性 constrained covering array；新增的场景规格与风险门禁让它更接近“发布前组合测试计划生成器”，与上述方向存在明确功能边界。

本项目为原创开发，不是对已有 Mooncakes 审查、README/许可证校验、来源证明、机器人策略或报名材料审核工具的移植、改名或扩展。仓库中的 `audit` 语义限定为测试矩阵覆盖验证，不读取其他仓库，不审查包发布资格，也不做开源来源溯源。

详细查重与边界说明见 `docs/DIFFERENTIATION.md`。

## 验收清单

- MoonBit 为主要实现语言：核心库、示例和测试均为 `.mbt`。
- 代码仓库公开可访问：已推送到公开 GitHub 仓库 `https://github.com/LF-ai-nb/caseweave`。
- README 清晰完整：见 `README.md`。
- 用途、主要功能、使用方法：见 `README.md`、`docs/API.md`。
- 可运行示例：`moon run cmd/main`。
- 持续集成：见 `.github/workflows/ci.yml`。
- 可运行测试：`moon test`。
- 正常构建：`moon build`。
- Mooncakes 发布：已按 `LF-ai-nb/caseweave` 发布，页面为 `https://mooncakes.io/docs/LF-ai-nb/caseweave`。
- 开发过程可追踪：本地 Git 历史包含脚手架、核心、导出、文档和 CI 等阶段提交。
- 功能边界清晰：见 `docs/DESIGN.md` 和 `docs/DIFFERENTIATION.md`。
- 后续维护价值：见 `docs/ROADMAP.md`。
- 第三方依赖和许可证：当前无第三方运行时依赖，项目采用 MIT License。
- 有效 MoonBit 代码规模：当前非空、非注释 `.mbt` 行数已超过 4000 行，且新增代码集中在场景规格、风险排序、覆盖修复、质量门禁和对应测试。

## 建议保留记录

- Git 提交记录：按功能阶段提交。
- Issue 记录：使用 `.github/ISSUE_TEMPLATE`。
- 合并请求记录：使用 `.github/pull_request_template.md`。
- 测试记录：见 `docs/VALIDATION.md`。
- 更新日志：见 `CHANGELOG.md`。
- 版本发布记录：见 `CHANGELOG.md` 和 GitHub Releases。
- 重要技术方案：见 `docs/DESIGN.md`。
