# CaseWeave

CaseWeave 是一个用 MoonBit 编写的确定性组合测试矩阵生成器。它面向“配置很多、组合爆炸、但每个维度都想覆盖到”的测试场景，例如：

- 操作系统 × 浏览器 × 登录方式 × 区域
- 数据库版本 × 存储引擎 × 事务模式 × 部署形态
- 设备类型 × 网络状态 × 权限策略 × 功能开关

它的角度不是随机生成测试数据，而是系统性生成 pairwise 或更高强度的 covering array：在尽量少的测试用例里覆盖所有可行的参数交互，并且能用约束排除现实中不可能出现的组合。

## 主要功能

- 以 MoonBit 为主要实现语言，无第三方运行时依赖。
- 支持强度 1、2、3 及更高的组合覆盖，默认 pairwise。
- 支持约束 DSL：`==`、`!=`、`in`、`not in`、`and`、`or`、`not`、`=>`。
- 生成过程确定性可复现，相同输入得到相同矩阵。
- 支持 CSV、JSON、Markdown 导出。
- 支持对任意测试套件做覆盖率审计，并列出缺失交互。
- 提供可运行示例、单元测试、CI 配置和 Mooncakes 发布元数据。

## 快速开始

```bash
moon check
moon build
moon test
moon run cmd/main
```

示例程序会生成一份部署测试矩阵，并打印覆盖率摘要：

```text
CaseWeave deployment matrix
strength=2, cases=11, interactions=43, candidates=42/54, removed=0
strength=2, cases=11, coverage=100%, covered=43/43, missing=0
```

## API 示例

```moonbit
import {
  "participant/caseweave" @caseweave,
}

fn main {
  let model = @caseweave.Model::new([
    @caseweave.Parameter::new("os", ["linux", "windows", "macos"]),
    @caseweave.Parameter::new("browser", ["chrome", "firefox", "safari"]),
    @caseweave.Parameter::new("auth", ["password", "oidc"]),
  ])
  let model = match model {
    Ok(value) => value
    Err(_) => panic()
  }
  let safari_rule = match @caseweave.Constraint::parse(
    "Safari is only supported on macOS",
    "browser == safari => os == macos",
  ) {
    Ok(value) => value
    Err(_) => panic()
  }
  let suite = match @caseweave.generate(model, constraints=[safari_rule]) {
    Ok(value) => value
    Err(_) => panic()
  }
  println(suite.summary())
  println(suite.to_markdown(model))
}
```

## 项目边界

CaseWeave 负责生成和审计测试矩阵，不负责执行测试、调用浏览器、管理环境或写入文件。这样的边界让它适合作为库被 CI、命令行工具或业务测试框架调用。

## 目录

- `model.mbt`：参数模型、测试用例和输入验证
- `constraint.mbt`：约束 DSL、解析、验证和部分求值
- `generate.mbt`：候选枚举、交互收集、贪心覆盖和冗余删除
- `coverage.mbt`：覆盖率审计和缺失交互命名
- `export.mbt`：CSV、JSON、Markdown 导出
- `cmd/main`：可运行示例
- `docs/`：API、设计、验收和验证记录

## Mooncakes 发布

发布前请把 `moon.mod` 里的 `participant/caseweave` 改成你的 Mooncakes 用户名或组织名，例如 `yourname/caseweave`，并填写真实仓库地址。

```bash
moon check
moon build
moon test
moon publish --dry-run
moon publish
```

## 许可证

本项目使用 MIT License。第三方依赖当前为零；如后续加入外部代码或素材，必须在 `NOTICE.md` 中记录来源、版本和许可证。
