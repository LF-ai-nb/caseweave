///|
/// CI-oriented policy for generated scenario runs. It turns coverage, risk and
/// scenario-lint facts into a small pass/fail report that can be printed in a
/// release job.
pub(all) struct ScenarioGate {
  require_complete_coverage : Bool
  max_missing_interactions : Int
  min_cases : Int
  max_cases : Int
  min_top_risk_score : Int
  min_positive_risk_cases : Int
  allow_warnings : Bool
}

///|
pub(all) enum GateFailureKind {
  IncompleteCoverage(Int, Int)
  TooManyMissingInteractions(Int, Int)
  TooFewCases(Int, Int)
  TooManyCases(Int, Int)
  TopRiskTooLow(Int, Int)
  TooFewPositiveRiskCases(Int, Int)
  ScenarioWarnings(Int)
} derive(Debug, Eq)

///|
pub(all) struct GateFailure {
  kind : GateFailureKind
  message : String
} derive(Debug, Eq)

///|
pub(all) struct GateReport {
  passed : Bool
  failures : Array[GateFailure]
  warnings : Array[SpecWarning]
  coverage : CoverageReport
  case_count : Int
  top_risk_score : Int
  positive_risk_cases : Int
}

///|
pub fn ScenarioGate::default() -> ScenarioGate {
  {
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases: 1,
    max_cases: 100000,
    min_top_risk_score: 0,
    min_positive_risk_cases: 0,
    allow_warnings: true,
  }
}

///|
pub fn ScenarioGate::strict() -> ScenarioGate {
  {
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases: 1,
    max_cases: 100000,
    min_top_risk_score: 1,
    min_positive_risk_cases: 1,
    allow_warnings: false,
  }
}

///|
pub fn ScenarioGate::coverage_only() -> ScenarioGate {
  {
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases: 0,
    max_cases: 100000,
    min_top_risk_score: 0,
    min_positive_risk_cases: 0,
    allow_warnings: true,
  }
}

///|
pub fn ScenarioGate::with_case_budget(
  min_cases : Int,
  max_cases : Int,
) -> ScenarioGate {
  {
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases,
    max_cases,
    min_top_risk_score: 0,
    min_positive_risk_cases: 0,
    allow_warnings: true,
  }
}

///|
pub fn ScenarioGate::with_risk_floor(
  min_top_risk_score : Int,
  min_positive_risk_cases : Int,
) -> ScenarioGate {
  {
    require_complete_coverage: true,
    max_missing_interactions: 0,
    min_cases: 1,
    max_cases: 100000,
    min_top_risk_score,
    min_positive_risk_cases,
    allow_warnings: true,
  }
}

///|
pub fn ScenarioRun::evaluate_gate(
  self : ScenarioRun,
  spec : ScenarioSpec,
  gate? : ScenarioGate = ScenarioGate::default(),
) -> GateReport {
  let failures : Array[GateFailure] = []
  let warnings = spec.lint()
  let top_score = self.top_risk_score()
  let positive_risk_cases = self.positive_risk_case_count()
  if gate.require_complete_coverage && !self.coverage.is_complete() {
    failures.push({
      kind: IncompleteCoverage(
        self.coverage.covered_interactions,
        self.coverage.total_interactions,
      ),
      message: "Coverage is incomplete: \{self.coverage.covered_interactions}/\{self.coverage.total_interactions} interactions are covered.",
    })
  }
  if self.coverage.missing.length() > gate.max_missing_interactions {
    failures.push({
      kind: TooManyMissingInteractions(
        self.coverage.missing.length(),
        gate.max_missing_interactions,
      ),
      message: "Missing interactions exceed the gate: \{self.coverage.missing.length()} > \{gate.max_missing_interactions}.",
    })
  }
  if self.cases.length() < gate.min_cases {
    failures.push({
      kind: TooFewCases(self.cases.length(), gate.min_cases),
      message: "The run has too few cases: \{self.cases.length()} < \{gate.min_cases}.",
    })
  }
  if self.cases.length() > gate.max_cases {
    failures.push({
      kind: TooManyCases(self.cases.length(), gate.max_cases),
      message: "The run has too many cases for the configured budget: \{self.cases.length()} > \{gate.max_cases}.",
    })
  }
  if top_score < gate.min_top_risk_score {
    failures.push({
      kind: TopRiskTooLow(top_score, gate.min_top_risk_score),
      message: "The highest risk score is below the gate: \{top_score} < \{gate.min_top_risk_score}.",
    })
  }
  if positive_risk_cases < gate.min_positive_risk_cases {
    failures.push({
      kind: TooFewPositiveRiskCases(
        positive_risk_cases,
        gate.min_positive_risk_cases,
      ),
      message: "Too few generated cases match risk hints: \{positive_risk_cases} < \{gate.min_positive_risk_cases}.",
    })
  }
  if !gate.allow_warnings && warnings.length() > 0 {
    failures.push({
      kind: ScenarioWarnings(warnings.length()),
      message: "Scenario lint produced \{warnings.length()} warning(s), and this gate treats warnings as failures.",
    })
  }
  {
    passed: failures.length() == 0,
    failures,
    warnings,
    coverage: self.coverage,
    case_count: self.cases.length(),
    top_risk_score: top_score,
    positive_risk_cases,
  }
}

///|
pub fn ScenarioRun::top_risk_score(self : ScenarioRun) -> Int {
  if self.ranked_cases.length() == 0 {
    0
  } else {
    self.ranked_cases[0].score
  }
}

///|
pub fn ScenarioRun::positive_risk_case_count(self : ScenarioRun) -> Int {
  let mut count = 0
  for item in self.ranked_cases {
    if item.score > 0 {
      count = count + 1
    }
  }
  count
}

///|
pub fn GateReport::is_passed(self : GateReport) -> Bool {
  self.passed
}

///|
pub fn GateReport::summary(self : GateReport) -> String {
  let status = if self.passed { "pass" } else { "fail" }
  "gate=\{status}, failures=\{self.failures.length()}, warnings=\{self.warnings.length()}, cases=\{self.case_count}, coverage=\{self.coverage.coverage_percent}%, top-risk=\{self.top_risk_score}, risk-cases=\{self.positive_risk_cases}"
}

///|
pub fn GateReport::failure_text(self : GateReport) -> String {
  if self.failures.length() == 0 {
    return "no gate failures\n"
  }
  let builder = StringBuilder::new()
  for failure in self.failures {
    builder.write_string("- ")
    builder.write_string(failure.message)
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
pub fn GateReport::warning_text(self : GateReport) -> String {
  if self.warnings.length() == 0 {
    return "no gate warnings\n"
  }
  let builder = StringBuilder::new()
  for warning in self.warnings {
    builder.write_string("- ")
    builder.write_string(warning.message)
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
pub fn GateReport::to_markdown(self : GateReport) -> String {
  let builder = StringBuilder::new()
  builder.write_string("## CaseWeave Gate Report\n\n")
  builder.write_string("- status: ")
  builder.write_string(if self.passed { "pass" } else { "fail" })
  builder.write_char('\n')
  builder.write_string("- cases: ")
  builder.write_string(self.case_count.to_string())
  builder.write_char('\n')
  builder.write_string("- coverage: ")
  builder.write_string(self.coverage.coverage_percent.to_string())
  builder.write_string("%\n")
  builder.write_string("- top risk score: ")
  builder.write_string(self.top_risk_score.to_string())
  builder.write_char('\n')
  builder.write_string("- positive risk cases: ")
  builder.write_string(self.positive_risk_cases.to_string())
  builder.write_string("\n\n")
  builder.write_string("### Failures\n\n")
  if self.failures.length() == 0 {
    builder.write_string("No gate failures.\n\n")
  } else {
    for failure in self.failures {
      builder.write_string("- ")
      builder.write_string(failure.message)
      builder.write_char('\n')
    }
    builder.write_char('\n')
  }
  builder.write_string("### Warnings\n\n")
  if self.warnings.length() == 0 {
    builder.write_string("No scenario warnings.\n")
  } else {
    for warning in self.warnings {
      builder.write_string("- ")
      builder.write_string(warning.message)
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
pub fn ScenarioGate::describe(self : ScenarioGate) -> String {
  let builder = StringBuilder::new()
  builder.write_string("coverage=")
  builder.write_string(
    if self.require_complete_coverage {
      "complete"
    } else {
      "best-effort"
    },
  )
  builder.write_string(", max-missing=")
  builder.write_string(self.max_missing_interactions.to_string())
  builder.write_string(", case-budget=")
  builder.write_string(self.min_cases.to_string())
  builder.write_string("..")
  builder.write_string(self.max_cases.to_string())
  builder.write_string(", min-top-risk=")
  builder.write_string(self.min_top_risk_score.to_string())
  builder.write_string(", min-risk-cases=")
  builder.write_string(self.min_positive_risk_cases.to_string())
  builder.write_string(", warnings=")
  builder.write_string(if self.allow_warnings { "allowed" } else { "fail" })
  builder.to_string()
}

///|
pub fn ScenarioGate::normalize(self : ScenarioGate) -> ScenarioGate {
  {
    require_complete_coverage: self.require_complete_coverage,
    max_missing_interactions: clamp_non_negative(self.max_missing_interactions),
    min_cases: clamp_non_negative(self.min_cases),
    max_cases: if self.max_cases < 0 {
      0
    } else {
      self.max_cases
    },
    min_top_risk_score: clamp_non_negative(self.min_top_risk_score),
    min_positive_risk_cases: clamp_non_negative(self.min_positive_risk_cases),
    allow_warnings: self.allow_warnings,
  }
}

///|
fn clamp_non_negative(value : Int) -> Int {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
pub fn ScenarioRun::evaluate_normalized_gate(
  self : ScenarioRun,
  spec : ScenarioSpec,
  gate : ScenarioGate,
) -> GateReport {
  self.evaluate_gate(spec, gate=gate.normalize())
}
