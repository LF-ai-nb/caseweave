# 黑客松验收说明

## 项目定位

CaseWeave 是一个确定性组合测试矩阵生成器。它服务于配置测试、兼容性测试和发布前冒烟测试，把庞大的笛卡尔积压缩成可审计的覆盖矩阵。

## 与常见项目的差异

项目没有选择通用算法题、格式转换器或随机测试工具，而是聚焦“配置组合爆炸”这一工程测试痛点。它的产物不是随机样本，而是一份能解释覆盖率、能导出、能被 CI 检查的测试计划。

## 验收清单

- MoonBit 为主要实现语言：核心库、示例和测试均为 `.mbt`。
- 代码仓库公开可访问：发布前需推送到公开 GitHub 仓库。
- README 清晰完整：见 `README.md`。
- 用途、主要功能、使用方法：见 `README.md`、`docs/API.md`。
- 可运行示例：`moon run cmd/main`。
- 持续集成：见 `.github/workflows/ci.yml`。
- 可运行测试：`moon test`。
- 正常构建：`moon build`。
- Mooncakes 发布：发布前更新 `moon.mod` 所有者和仓库地址，然后运行 `moon publish`。
- 开发过程可追踪：本地 Git 历史包含脚手架、核心、导出、文档和 CI 等阶段提交。
- 功能边界清晰：见 `docs/DESIGN.md`。
- 后续维护价值：见 `docs/ROADMAP.md`。
- 第三方依赖和许可证：当前无第三方运行时依赖，项目采用 MIT License。

## 建议保留记录

- Git 提交记录：按功能阶段提交。
- Issue 记录：使用 `.github/ISSUE_TEMPLATE`。
- 合并请求记录：使用 `.github/pull_request_template.md`。
- 测试记录：见 `docs/VALIDATION.md`。
- 更新日志：见 `CHANGELOG.md`。
- 版本发布记录：见 `CHANGELOG.md` 和 GitHub Releases。
- 重要技术方案：见 `docs/DESIGN.md`。
