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
