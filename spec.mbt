///|
/// A compact, line-oriented scenario format for teams that want to keep their
/// covering-array model beside design docs, issues or CI configuration.
pub(all) struct ScenarioSpec {
  name : String
  model : Model
  constraints : Array[Constraint]
  options : GenerationOptions
  included_cases : Array[TestCase]
  excluded_patterns : Array[CasePattern]
  value_risks : Array[ValueRisk]
  interaction_risks : Array[InteractionRisk]
}

///|
/// A partial assignment such as `os=linux, browser=chrome`.
pub(all) struct CasePattern {
  choices : Array[NamedChoice]
} derive(Debug, Eq)

///|
/// A risk attached to one parameter value.
pub(all) struct ValueRisk {
  choice : NamedChoice
  weight : Int
  note : String
} derive(Debug, Eq)

///|
/// A risk attached to an interaction pattern.
pub(all) struct InteractionRisk {
  pattern : CasePattern
  weight : Int
  note : String
} derive(Debug, Eq)

///|
/// Risk score for one concrete case.
pub(all) struct CaseRisk {
  score : Int
  reasons : Array[String]
} derive(Debug, Eq)

///|
/// A generated case ordered by descending risk score.
pub(all) struct RankedCase {
  rank : Int
  index : Int
  test_case : TestCase
  score : Int
  reasons : Array[String]
} derive(Debug, Eq)

///|
/// End-to-end execution result for a parsed scenario spec.
pub(all) struct ScenarioRun {
  spec_name : String
  model : Model
  suite : Suite
  cases : Array[TestCase]
  included_case_count : Int
  coverage : CoverageReport
  ranked_cases : Array[RankedCase]
}

///|
/// Non-blocking quality hints for scenario specifications.
pub(all) enum SpecWarningKind {
  NoConstraints
  NoRiskHints
  NoIncludedCases
  StrengthOne
  CandidateLimitBelowCartesian(Int64, Int)
  SingleValueParameter(String)
} derive(Debug, Eq)

///|
pub(all) struct SpecWarning {
  kind : SpecWarningKind
  message : String
} derive(Debug, Eq)

///|
priv struct TextParts {
  left : String
  right : String
}

///|
priv struct RawConstraintLine {
  label : String
  source : String
}

///|
priv struct RawPatternLine {
  pattern : CasePattern
  line : Int
}

///|
priv struct RawRiskLine {
  pattern : CasePattern
  weight : Int
  note : String
  line : Int
}

///|
priv struct RawSpecBuilder {
  mut name : String
  parameters : Array[Parameter]
  constraints : Array[RawConstraintLine]
  includes : Array[RawPatternLine]
  excludes : Array[RawPatternLine]
  risks : Array[RawRiskLine]
  mut strength : Int
  mut max_candidates : Int
  mut minimize : Bool
}

///|
fn RawSpecBuilder::new() -> RawSpecBuilder {
  {
    name: "CaseWeave scenario",
    parameters: [],
    constraints: [],
    includes: [],
    excludes: [],
    risks: [],
    strength: 2,
    max_candidates: 100000,
    minimize: true,
  }
}

///|
pub fn ScenarioSpec::parse(
  source : String,
) -> Result[ScenarioSpec, CaseWeaveError] {
  parse_scenario_spec(source)
}

///|
pub fn parse_scenario_spec(
  source : String,
) -> Result[ScenarioSpec, CaseWeaveError] {
  let builder = RawSpecBuilder::new()
  let lines = split_lines(source)
  for line_index = 0; line_index < lines.length(); line_index = line_index + 1 {
    match parse_spec_line(builder, line_index + 1, lines[line_index]) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  builder.finish()
}

///|
fn RawSpecBuilder::finish(
  self : RawSpecBuilder,
) -> Result[ScenarioSpec, CaseWeaveError] {
  let model = match Model::new(self.parameters) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if self.strength < 1 || self.strength > model.parameter_count() {
    return Err(InvalidStrength(self.strength, model.parameter_count()))
  }
  if self.max_candidates < 1 {
    return Err(InvalidCandidateLimit(self.max_candidates))
  }
  let constraints : Array[Constraint] = []
  for raw in self.constraints {
    let parsed = match Constraint::parse(raw.label, raw.source) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match parsed.validate(model) {
      Err(error) => return Err(error)
      Ok(_) => constraints.push(parsed)
    }
  }
  let excluded_patterns : Array[CasePattern] = []
  for raw in self.excludes {
    match raw.pattern.validate(model) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let label = "exclude line \{raw.line}: \{raw.pattern.to_text()}"
    let constraint = match raw.pattern.to_exclusion_constraint(label) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match constraint.validate(model) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    constraints.push(constraint)
    excluded_patterns.push(raw.pattern)
  }
  let included_cases : Array[TestCase] = []
  for raw in self.includes {
    let test_case = match raw.pattern.to_case(model, line_no=raw.line) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match
      validate_case_against_constraints(
        model,
        test_case,
        constraints,
        included_cases.length(),
      ) {
      Err(error) => return Err(error)
      Ok(_) => included_cases.push(test_case)
    }
  }
  let value_risks : Array[ValueRisk] = []
  let interaction_risks : Array[InteractionRisk] = []
  for raw in self.risks {
    match raw.pattern.validate(model) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if raw.weight <= 0 {
      return Err(ParseError(raw.line, "risk weight must be positive"))
    }
    if raw.pattern.choices.length() == 1 {
      value_risks.push({
        choice: raw.pattern.choices[0],
        weight: raw.weight,
        note: raw.note,
      })
    } else {
      interaction_risks.push({
        pattern: raw.pattern,
        weight: raw.weight,
        note: raw.note,
      })
    }
  }
  Ok({
    name: self.name,
    model,
    constraints,
    options: {
      strength: self.strength,
      max_candidates: self.max_candidates,
      minimize: self.minimize,
    },
    included_cases,
    excluded_patterns,
    value_risks,
    interaction_risks,
  })
}

///|
fn validate_case_against_constraints(
  model : Model,
  test_case : TestCase,
  constraints : Array[Constraint],
  case_index : Int,
) -> Result[Unit, CaseWeaveError] {
  match model.validate_case(test_case) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for constraint in constraints {
    match constraint.matches(model, test_case) {
      Err(error) => return Err(error)
      Ok(true) => ()
      Ok(false) => return Err(ConstraintViolation(case_index, constraint.label))
    }
  }
  Ok(())
}

///|
fn parse_spec_line(
  builder : RawSpecBuilder,
  line_no : Int,
  source : String,
) -> Result[Unit, CaseWeaveError] {
  let line = trim_text(source)
  if line.length() == 0 {
    return Ok(())
  }
  if starts_with_text(line, "#") {
    return Ok(())
  }
  let parts = match split_once_char(line, ':') {
    None => return Err(ParseError(line_no, "expected ':' in scenario line"))
    Some(value) => value
  }
  let head = trim_text(parts.left)
  let body = trim_text(parts.right)
  if head.length() == 0 {
    return Err(ParseError(line_no, "missing directive name"))
  }
  if directive_is(head, "name") || directive_is(head, "title") {
    if body.length() == 0 {
      return Err(ParseError(line_no, "scenario name must not be empty"))
    }
    builder.name = body
    return Ok(())
  }
  if directive_is(head, "strength") {
    builder.strength = match parse_positive_int(body, line_no) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    return Ok(())
  }
  if directive_is(head, "max-candidates") ||
    directive_is(head, "max_candidates") ||
    directive_is(head, "limit") {
    builder.max_candidates = match parse_positive_int(body, line_no) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    return Ok(())
  }
  if directive_is(head, "minimize") {
    builder.minimize = match parse_bool(body, line_no) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    return Ok(())
  }
  match strip_directive(head, "param") {
    Some(parameter_name) =>
      return parse_parameter_directive(builder, line_no, parameter_name, body)
    None => ()
  }
  match strip_directive(head, "parameter") {
    Some(parameter_name) =>
      return parse_parameter_directive(builder, line_no, parameter_name, body)
    None => ()
  }
  match strip_directive(head, "constraint") {
    Some(label) => {
      let normalized_label = if label.length() == 0 {
        "constraint line \{line_no}"
      } else {
        label
      }
      if body.length() == 0 {
        return Err(ParseError(line_no, "constraint expression is empty"))
      }
      builder.constraints.push({ label: normalized_label, source: body })
      return Ok(())
    }
    None => ()
  }
  if directive_is(head, "include") ||
    directive_is(head, "case") ||
    directive_is(head, "must") {
    let pattern = match parse_case_pattern(body, line_no) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    builder.includes.push({ pattern, line: line_no })
    return Ok(())
  }
  if directive_is(head, "exclude") ||
    directive_is(head, "forbid") ||
    directive_is(head, "never") {
    let pattern = match parse_case_pattern(body, line_no) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    builder.excludes.push({ pattern, line: line_no })
    return Ok(())
  }
  match strip_directive(head, "risk") {
    Some(selector) =>
      return parse_risk_directive(builder, line_no, selector, body)
    None => ()
  }
  Err(ParseError(line_no, "unknown scenario directive"))
}

///|
fn parse_parameter_directive(
  builder : RawSpecBuilder,
  line_no : Int,
  parameter_name : String,
  body : String,
) -> Result[Unit, CaseWeaveError] {
  let name = trim_text(parameter_name)
  if name.length() == 0 {
    return Err(ParseError(line_no, "parameter name must not be empty"))
  }
  let values = match split_csv_values(body, line_no) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  builder.parameters.push(Parameter::new(name, values))
  Ok(())
}

///|
fn parse_risk_directive(
  builder : RawSpecBuilder,
  line_no : Int,
  selector : String,
  body : String,
) -> Result[Unit, CaseWeaveError] {
  let pattern = match parse_case_pattern(selector, line_no) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let parts = split_once_char(body, ':')
  let weight_text = match parts {
    None => body
    Some(value) => trim_text(value.left)
  }
  let note = match parts {
    None => ""
    Some(value) => trim_text(value.right)
  }
  let weight = match parse_positive_int(weight_text, line_no) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  builder.risks.push({ pattern, weight, note, line: line_no })
  Ok(())
}

///|
pub fn ScenarioSpec::generate_suite(
  self : ScenarioSpec,
) -> Result[Suite, CaseWeaveError] {
  generate(self.model, constraints=self.constraints, options=self.options)
}

///|
pub fn ScenarioSpec::run(
  self : ScenarioSpec,
) -> Result[ScenarioRun, CaseWeaveError] {
  let suite = match self.generate_suite() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let cases = merge_cases(self.included_cases, suite.cases())
  let coverage = match
    audit(
      self.model,
      cases,
      strength=self.options.strength,
      constraints=self.constraints,
      max_candidates=self.options.max_candidates,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let ranked_cases = match self.rank_cases(cases) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    spec_name: self.name,
    model: self.model,
    suite,
    cases,
    included_case_count: self.included_cases.length(),
    coverage,
    ranked_cases,
  })
}

///|
fn merge_cases(
  included : Array[TestCase],
  generated : Array[TestCase],
) -> Array[TestCase] {
  let cases : Array[TestCase] = []
  for test_case in included {
    if !contains_test_case(cases, test_case) {
      cases.push(test_case)
    }
  }
  for test_case in generated {
    if !contains_test_case(cases, test_case) {
      cases.push(test_case)
    }
  }
  cases
}

///|
fn contains_test_case(cases : Array[TestCase], target : TestCase) -> Bool {
  for test_case in cases {
    if test_case == target {
      return true
    }
  }
  false
}

///|
pub fn ScenarioSpec::score_case(
  self : ScenarioSpec,
  test_case : TestCase,
) -> Result[CaseRisk, CaseWeaveError] {
  match self.model.validate_case(test_case) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let reasons : Array[String] = []
  let mut score = 0
  for risk in self.value_risks {
    if case_has_choice(self.model, test_case, risk.choice) {
      score = score + risk.weight
      reasons.push(risk_reason(risk.choice, risk.weight, risk.note))
    }
  }
  for risk in self.interaction_risks {
    match risk.pattern.matches(self.model, test_case) {
      Err(error) => return Err(error)
      Ok(true) => {
        score = score + risk.weight
        reasons.push(pattern_risk_reason(risk.pattern, risk.weight, risk.note))
      }
      Ok(false) => ()
    }
  }
  Ok({ score, reasons })
}

///|
pub fn ScenarioSpec::rank_cases(
  self : ScenarioSpec,
  cases : Array[TestCase],
) -> Result[Array[RankedCase], CaseWeaveError] {
  let ranked : Array[RankedCase] = []
  for index = 0; index < cases.length(); index = index + 1 {
    let risk = match self.score_case(cases[index]) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    ranked.push({
      rank: 0,
      index,
      test_case: cases[index],
      score: risk.score,
      reasons: risk.reasons,
    })
  }
  ranked.sort_by(compare_ranked_case)
  for index = 0; index < ranked.length(); index = index + 1 {
    let item = ranked[index]
    ranked[index] = {
      rank: index + 1,
      index: item.index,
      test_case: item.test_case,
      score: item.score,
      reasons: item.reasons,
    }
  }
  Ok(ranked)
}

///|
fn compare_ranked_case(left : RankedCase, right : RankedCase) -> Int {
  if left.score > right.score {
    -1
  } else if left.score < right.score {
    1
  } else if left.index < right.index {
    -1
  } else if left.index > right.index {
    1
  } else {
    0
  }
}

///|
fn case_has_choice(
  model : Model,
  test_case : TestCase,
  choice : NamedChoice,
) -> Bool {
  match test_case.value_for(model, choice.parameter) {
    Some(value) => value == choice.value
    None => false
  }
}

///|
fn risk_reason(choice : NamedChoice, weight : Int, note : String) -> String {
  let suffix = if note.length() == 0 { "" } else { " — \{note}" }
  "\{choice.parameter}=\{choice.value} +\{weight}\{suffix}"
}

///|
fn pattern_risk_reason(
  pattern : CasePattern,
  weight : Int,
  note : String,
) -> String {
  let suffix = if note.length() == 0 { "" } else { " — \{note}" }
  "\{pattern.to_text()} +\{weight}\{suffix}"
}

///|
pub fn CasePattern::validate(
  self : CasePattern,
  model : Model,
) -> Result[Unit, CaseWeaveError] {
  if self.choices.length() == 0 {
    return Err(ParseError(0, "case pattern must not be empty"))
  }
  for index = 0; index < self.choices.length(); index = index + 1 {
    let choice = self.choices[index]
    for previous = 0; previous < index; previous = previous + 1 {
      if self.choices[previous].parameter == choice.parameter {
        return Err(DuplicateParameter(choice.parameter))
      }
    }
    let parameter_index = match model.parameter_index(choice.parameter) {
      None => return Err(UnknownParameter(choice.parameter))
      Some(value) => value
    }
    if model.value_index(parameter_index, choice.value) is None {
      return Err(UnknownValue(choice.parameter, choice.value))
    }
  }
  Ok(())
}

///|
pub fn CasePattern::matches(
  self : CasePattern,
  model : Model,
  test_case : TestCase,
) -> Result[Bool, CaseWeaveError] {
  match self.validate(model) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match model.validate_case(test_case) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for choice in self.choices {
    if !case_has_choice(model, test_case, choice) {
      return Ok(false)
    }
  }
  Ok(true)
}

///|
pub fn CasePattern::to_exclusion_constraint(
  self : CasePattern,
  label : String,
) -> Result[Constraint, CaseWeaveError] {
  if self.choices.length() == 0 {
    return Err(ParseError(0, "case pattern must not be empty"))
  }
  Ok(Constraint::new(label, Not(pattern_to_expression(self))))
}

///|
fn pattern_to_expression(pattern : CasePattern) -> ConstraintExpr {
  let mut expression : ConstraintExpr = Equal(
    pattern.choices[0].parameter,
    pattern.choices[0].value,
  )
  for index = 1; index < pattern.choices.length(); index = index + 1 {
    expression = And(
      expression,
      Equal(pattern.choices[index].parameter, pattern.choices[index].value),
    )
  }
  expression
}

///|
pub fn CasePattern::to_case(
  self : CasePattern,
  model : Model,
  line_no? : Int = 0,
) -> Result[TestCase, CaseWeaveError] {
  match self.validate(model) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let values = Array::make(model.parameter_count(), "")
  let seen = Array::make(model.parameter_count(), false)
  for choice in self.choices {
    let parameter_index = match model.parameter_index(choice.parameter) {
      None => return Err(UnknownParameter(choice.parameter))
      Some(value) => value
    }
    values[parameter_index] = choice.value
    seen[parameter_index] = true
  }
  for index = 0; index < seen.length(); index = index + 1 {
    if !seen[index] {
      let parameter = match model.parameter(index) {
        None => "unknown"
        Some(value) => value.name
      }
      return Err(
        ParseError(line_no, "included case is missing parameter '\{parameter}'"),
      )
    }
  }
  Ok(TestCase::new(values))
}

///|
pub fn CasePattern::to_text(self : CasePattern) -> String {
  let builder = StringBuilder::new()
  for index = 0; index < self.choices.length(); index = index + 1 {
    if index > 0 {
      builder.write_string(", ")
    }
    let choice = self.choices[index]
    builder.write_string(choice.parameter)
    builder.write_char('=')
    builder.write_string(choice.value)
  }
  builder.to_string()
}

///|
pub fn TestCase::assignment_text(self : TestCase, model : Model) -> String {
  let builder = StringBuilder::new()
  for index = 0; index < model.parameter_count(); index = index + 1 {
    if index > 0 {
      builder.write_string(", ")
    }
    let parameter = match model.parameter(index) {
      None => "unknown"
      Some(value) => value.name
    }
    builder.write_string(parameter)
    builder.write_char('=')
    match self.get(index) {
      None => builder.write_string("?")
      Some(value) => builder.write_string(value)
    }
  }
  builder.to_string()
}

///|
pub fn ScenarioSpec::summary(self : ScenarioSpec) -> String {
  "scenario=\{self.name}, parameters=\{self.model.parameter_count()}, strength=\{self.options.strength}, constraints=\{self.constraints.length()}, includes=\{self.included_cases.length()}, excludes=\{self.excluded_patterns.length()}, risks=\{self.value_risks.length() + self.interaction_risks.length()}"
}

///|
pub fn ScenarioSpec::lint(self : ScenarioSpec) -> Array[SpecWarning] {
  let warnings : Array[SpecWarning] = []
  if self.constraints.length() == 0 {
    warnings.push({
      kind: NoConstraints,
      message: "No constraints are declared; verify that impossible real-world combinations are not being generated.",
    })
  }
  if self.value_risks.length() == 0 && self.interaction_risks.length() == 0 {
    warnings.push({
      kind: NoRiskHints,
      message: "No risk hints are declared; ranked output will preserve generation order only.",
    })
  }
  if self.included_cases.length() == 0 {
    warnings.push({
      kind: NoIncludedCases,
      message: "No included anchor cases are declared; add must-run smoke paths when a scenario has business-critical examples.",
    })
  }
  if self.options.strength == 1 {
    warnings.push({
      kind: StrengthOne,
      message: "Strength 1 covers individual values only; pairwise strength is a better default for configuration interactions.",
    })
  }
  if self.model.combination_count() > self.options.max_candidates.to_int64() {
    warnings.push({
      kind: CandidateLimitBelowCartesian(
        self.model.combination_count(),
        self.options.max_candidates,
      ),
      message: "The candidate limit is below the Cartesian space; generation may stop before all feasible rows are examined.",
    })
  }
  for parameter in self.model.parameters {
    if parameter.values.length() == 1 {
      warnings.push({
        kind: SingleValueParameter(parameter.name),
        message: "Parameter '\{parameter.name}' has one value and does not increase coverage strength.",
      })
    }
  }
  warnings
}

///|
pub fn ScenarioSpec::lint_text(self : ScenarioSpec) -> String {
  let warnings = self.lint()
  if warnings.length() == 0 {
    return "no scenario warnings\n"
  }
  let builder = StringBuilder::new()
  for warning in warnings {
    builder.write_string("- ")
    builder.write_string(warning.message)
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
pub fn ScenarioRun::summary(self : ScenarioRun) -> String {
  let top_score = if self.ranked_cases.length() == 0 {
    0
  } else {
    self.ranked_cases[0].score
  }
  "scenario=\{self.spec_name}, cases=\{self.cases.length()}, included=\{self.included_case_count}, coverage=\{self.coverage.coverage_percent}%, top-risk=\{top_score}"
}

///|
pub fn ScenarioRun::cases_markdown(self : ScenarioRun) -> String {
  cases_to_markdown(self.model, self.cases)
}

///|
pub fn ScenarioRun::risk_markdown(
  self : ScenarioRun,
  top? : Int = 10,
) -> String {
  let builder = StringBuilder::new()
  builder.write_string("| rank | case | score | reasons |\n")
  builder.write_string("| --- | --- | --- | --- |\n")
  let limit = if top < 0 {
    self.ranked_cases.length()
  } else if top > self.ranked_cases.length() {
    self.ranked_cases.length()
  } else {
    top
  }
  for index = 0; index < limit; index = index + 1 {
    let item = self.ranked_cases[index]
    builder.write_string("| ")
    builder.write_string(item.rank.to_string())
    builder.write_string(" | ")
    builder.write_string(
      markdown_inline(item.test_case.assignment_text(self.model)),
    )
    builder.write_string(" | ")
    builder.write_string(item.score.to_string())
    builder.write_string(" | ")
    builder.write_string(markdown_inline(join_reasons(item.reasons)))
    builder.write_string(" |\n")
  }
  builder.to_string()
}

///|
fn join_reasons(reasons : Array[String]) -> String {
  if reasons.length() == 0 {
    return "none"
  }
  let builder = StringBuilder::new()
  for index = 0; index < reasons.length(); index = index + 1 {
    if index > 0 {
      builder.write_string("; ")
    }
    builder.write_string(reasons[index])
  }
  builder.to_string()
}

///|
fn markdown_inline(value : String) -> String {
  let builder = StringBuilder::new()
  for char in value.to_array() {
    match char {
      '|' => builder.write_string("\\|")
      '\n' => builder.write_string("<br>")
      '\r' => ()
      _ => builder.write_char(char)
    }
  }
  builder.to_string()
}

///|
fn parse_case_pattern(
  source : String,
  line_no : Int,
) -> Result[CasePattern, CaseWeaveError] {
  let parts = match split_csv_values(source, line_no) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let choices : Array[NamedChoice] = []
  for part in parts {
    let assignment = match split_once_char(part, '=') {
      None => return Err(ParseError(line_no, "expected parameter=value"))
      Some(value) => value
    }
    let parameter = trim_text(assignment.left)
    let value = trim_text(assignment.right)
    if parameter.length() == 0 {
      return Err(ParseError(line_no, "assignment parameter is empty"))
    }
    if value.length() == 0 {
      return Err(ParseError(line_no, "assignment value is empty"))
    }
    for choice in choices {
      if choice.parameter == parameter {
        return Err(DuplicateParameter(parameter))
      }
    }
    choices.push({ parameter, value })
  }
  if choices.length() == 0 {
    return Err(ParseError(line_no, "case pattern must not be empty"))
  }
  Ok({ choices, })
}

///|
fn split_csv_values(
  source : String,
  line_no : Int,
) -> Result[Array[String], CaseWeaveError] {
  let values : Array[String] = []
  let chars = source.to_array()
  let builder = StringBuilder::new()
  let mut quoted = false
  let mut index = 0
  while index < chars.length() {
    let char = chars[index]
    if quoted {
      if char == '"' {
        quoted = false
        index = index + 1
        continue
      }
      if char == '\\' {
        if index + 1 >= chars.length() {
          return Err(ParseError(line_no, "unterminated escape sequence"))
        }
        let escaped = chars[index + 1]
        match escaped {
          '"' => builder.write_char('"')
          '\\' => builder.write_char('\\')
          'n' => builder.write_char('\n')
          'r' => builder.write_char('\r')
          't' => builder.write_char('\t')
          ',' => builder.write_char(',')
          _ => return Err(ParseError(line_no, "unsupported escape sequence"))
        }
        index = index + 2
        continue
      }
      builder.write_char(char)
      index = index + 1
      continue
    }
    if char == '"' {
      quoted = true
      index = index + 1
      continue
    }
    if char == ',' {
      let value = trim_text(builder.to_string())
      if value.length() == 0 {
        return Err(ParseError(line_no, "empty comma-separated value"))
      }
      values.push(value)
      builder.reset()
      index = index + 1
      continue
    }
    builder.write_char(char)
    index = index + 1
  }
  if quoted {
    return Err(ParseError(line_no, "unterminated quoted value"))
  }
  let final_value = trim_text(builder.to_string())
  if final_value.length() == 0 {
    return Err(ParseError(line_no, "empty comma-separated value"))
  }
  values.push(final_value)
  Ok(values)
}

///|
fn parse_positive_int(
  text : String,
  line_no : Int,
) -> Result[Int, CaseWeaveError] {
  let value = trim_text(text)
  if value.length() == 0 {
    return Err(ParseError(line_no, "expected positive integer"))
  }
  let chars = value.to_array()
  let mut result = 0
  for char in chars {
    if char < '0' || char > '9' {
      return Err(ParseError(line_no, "expected positive integer"))
    }
    result = result * 10 + char_to_digit(char)
  }
  if result <= 0 {
    return Err(ParseError(line_no, "expected positive integer"))
  }
  Ok(result)
}

///|
fn char_to_digit(char : Char) -> Int {
  char.to_int() - '0'.to_int()
}

///|
fn parse_bool(text : String, line_no : Int) -> Result[Bool, CaseWeaveError] {
  let value = trim_text(text).to_lower()
  match value {
    "true" | "yes" | "on" => Ok(true)
    "false" | "no" | "off" => Ok(false)
    _ => Err(ParseError(line_no, "expected boolean"))
  }
}

///|
fn split_lines(source : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = source.to_array()
  let builder = StringBuilder::new()
  for char in chars {
    if char == '\n' {
      lines.push(builder.to_string())
      builder.reset()
    } else {
      builder.write_char(char)
    }
  }
  lines.push(builder.to_string())
  lines
}

///|
fn split_once_char(source : String, separator : Char) -> TextParts? {
  let chars = source.to_array()
  for index = 0; index < chars.length(); index = index + 1 {
    if chars[index] == separator {
      return Some({
        left: slice_chars(chars, 0, index),
        right: slice_chars(chars, index + 1, chars.length()),
      })
    }
  }
  None
}

///|
fn slice_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let builder = StringBuilder::new()
  for index = start; index < end; index = index + 1 {
    builder.write_char(chars[index])
  }
  builder.to_string()
}

///|
fn trim_text(source : String) -> String {
  let chars = source.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && is_spec_space(chars[start]) {
    start = start + 1
  }
  while end > start && is_spec_space(chars[end - 1]) {
    end = end - 1
  }
  slice_chars(chars, start, end)
}

///|
fn is_spec_space(char : Char) -> Bool {
  char == ' ' || char == '\t' || char == '\r' || char == '\n'
}

///|
fn directive_is(head : String, expected : String) -> Bool {
  trim_text(head).to_lower() == expected
}

///|
fn strip_directive(head : String, expected : String) -> String? {
  let normalized = trim_text(head)
  let lower = normalized.to_lower()
  if lower == expected {
    return Some("")
  }
  let prefix = expected + " "
  if starts_with_text(lower, prefix) {
    Some(
      trim_text(
        slice_chars(
          normalized.to_array(),
          prefix.length(),
          normalized.to_array().length(),
        ),
      ),
    )
  } else {
    None
  }
}

///|
fn starts_with_text(source : String, prefix : String) -> Bool {
  let source_chars = source.to_array()
  let prefix_chars = prefix.to_array()
  if prefix_chars.length() > source_chars.length() {
    return false
  }
  for index = 0; index < prefix_chars.length(); index = index + 1 {
    if source_chars[index] != prefix_chars[index] {
      return false
    }
  }
  true
}
