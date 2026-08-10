///|
fn sample_model() -> @caseweave.Model {
  match
    @caseweave.Model::new([
      @caseweave.Parameter::new("os", ["linux", "windows", "macos"]),
      @caseweave.Parameter::new("browser", ["chrome", "firefox", "safari"]),
      @caseweave.Parameter::new("auth", ["password", "oidc"]),
    ]) {
    Ok(model) => model
    Err(_) => panic()
  }
}

///|
test "model keeps parameter order and computes Cartesian size" {
  let model = sample_model()
  assert_eq(model.parameter_count(), 3)
  assert_eq(model.combination_count(), 18L)
  assert_eq(model.parameter_index("browser"), Some(1))
  assert_eq(model.value_index(0, "macos"), Some(2))
  assert_eq(model.parameter(20), None)
}

///|
test "model rejects empty and duplicate dimensions" {
  assert_true(@caseweave.Model::new([]) is Err(EmptyModel))
  assert_true(
    @caseweave.Model::new([
      @caseweave.Parameter::new("os", ["linux"]),
      @caseweave.Parameter::new("os", ["windows"]),
    ])
    is Err(DuplicateParameter("os")),
  )
  assert_true(
    @caseweave.Model::new([@caseweave.Parameter::new("os", ["linux", "linux"])])
    is Err(DuplicateValue("os", "linux")),
  )
}

///|
test "test case lookup is model aware" {
  let model = sample_model()
  let row = @caseweave.TestCase::new(["linux", "chrome", "oidc"])
  assert_eq(row.value_for(model, "auth"), Some("oidc"))
  assert_eq(row.value_for(model, "missing"), None)
  assert_true(model.validate_case(row) is Ok(_))
  assert_true(
    model.validate_case(@caseweave.TestCase::new(["linux"]))
    is Err(InvalidCaseWidth(3, 1)),
  )
}

///|
test "constraint parser respects precedence and implication" {
  let parsed = @caseweave.Constraint::parse(
    "safari only on macOS", "browser == \"safari\" => os == \"macos\" and auth != \"password\"",
  )
  guard parsed is Ok(constraint) else { fail("constraint should parse") }
  debug_inspect(
    constraint.expression,
    content=(
      #|Implies(
      #|  Equal("browser", "safari"),
      #|  And(Equal("os", "macos"), NotEqual("auth", "password")),
      #|)
    ),
  )
}

///|
test "constraint parser supports membership and word operators" {
  let parsed = @caseweave.Constraint::parse(
    "supported", "os in [\"linux\", windows] and browser not in [\"safari\"]",
  )
  guard parsed is Ok(constraint) else { fail("constraint should parse") }
  assert_true(constraint.validate(sample_model()) is Ok(_))
  assert_eq(
    constraint.matches(
      sample_model(),
      @caseweave.TestCase::new(["windows", "chrome", "oidc"]),
    ),
    Ok(true),
  )
  assert_eq(
    constraint.matches(
      sample_model(),
      @caseweave.TestCase::new(["macos", "safari", "oidc"]),
    ),
    Ok(false),
  )
}

///|
test "constraint parser reports malformed input" {
  assert_true(
    @caseweave.Constraint::parse("bad", "os = \"linux\"")
    is Err(ParseError(_, _)),
  )
  assert_true(
    @caseweave.Constraint::parse("bad", "os in []") is Err(ParseError(_, _)),
  )
  assert_true(
    @caseweave.Constraint::parse("bad", "os == \"unterminated")
    is Err(ParseError(_, _)),
  )
}

///|
test "constraint validation catches names and values" {
  let unknown_parameter = @caseweave.Constraint::new(
    "bad parameter",
    Equal("platform", "linux"),
  )
  assert_eq(
    unknown_parameter.validate(sample_model()),
    Err(UnknownParameter("platform")),
  )
  let unknown_value = @caseweave.Constraint::new(
    "bad value",
    Equal("os", "plan9"),
  )
  assert_eq(
    unknown_value.validate(sample_model()),
    Err(UnknownValue("os", "plan9")),
  )
}

///|
test "generator creates deterministic complete pairwise suites" {
  let model = sample_model()
  let first = match @caseweave.generate(model) {
    Ok(suite) => suite
    Err(_) => panic()
  }
  let second = match @caseweave.generate(model) {
    Ok(suite) => suite
    Err(_) => panic()
  }
  let report = match @caseweave.audit(model, first.cases()) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(report.is_complete())
  assert_eq(first.to_csv(model), second.to_csv(model))
  assert_eq(first.strength(), 2)
  assert_true(first.length() < 18)
}

///|
test "generator supports strength one and full strength" {
  let model = sample_model()
  let strength_one = match
    @caseweave.generate(model, options=@caseweave.GenerationOptions::{
      strength: 1,
      max_candidates: 100000,
      minimize: true,
    }) {
    Ok(suite) => suite
    Err(_) => panic()
  }
  let one_report = match
    @caseweave.audit(model, strength_one.cases(), strength=1) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(one_report.is_complete())
  let strength_three = match
    @caseweave.generate(model, options=@caseweave.GenerationOptions::{
      strength: 3,
      max_candidates: 100000,
      minimize: true,
    }) {
    Ok(suite) => suite
    Err(_) => panic()
  }
  assert_eq(strength_three.length(), 18)
}

///|
test "generator respects constraints and audits constrained coverage" {
  let model = sample_model()
  let safari_rule = match
    @caseweave.Constraint::parse(
      "safari only on macOS", "browser == safari => os == macos",
    ) {
    Ok(rule) => rule
    Err(_) => panic()
  }
  let suite = match @caseweave.generate(model, constraints=[safari_rule]) {
    Ok(value) => value
    Err(_) => panic()
  }
  for test_case in suite.cases() {
    if test_case.value_for(model, "browser") == Some("safari") {
      assert_eq(test_case.value_for(model, "os"), Some("macos"))
    }
  }
  let report = match
    @caseweave.audit(model, suite.cases(), constraints=[safari_rule]) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(report.is_complete())
}

///|
test "generator reports impossible models and candidate limits" {
  let model = sample_model()
  assert_true(
    @caseweave.generate(model, constraints=[
      @caseweave.Constraint::new("impossible", Never),
    ])
    is Err(NoValidCases),
  )
  assert_true(
    @caseweave.generate(model, options=@caseweave.GenerationOptions::{
      strength: 2,
      max_candidates: 2,
      minimize: true,
    })
    is Err(CandidateLimitExceeded(2)),
  )
}

///|
test "coverage audit names missing interactions" {
  let model = sample_model()
  let report = match
    @caseweave.audit(model, [
      @caseweave.TestCase::new(["linux", "chrome", "password"]),
    ]) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_false(report.is_complete())
  assert_true(report.missing.length() > 0)
  assert_true(report.summary().contains("missing="))
  assert_true(report.missing_text().contains("browser="))
}

///|
test "exporters escape csv json and markdown" {
  let model = match
    @caseweave.Model::new([
      @caseweave.Parameter::new("env,name", ["prod,\"blue\"", "qa"]),
      @caseweave.Parameter::new("browser", ["edge|dev", "fire\nfox"]),
    ]) {
    Ok(value) => value
    Err(_) => panic()
  }
  let cases = [@caseweave.TestCase::new(["prod,\"blue\"", "edge|dev"])]
  assert_eq(
    @caseweave.cases_to_csv(model, cases),
    "\"env,name\",browser\n\"prod,\"\"blue\"\"\",edge|dev\n",
  )
  assert_eq(
    @caseweave.cases_to_markdown(model, cases),
    "| # | env,name | browser |\n| --- | --- | --- |\n| 1 | prod,\"blue\" | edge\\|dev |\n",
  )
  let suite = match @caseweave.generate(model) {
    Ok(value) => value
    Err(_) => panic()
  }
  let json = suite.to_json(model)
  assert_true(json.contains("prod,\\\"blue\\\""))
  assert_true(json.contains("fire\\nfox"))
}
