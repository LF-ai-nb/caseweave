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

///|
fn deployment_scenario_source() -> String {
  "name: Deployment risk matrix\n" +
  "strength: 2\n" +
  "max-candidates: 1000\n" +
  "minimize: true\n" +
  "param os: linux, windows, macos\n" +
  "param browser: chrome, firefox, safari\n" +
  "param auth: password, oidc\n" +
  "param region: cn, eu, us\n" +
  "constraint safari requires macos: browser == safari => os == macos\n" +
  "exclude: os=windows, browser=safari\n" +
  "include: os=linux, browser=chrome, auth=oidc, region=cn\n" +
  "risk browser=safari: 4: browser-specific rendering risk\n" +
  "risk os=macos, browser=safari: 9: Safari path must stay visible\n"
}

///|
fn deployment_scenario() -> @caseweave.ScenarioSpec {
  match @caseweave.ScenarioSpec::parse(deployment_scenario_source()) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
test "scenario spec parses model constraints cases and risks" {
  let spec = deployment_scenario()
  assert_eq(spec.name, "Deployment risk matrix")
  assert_eq(spec.model.parameter_count(), 4)
  assert_eq(spec.model.combination_count(), 54L)
  assert_eq(spec.options.strength, 2)
  assert_eq(spec.options.max_candidates, 1000)
  assert_true(spec.options.minimize)
  assert_eq(spec.constraints.length(), 2)
  assert_eq(spec.included_cases.length(), 1)
  assert_eq(spec.excluded_patterns.length(), 1)
  assert_eq(spec.value_risks.length(), 1)
  assert_eq(spec.interaction_risks.length(), 1)
  assert_true(spec.summary().contains("risks=2"))
}

///|
test "scenario run keeps included cases and completes coverage" {
  let spec = deployment_scenario()
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(run.coverage.is_complete())
  assert_true(run.cases.length() >= run.suite.length())
  assert_eq(run.included_case_count, 1)
  assert_eq(run.cases[0].value_for(spec.model, "os"), Some("linux"))
  assert_eq(run.cases[0].value_for(spec.model, "browser"), Some("chrome"))
  assert_true(run.summary().contains("coverage=100"))
  assert_true(run.cases_markdown().contains("| # | os | browser |"))
}

///|
test "scenario excludes forbidden patterns from generated output" {
  let spec = deployment_scenario()
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  for test_case in run.cases {
    assert_false(
      test_case.value_for(spec.model, "os") == Some("windows") &&
      test_case.value_for(spec.model, "browser") == Some("safari"),
    )
    if test_case.value_for(spec.model, "browser") == Some("safari") {
      assert_eq(test_case.value_for(spec.model, "os"), Some("macos"))
    }
  }
}

///|
test "scenario ranks generated cases by business risk hints" {
  let spec = deployment_scenario()
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(run.ranked_cases.length() == run.cases.length())
  assert_true(run.ranked_cases[0].score >= 13)
  assert_true(run.ranked_cases[0].reasons.length() >= 2)
  assert_true(run.risk_markdown(top=3).contains("Safari path"))
  let safari = @caseweave.TestCase::new(["macos", "safari", "oidc", "eu"])
  let score = match spec.score_case(safari) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_eq(score.score, 13)
}

///|
test "scenario gate turns coverage and risk into CI style reports" {
  let spec = deployment_scenario()
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  let report = run.evaluate_gate(spec, gate=@caseweave.ScenarioGate::strict())
  assert_true(report.is_passed())
  assert_true(report.summary().contains("gate=pass"))
  assert_true(report.failure_text().contains("no gate failures"))
  assert_true(report.warning_text().contains("no gate warnings"))
  assert_true(report.to_markdown().contains("CaseWeave Gate Report"))
  assert_true(
    @caseweave.ScenarioGate::strict().describe().contains("coverage=complete"),
  )
}

///|
test "scenario gate reports case budget and risk failures" {
  let spec = deployment_scenario()
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  let gate = @caseweave.ScenarioGate::{
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases: 1000,
    max_cases: 1,
    min_top_risk_score: 99,
    min_positive_risk_cases: 99,
    allow_warnings: true,
  }
  let report = run.evaluate_gate(spec, gate~)
  assert_false(report.is_passed())
  assert_true(report.failures.length() >= 4)
  assert_true(
    report.failure_text().contains("too few cases") ||
    report.failure_text().contains("too few"),
  )
  let normalized = run.evaluate_normalized_gate(spec, @caseweave.ScenarioGate::{
    require_complete_coverage: true,
    max_missing_interactions: -1,
    min_cases: -1,
    max_cases: -1,
    min_top_risk_score: -1,
    min_positive_risk_cases: -1,
    allow_warnings: true,
  })
  assert_false(normalized.is_passed())
}

///|
test "scenario lint explains weak scenario specs" {
  let source = "name: weak\n" + "strength: 1\n" + "param os: linux\n"
  let spec = match @caseweave.ScenarioSpec::parse(source) {
    Ok(value) => value
    Err(_) => panic()
  }
  let warnings = spec.lint()
  assert_true(warnings.length() >= 4)
  let text = spec.lint_text()
  assert_true(text.contains("No constraints"))
  assert_true(text.contains("No risk hints"))
  assert_true(text.contains("Strength 1"))
  assert_true(text.contains("one value"))
}

///|
test "scenario parser supports quoted csv values" {
  let source = "name: quoted\n" +
    "strength: 1\n" +
    "param env: \"prod,blue\", qa\n" +
    "param browser: \"edge\\\"dev\", firefox\n" +
    "include: env=\"prod,blue\", browser=\"edge\\\"dev\"\n" +
    "risk env=\"prod,blue\": 2: comma value\n"
  let spec = match @caseweave.ScenarioSpec::parse(source) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_eq(spec.model.value_index(0, "prod,blue"), Some(0))
  assert_eq(spec.model.value_index(1, "edge\"dev"), Some(0))
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(run.cases[0].assignment_text(spec.model).contains("prod,blue"))
  assert_true(run.ranked_cases[0].score >= 2)
}

///|
test "scenario parser reports malformed inputs" {
  assert_true(
    @caseweave.ScenarioSpec::parse("name only") is Err(ParseError(_, _)),
  )
  assert_true(
    @caseweave.ScenarioSpec::parse(
      "name: bad\nstrength: 1\nparam os: linux\nrisk browser=chrome: 2\n",
    )
    is Err(UnknownParameter("browser")),
  )
  assert_true(
    @caseweave.ScenarioSpec::parse(
      "name: bad\nstrength: 2\nparam os: linux\ninclude: os=linux\n",
    )
    is Err(InvalidStrength(2, 1)),
  )
  assert_true(
    @caseweave.ScenarioSpec::parse(
      "name: bad\nstrength: 1\nparam os: \"unterminated\n",
    )
    is Err(ParseError(_, _)),
  )
}

///|
test "repair planner completes incomplete external suites" {
  let model = sample_model()
  let seed = [@caseweave.TestCase::new(["linux", "chrome", "password"])]
  let plan = match @caseweave.plan_repair(model, seed) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(plan.is_complete())
  assert_true(plan.addition_count() > 0)
  assert_eq(plan.final_missing, 0)
  assert_true(plan.initial_missing > 0)
  assert_true(plan.merged_cases().length() > seed.length())
  assert_true(plan.summary().contains("repair=complete"))
  assert_true(plan.additions_markdown().contains("| # | os | browser | auth |"))
  assert_true(plan.steps_markdown(top=2).contains("covers"))
  assert_true(plan.to_markdown().contains("CaseWeave Repair Plan"))
  let gate = plan.evaluate_repair_gate()
  assert_true(gate.is_passed())
  assert_true(gate.summary().contains("repair-gate=pass"))
  assert_true(gate.failure_text().contains("no repair gate failures"))
}

///|
test "repair planner respects constraints while adding cases" {
  let model = sample_model()
  let safari_rule = match
    @caseweave.Constraint::parse(
      "safari only on macOS", "browser == safari => os == macos",
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
  let plan = match
    @caseweave.plan_repair(
      model,
      [@caseweave.TestCase::new(["linux", "chrome", "password"])],
      constraints=[safari_rule],
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(plan.is_complete())
  for test_case in plan.additions() {
    if test_case.value_for(model, "browser") == Some("safari") {
      assert_eq(test_case.value_for(model, "os"), Some("macos"))
    }
  }
}

///|
test "scenario repair planner uses risk hints for tie breaking and reports" {
  let spec = deployment_scenario()
  let seed = [@caseweave.TestCase::new(["linux", "chrome", "oidc", "cn"])]
  let plan = match spec.plan_repair(seed) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(plan.is_complete())
  guard plan.highest_risk_step() is Some(highest) else {
    fail("repair should suggest at least one step")
  }
  assert_true(highest.risk_score >= 13)
  assert_true(plan.risk_summary().contains("highest-risk"))
  assert_true(plan.steps_markdown().contains("Safari path"))
  guard plan.largest_gain_step() is Some(largest) else {
    fail("repair should have a largest gain step")
  }
  assert_true(largest.newly_covered.length() >= 1)
}

///|
test "repair gate reports incomplete plans and budget failures" {
  let model = sample_model()
  let seed = [@caseweave.TestCase::new(["linux", "chrome", "password"])]
  let partial = match
    @caseweave.plan_repair(model, seed, options=@caseweave.RepairOptions::{
      strength: 2,
      max_candidates: 100000,
      max_suggestions: 0,
    }) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_false(partial.is_complete())
  let partial_gate = partial.evaluate_repair_gate()
  assert_false(partial_gate.is_passed())
  assert_true(partial_gate.failure_text().contains("incomplete"))
  let complete = match @caseweave.plan_repair(model, seed) {
    Ok(value) => value
    Err(_) => panic()
  }
  let budget_gate = complete.evaluate_repair_gate(
    gate=@caseweave.RepairGate::budget(0),
  )
  assert_false(budget_gate.is_passed())
  assert_true(budget_gate.to_markdown().contains("Repair Gate"))
  let best_effort = partial.evaluate_repair_gate(
    gate=@caseweave.RepairGate::best_effort(0, partial.final_missing),
  )
  assert_true(best_effort.is_passed())
}

///|
test "repair options validate suggestion limits and normalize values" {
  assert_true(
    @caseweave.plan_repair(sample_model(), [], options=@caseweave.RepairOptions::{
      strength: 2,
      max_candidates: 100000,
      max_suggestions: -1,
    })
    is Err(InvalidSuggestionLimit(-1)),
  )
  let normalized = @caseweave.RepairOptions::{
    strength: -10,
    max_candidates: -20,
    max_suggestions: -30,
  }.normalize()
  assert_eq(normalized.strength, 1)
  assert_eq(normalized.max_candidates, 1)
  assert_eq(normalized.max_suggestions, 0)
  assert_eq(
    @caseweave.RepairOptions::from_generation(
      @caseweave.GenerationOptions::pairwise(),
    ).strength,
    2,
  )
}
