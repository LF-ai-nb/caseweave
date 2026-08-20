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
- 支持文本场景规格：参数、约束、必须包含/排除的业务样例、风险权重都可以写在同一份 spec 中。
- 支持按业务风险对生成用例排序，方便先跑高风险路径或把风险解释写进测试计划。
- 支持 CI 质量门禁：覆盖完整性、缺失交互数、用例预算、风险样例数量和规格 lint 可形成通过/失败报告。
- 支持覆盖缺口修复：对已有测试套件生成补测建议，把缺失交互逐步补齐，并提供补测门禁。
- 提供可运行示例、单元测试、CI 配置和 Mooncakes 发布元数据。

## 快速开始

```bash
moon check
moon build
moon test
moon run cmd/main
```

示例程序会从一份内嵌场景规格生成部署测试矩阵，并打印覆盖率、风险排序和门禁摘要：

```text
CaseWeave scenario-driven deployment matrix
scenario=Deployment risk matrix, parameters=4, strength=2, constraints=2, includes=1, excludes=1, risks=2
strength=2, cases=11, interactions=43, candidates=42/54, removed=0
strength=2, cases=12, coverage=100%, covered=43/43, missing=0
gate=pass, failures=0, warnings=0, cases=12, coverage=100%, top-risk=13, risk-cases=3
repair=complete, original=1, additions=10, initial-missing=37, final-missing=0, coverage=100%
repair-gate=pass, failures=0, additions=10, initial-missing=37, final-missing=0, largest-gain=6
```

## API 示例

```moonbit
import {
  "ZBZ-ai-nb/caseweave" @caseweave,
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

## 场景规格示例

如果团队希望把测试矩阵配置放进 issue、设计文档或 CI 变量，可以使用 `ScenarioSpec::parse`：

```moonbit
let source =
  "name: Deployment risk matrix\n" +
  "strength: 2\n" +
  "param os: linux, windows, macos\n" +
  "param browser: chrome, firefox, safari\n" +
  "param auth: password, oidc\n" +
  "constraint safari requires macos: browser == safari => os == macos\n" +
  "include: os=linux, browser=chrome, auth=oidc\n" +
  "risk browser=safari: 4: rendering risk\n" +
  "risk os=macos, browser=safari: 9: critical Safari path\n"

let spec = @caseweave.ScenarioSpec::parse(source).unwrap()
let run = spec.run().unwrap()
let gate = run.evaluate_gate(spec, gate=@caseweave.ScenarioGate::strict())
println(run.risk_markdown(top=5))
println(gate.summary())
```

这层能力让 CaseWeave 不只是“生成组合”，而是能把业务约束、必须跑的样例、风险解释和 CI 门禁串成一条可追踪的测试计划。

## 覆盖缺口修复

如果已有测试套件不完整，可以让 CaseWeave 给出追加用例：

```moonbit
let seed = [@caseweave.TestCase::new(["linux", "chrome", "oidc"])]
let repair = @caseweave.plan_repair(model, seed).unwrap()
println(repair.summary())
println(repair.steps_markdown(top=5))
```

如果使用场景规格，修复计划会同时参考风险提示：

```moonbit
let repair = spec.plan_repair(seed).unwrap()
let gate = repair.evaluate_repair_gate(
  gate=@caseweave.RepairGate::budget(20),
)
println(gate.summary())
```

这让项目从“生成第一版矩阵”延展到“审计遗留测试并生成补测计划”，更适合接入真实 CI。

## 独特性说明

我按 Mooncakes/GitHub 上常见测试类方向做过对比：CaseWeave 不做随机性质测试、不做代码覆盖率报告、不做 TAP 报告、不做提交材料自查，也不是通用规则/novelty 分析工具。它的边界是“确定性、带约束、可审计、可导出的组合测试矩阵”，新增的场景规格与风险门禁进一步把它定位为发布前测试计划生成器。

## 项目边界

CaseWeave 负责生成和审计测试矩阵，不负责执行测试、调用浏览器、管理环境或写入文件。这样的边界让它适合作为库被 CI、命令行工具或业务测试框架调用。

## 目录

- `model.mbt`：参数模型、测试用例和输入验证
- `constraint.mbt`：约束 DSL、解析、验证和部分求值
- `generate.mbt`：候选枚举、交互收集、贪心覆盖和冗余删除
- `coverage.mbt`：覆盖率审计和缺失交互命名
- `export.mbt`：CSV、JSON、Markdown 导出
- `spec.mbt`：场景规格解析、必须/排除样例、风险排序和 lint
- `gate.mbt`：CI 场景质量门禁和 Markdown 报告
- `repair.mbt`：覆盖缺口修复计划、风险感知补测建议和补测门禁
- `cmd/main`：可运行示例
- `docs/`：API、设计、验收和验证记录

## Mooncakes 发布

发布前请确认 `moon.mod` 里的包名和仓库地址对应你的 Mooncakes / GitHub 账号。当前配置为 `ZBZ-ai-nb/caseweave` 和 `https://github.com/ZBZ-ai-nb/caseweave`；正式提交前需要创建并推送到这个公开仓库，或改成你实际使用的公开仓库地址。

```bash
moon check
moon build
moon test
moon publish --dry-run
moon publish
```

## 许可证

本项目使用 MIT License。第三方依赖当前为零；如后续加入外部代码或素材，必须在 `NOTICE.md` 中记录来源、版本和许可证。
