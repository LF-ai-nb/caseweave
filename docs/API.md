# API 说明

## 建模

`Parameter::new(name, values)` 定义一个维度。`Model::new(parameters)` 会检查空模型、重复参数、空值和重复值。

```moonbit
let model = @caseweave.Model::new([
  @caseweave.Parameter::new("os", ["linux", "windows", "macos"]),
  @caseweave.Parameter::new("browser", ["chrome", "firefox", "safari"]),
])
```

`TestCase::new(values)` 按模型顺序保存一条用例。可以用 `value_for(model, parameter)` 按参数名读取。

## 约束

约束可以手写 AST，也可以用字符串 DSL 解析。

```moonbit
let rule = @caseweave.Constraint::parse(
  "Safari is only supported on macOS",
  "browser == safari => os == macos",
)
```

支持的语法：

- `parameter == value`
- `parameter != value`
- `parameter in [a, b, "quoted value"]`
- `parameter not in [a, b]`
- `and` / `&&`
- `or` / `||`
- `not` / `!`
- `=>`
- `true` / `false`
- 括号

## 生成

`generate(model, constraints?, options?)` 返回 `Result[Suite, CaseWeaveError]`。

```moonbit
let suite = @caseweave.generate(
  model,
  constraints=[rule],
  options=@caseweave.GenerationOptions::{
    strength: 2,
    max_candidates: 100000,
    minimize: true,
  },
)
```

`GenerationOptions::default()` 默认使用 pairwise，候选上限为 `100000`，并启用冗余删除。

## 审计

`audit(model, cases, strength?, constraints?, max_candidates?)` 可以检查外部测试套件是否覆盖所有可行交互。

```moonbit
let report = @caseweave.audit(model, suite.cases(), strength=2)
assert_true(report.is_complete())
println(report.summary())
```

## 导出

生成后的 `Suite` 可以导出为多种文本格式。

```moonbit
println(suite.to_csv(model))
println(suite.to_json(model))
println(suite.to_markdown(model))
```

如果用例来自外部，也可以使用：

- `cases_to_csv(model, cases)`
- `cases_to_markdown(model, cases)`

所有导出函数保持参数顺序稳定，便于在 CI 中比较输出。

## 场景规格

`ScenarioSpec::parse(source)` 支持把参数、约束、必须包含的业务样例、排除样例和风险提示写成一份行式文本规格。

```moonbit
let spec = @caseweave.ScenarioSpec::parse(
  "name: Deployment risk matrix\n" +
  "strength: 2\n" +
  "param os: linux, windows, macos\n" +
  "param browser: chrome, firefox, safari\n" +
  "constraint safari requires macos: browser == safari => os == macos\n" +
  "include: os=linux, browser=chrome\n" +
  "risk browser=safari: 4: rendering risk\n",
)
```

常用指令：

- `name:` / `title:`：场景名称
- `strength:`：覆盖强度
- `max-candidates:`：候选枚举上限
- `minimize:`：是否删除冗余行
- `param name:`：参数和值列表，值支持 CSV 风格引号
- `constraint label:`：复用约束 DSL
- `include:`：必须保留的完整业务样例
- `exclude:`：要排除的部分或完整组合，会转成约束
- `risk selector:`：给单值或多值交互添加风险权重

`spec.run()` 会生成矩阵、合并 `include` 样例、执行覆盖审计，并对用例按风险分数排序。

```moonbit
let run = spec.run().unwrap()
println(run.summary())
println(run.risk_markdown(top=5))
```

## 场景 lint 与门禁

`spec.lint()` 返回非阻断告警，例如没有约束、没有风险提示、强度为 1、候选上限低于笛卡尔空间或某个参数只有一个值。

```moonbit
println(spec.lint_text())
```

`ScenarioGate` 可以把一次运行变成 CI 质量门禁：

```moonbit
let report = run.evaluate_gate(
  spec,
  gate=@caseweave.ScenarioGate::strict(),
)
assert_true(report.is_passed())
println(report.to_markdown())
```

内置门禁：

- `ScenarioGate::default()`：要求覆盖完整，允许 lint 告警。
- `ScenarioGate::strict()`：要求覆盖完整、至少一个风险样例、且 lint 告警失败。
- `ScenarioGate::coverage_only()`：只关注覆盖完整性。
- `ScenarioGate::with_case_budget(min, max)`：检查用例数量预算。
- `ScenarioGate::with_risk_floor(top, count)`：检查风险分数和命中风险提示的用例数。
