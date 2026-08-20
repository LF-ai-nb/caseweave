///|
/// Options for repairing an incomplete suite. The planner uses the same
/// interaction model as `audit`, then greedily proposes additional feasible
/// cases that cover the largest number of currently missing interactions.
pub(all) struct RepairOptions {
  strength : Int
  max_candidates : Int
  max_suggestions : Int
}

///|
pub fn RepairOptions::default() -> RepairOptions {
  { strength: 2, max_candidates: 100000, max_suggestions: 1000 }
}

///|
pub fn RepairOptions::pairwise(
  max_candidates? : Int = 100000,
  max_suggestions? : Int = 1000,
) -> RepairOptions {
  { strength: 2, max_candidates, max_suggestions }
}

///|
pub fn RepairOptions::from_generation(
  options : GenerationOptions,
  max_suggestions? : Int = 1000,
) -> RepairOptions {
  {
    strength: options.strength,
    max_candidates: options.max_candidates,
    max_suggestions,
  }
}

///|
pub(all) struct RepairStep {
  index : Int
  test_case : TestCase
  newly_covered : Array[MissingInteraction]
  remaining_missing : Int
  risk_score : Int
  reasons : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct RepairPlan {
  model : Model
  original_cases : Array[TestCase]
  additions : Array[TestCase]
  merged_cases : Array[TestCase]
  original_report : CoverageReport
  final_report : CoverageReport
  steps : Array[RepairStep]
  complete : Bool
  initial_missing : Int
  final_missing : Int
}

///|
pub(all) struct RepairGate {
  require_complete : Bool
  max_additions : Int
  max_final_missing : Int
  min_largest_gain : Int
}

///|
pub(all) enum RepairGateFailureKind {
  RepairIncomplete(Int)
  TooManyRepairAdditions(Int, Int)
  TooManyRemainingInteractions(Int, Int)
  LargestGainTooLow(Int, Int)
} derive(Debug, Eq)

///|
pub(all) struct RepairGateFailure {
  kind : RepairGateFailureKind
  message : String
} derive(Debug, Eq)

///|
pub(all) struct RepairGateReport {
  passed : Bool
  failures : Array[RepairGateFailure]
  additions : Int
  initial_missing : Int
  final_missing : Int
  largest_gain : Int
  complete : Bool
}

///|
priv struct RepairRisk {
  score : Int
  reasons : Array[String]
}

///|
priv struct RepairChoice {
  row_index : Int
  gain : Int
  risk : RepairRisk
}

///|
pub fn plan_repair(
  model : Model,
  cases : Array[TestCase],
  constraints? : Array[Constraint] = [],
  options? : RepairOptions = RepairOptions::default(),
) -> Result[RepairPlan, CaseWeaveError] {
  plan_repair_internal(model, cases, constraints, options, None)
}

///|
pub fn ScenarioSpec::plan_repair(
  self : ScenarioSpec,
  cases : Array[TestCase],
  options? : RepairOptions = RepairOptions::from_generation(self.options),
) -> Result[RepairPlan, CaseWeaveError] {
  plan_repair_internal(self.model, cases, self.constraints, options, Some(self))
}

///|
fn plan_repair_internal(
  model : Model,
  cases : Array[TestCase],
  constraints : Array[Constraint],
  options : RepairOptions,
  spec : ScenarioSpec?,
) -> Result[RepairPlan, CaseWeaveError] {
  match validate_repair_options(model, options) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_constraints(constraints, model) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let enumeration = match
    enumerate_valid_rows(model, constraints, options.max_candidates) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if enumeration.rows.length() == 0 {
    return Err(NoValidCases)
  }
  let interactions = collect_interactions(enumeration.rows, options.strength)
  let covered = Array::make(interactions.length(), false)
  let existing_rows : Array[Array[Int]] = []
  for case_index = 0; case_index < cases.length(); case_index = case_index + 1 {
    let row = match
      encode_repair_case(model, cases[case_index], constraints, case_index) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    existing_rows.push(row)
    mark_row_coverage(row, interactions, covered)
  }
  let original_report = match
    audit(
      model,
      cases,
      strength=options.strength,
      constraints~,
      max_candidates=options.max_candidates,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let initial_missing = count_uncovered(covered)
  let addition_rows : Array[Array[Int]] = []
  let additions : Array[TestCase] = []
  let steps : Array[RepairStep] = []
  let mut remaining = initial_missing
  while remaining > 0 && steps.length() < options.max_suggestions {
    let choice = match
      choose_repair_choice(
        model,
        enumeration.rows,
        interactions,
        covered,
        existing_rows,
        addition_rows,
        spec,
      ) {
      None => return Err(UncoverableInteraction)
      Some(value) => value
    }
    let row = enumeration.rows[choice.row_index]
    let newly = newly_covered_interactions(model, row, interactions, covered)
    if newly.length() == 0 {
      return Err(UncoverableInteraction)
    }
    mark_row_coverage(row, interactions, covered)
    remaining = count_uncovered(covered)
    let test_case = model.decode(row)
    addition_rows.push(row.copy())
    additions.push(test_case)
    steps.push({
      index: steps.length() + 1,
      test_case,
      newly_covered: newly,
      remaining_missing: remaining,
      risk_score: choice.risk.score,
      reasons: repair_reasons(choice.gain, choice.risk.reasons),
    })
  }
  let merged_cases = merge_repair_cases(cases, additions)
  let final_report = match
    audit(
      model,
      merged_cases,
      strength=options.strength,
      constraints~,
      max_candidates=options.max_candidates,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    model,
    original_cases: cases.copy(),
    additions,
    merged_cases,
    original_report,
    final_report,
    steps,
    complete: final_report.is_complete(),
    initial_missing,
    final_missing: final_report.missing.length(),
  })
}

///|
fn validate_repair_options(
  model : Model,
  options : RepairOptions,
) -> Result[Unit, CaseWeaveError] {
  if options.strength < 1 || options.strength > model.parameter_count() {
    return Err(InvalidStrength(options.strength, model.parameter_count()))
  }
  if options.max_candidates < 1 {
    return Err(InvalidCandidateLimit(options.max_candidates))
  }
  if options.max_suggestions < 0 {
    return Err(InvalidSuggestionLimit(options.max_suggestions))
  }
  Ok(())
}

///|
fn encode_repair_case(
  model : Model,
  test_case : TestCase,
  constraints : Array[Constraint],
  case_index : Int,
) -> Result[Array[Int], CaseWeaveError] {
  let row = match model.encode(test_case) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  for constraint in constraints {
    if evaluate_expression(constraint.expression, model, row) != Yes {
      return Err(ConstraintViolation(case_index, constraint.label))
    }
  }
  Ok(row)
}

///|
fn choose_repair_choice(
  model : Model,
  valid_rows : Array[Array[Int]],
  interactions : Array[Interaction],
  covered : Array[Bool],
  existing_rows : Array[Array[Int]],
  addition_rows : Array[Array[Int]],
  spec : ScenarioSpec?,
) -> RepairChoice? {
  let mut best : RepairChoice? = None
  for row_index = 0; row_index < valid_rows.length(); row_index = row_index + 1 {
    let row = valid_rows[row_index]
    if row_exists(existing_rows, row) || row_exists(addition_rows, row) {
      continue
    }
    let gain = repair_gain(row, interactions, covered)
    if gain <= 0 {
      continue
    }
    let risk = score_repair_row(model, row, spec)
    let candidate : RepairChoice = { row_index, gain, risk }
    match best {
      None => best = Some(candidate)
      Some(current) =>
        if repair_choice_is_better(candidate, current) {
          best = Some(candidate)
        }
    }
  }
  best
}

///|
fn repair_choice_is_better(
  candidate : RepairChoice,
  current : RepairChoice,
) -> Bool {
  if candidate.gain > current.gain {
    return true
  }
  if candidate.gain < current.gain {
    return false
  }
  if candidate.risk.score > current.risk.score {
    return true
  }
  if candidate.risk.score < current.risk.score {
    return false
  }
  candidate.row_index < current.row_index
}

///|
fn row_exists(rows : Array[Array[Int]], target : Array[Int]) -> Bool {
  for row in rows {
    if row == target {
      return true
    }
  }
  false
}

///|
fn repair_gain(
  row : Array[Int],
  interactions : Array[Interaction],
  covered : Array[Bool],
) -> Int {
  let mut gain = 0
  for index = 0; index < interactions.length(); index = index + 1 {
    if !covered[index] && row_covers(row, interactions[index]) {
      gain = gain + 1
    }
  }
  gain
}

///|
fn mark_row_coverage(
  row : Array[Int],
  interactions : Array[Interaction],
  covered : Array[Bool],
) -> Unit {
  for index = 0; index < interactions.length(); index = index + 1 {
    if row_covers(row, interactions[index]) {
      covered[index] = true
    }
  }
}

///|
fn newly_covered_interactions(
  model : Model,
  row : Array[Int],
  interactions : Array[Interaction],
  covered : Array[Bool],
) -> Array[MissingInteraction] {
  let newly : Array[MissingInteraction] = []
  for index = 0; index < interactions.length(); index = index + 1 {
    if !covered[index] && row_covers(row, interactions[index]) {
      newly.push(named_interaction(model, interactions[index]))
    }
  }
  newly
}

///|
fn count_uncovered(covered : Array[Bool]) -> Int {
  let mut count = 0
  for value in covered {
    if !value {
      count = count + 1
    }
  }
  count
}

///|
fn score_repair_row(
  model : Model,
  row : Array[Int],
  spec : ScenarioSpec?,
) -> RepairRisk {
  match spec {
    None => { score: 0, reasons: [] }
    Some(value) => {
      let test_case = model.decode(row)
      match value.score_case(test_case) {
        Err(_) => { score: 0, reasons: [] }
        Ok(risk) => { score: risk.score, reasons: risk.reasons }
      }
    }
  }
}

///|
fn repair_reasons(gain : Int, risk_reasons : Array[String]) -> Array[String] {
  let reasons : Array[String] = []
  reasons.push("covers \{gain} missing interaction(s)")
  for reason in risk_reasons {
    reasons.push(reason)
  }
  reasons
}

///|
fn merge_repair_cases(
  existing : Array[TestCase],
  additions : Array[TestCase],
) -> Array[TestCase] {
  let merged : Array[TestCase] = []
  for test_case in existing {
    merged.push(test_case)
  }
  for test_case in additions {
    if !contains_test_case(merged, test_case) {
      merged.push(test_case)
    }
  }
  merged
}

///|
pub fn RepairPlan::is_complete(self : RepairPlan) -> Bool {
  self.complete
}

///|
pub fn RepairPlan::addition_count(self : RepairPlan) -> Int {
  self.additions.length()
}

///|
pub fn RepairPlan::additions(self : RepairPlan) -> Array[TestCase] {
  self.additions.copy()
}

///|
pub fn RepairPlan::merged_cases(self : RepairPlan) -> Array[TestCase] {
  self.merged_cases.copy()
}

///|
pub fn RepairPlan::steps(self : RepairPlan) -> Array[RepairStep] {
  self.steps.copy()
}

///|
pub fn RepairPlan::summary(self : RepairPlan) -> String {
  let status = if self.complete { "complete" } else { "partial" }
  "repair=\{status}, original=\{self.original_cases.length()}, additions=\{self.additions.length()}, initial-missing=\{self.initial_missing}, final-missing=\{self.final_missing}, coverage=\{self.final_report.coverage_percent}%"
}

///|
pub fn RepairPlan::additions_markdown(self : RepairPlan) -> String {
  cases_to_markdown(self.model, self.additions)
}

///|
pub fn RepairPlan::merged_markdown(self : RepairPlan) -> String {
  cases_to_markdown(self.model, self.merged_cases)
}

///|
pub fn RepairPlan::steps_markdown(self : RepairPlan, top? : Int = -1) -> String {
  let builder = StringBuilder::new()
  builder.write_string(
    "| step | case | newly covered | remaining | risk | reasons |\n",
  )
  builder.write_string("| --- | --- | --- | --- | --- | --- |\n")
  let limit = if top < 0 || top > self.steps.length() {
    self.steps.length()
  } else {
    top
  }
  for index = 0; index < limit; index = index + 1 {
    let step = self.steps[index]
    builder.write_string("| ")
    builder.write_string(step.index.to_string())
    builder.write_string(" | ")
    builder.write_string(
      repair_markdown_inline(step.test_case.assignment_text(self.model)),
    )
    builder.write_string(" | ")
    builder.write_string(step.newly_covered.length().to_string())
    builder.write_string(" | ")
    builder.write_string(step.remaining_missing.to_string())
    builder.write_string(" | ")
    builder.write_string(step.risk_score.to_string())
    builder.write_string(" | ")
    builder.write_string(
      repair_markdown_inline(join_repair_reasons(step.reasons)),
    )
    builder.write_string(" |\n")
  }
  builder.to_string()
}

///|
pub fn RepairPlan::missing_after_text(self : RepairPlan) -> String {
  self.final_report.missing_text()
}

///|
pub fn RepairPlan::to_markdown(self : RepairPlan) -> String {
  let builder = StringBuilder::new()
  builder.write_string("## CaseWeave Repair Plan\n\n")
  builder.write_string("- status: ")
  builder.write_string(if self.complete { "complete" } else { "partial" })
  builder.write_char('\n')
  builder.write_string("- original cases: ")
  builder.write_string(self.original_cases.length().to_string())
  builder.write_char('\n')
  builder.write_string("- suggested additions: ")
  builder.write_string(self.additions.length().to_string())
  builder.write_char('\n')
  builder.write_string("- initial missing interactions: ")
  builder.write_string(self.initial_missing.to_string())
  builder.write_char('\n')
  builder.write_string("- final missing interactions: ")
  builder.write_string(self.final_missing.to_string())
  builder.write_string("\n\n")
  builder.write_string("### Suggested steps\n\n")
  builder.write_string(self.steps_markdown())
  if self.final_missing > 0 {
    builder.write_string("\n### Remaining gaps\n\n")
    builder.write_string(self.missing_after_text())
  }
  builder.to_string()
}

///|
fn join_repair_reasons(reasons : Array[String]) -> String {
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
fn repair_markdown_inline(value : String) -> String {
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
pub fn RepairPlan::highest_risk_step(self : RepairPlan) -> RepairStep? {
  if self.steps.length() == 0 {
    return None
  }
  let mut best = self.steps[0]
  for index = 1; index < self.steps.length(); index = index + 1 {
    let step = self.steps[index]
    if step.risk_score > best.risk_score {
      best = step
    }
  }
  Some(best)
}

///|
pub fn RepairPlan::largest_gain_step(self : RepairPlan) -> RepairStep? {
  if self.steps.length() == 0 {
    return None
  }
  let mut best = self.steps[0]
  for index = 1; index < self.steps.length(); index = index + 1 {
    let step = self.steps[index]
    if step.newly_covered.length() > best.newly_covered.length() {
      best = step
    }
  }
  Some(best)
}

///|
pub fn RepairPlan::risk_summary(self : RepairPlan) -> String {
  let risk_step = self.highest_risk_step()
  let gain_step = self.largest_gain_step()
  let builder = StringBuilder::new()
  match risk_step {
    None => builder.write_string("highest-risk: none\n")
    Some(step) => {
      builder.write_string("highest-risk: step ")
      builder.write_string(step.index.to_string())
      builder.write_string(", score=")
      builder.write_string(step.risk_score.to_string())
      builder.write_string(", case=")
      builder.write_string(step.test_case.assignment_text(self.model))
      builder.write_char('\n')
    }
  }
  match gain_step {
    None => builder.write_string("largest-gain: none\n")
    Some(step) => {
      builder.write_string("largest-gain: step ")
      builder.write_string(step.index.to_string())
      builder.write_string(", newly-covered=")
      builder.write_string(step.newly_covered.length().to_string())
      builder.write_string(", case=")
      builder.write_string(step.test_case.assignment_text(self.model))
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
pub fn RepairGate::default() -> RepairGate {
  {
    require_complete: true,
    max_additions: 100000,
    max_final_missing: 0,
    min_largest_gain: 1,
  }
}

///|
pub fn RepairGate::budget(max_additions : Int) -> RepairGate {
  {
    require_complete: true,
    max_additions,
    max_final_missing: 0,
    min_largest_gain: 1,
  }
}

///|
pub fn RepairGate::best_effort(
  max_additions : Int,
  max_final_missing : Int,
) -> RepairGate {
  {
    require_complete: false,
    max_additions,
    max_final_missing,
    min_largest_gain: 0,
  }
}

///|
pub fn RepairGate::normalize(self : RepairGate) -> RepairGate {
  {
    require_complete: self.require_complete,
    max_additions: if self.max_additions < 0 {
      0
    } else {
      self.max_additions
    },
    max_final_missing: if self.max_final_missing < 0 {
      0
    } else {
      self.max_final_missing
    },
    min_largest_gain: if self.min_largest_gain < 0 {
      0
    } else {
      self.min_largest_gain
    },
  }
}

///|
pub fn RepairPlan::evaluate_repair_gate(
  self : RepairPlan,
  gate? : RepairGate = RepairGate::default(),
) -> RepairGateReport {
  let normalized = gate.normalize()
  let failures : Array[RepairGateFailure] = []
  let largest_gain = self.largest_repair_gain()
  if normalized.require_complete && !self.complete {
    failures.push({
      kind: RepairIncomplete(self.final_missing),
      message: "Repair plan is incomplete; \{self.final_missing} interaction(s) remain missing.",
    })
  }
  if self.additions.length() > normalized.max_additions {
    failures.push({
      kind: TooManyRepairAdditions(
        self.additions.length(),
        normalized.max_additions,
      ),
      message: "Repair suggestions exceed the configured budget: \{self.additions.length()} > \{normalized.max_additions}.",
    })
  }
  if self.final_missing > normalized.max_final_missing {
    failures.push({
      kind: TooManyRemainingInteractions(
        self.final_missing,
        normalized.max_final_missing,
      ),
      message: "Remaining missing interactions exceed the gate: \{self.final_missing} > \{normalized.max_final_missing}.",
    })
  }
  if largest_gain < normalized.min_largest_gain {
    failures.push({
      kind: LargestGainTooLow(largest_gain, normalized.min_largest_gain),
      message: "The largest repair step covers too few interactions: \{largest_gain} < \{normalized.min_largest_gain}.",
    })
  }
  {
    passed: failures.length() == 0,
    failures,
    additions: self.additions.length(),
    initial_missing: self.initial_missing,
    final_missing: self.final_missing,
    largest_gain,
    complete: self.complete,
  }
}

///|
pub fn RepairPlan::largest_repair_gain(self : RepairPlan) -> Int {
  let mut gain = 0
  for step in self.steps {
    if step.newly_covered.length() > gain {
      gain = step.newly_covered.length()
    }
  }
  gain
}

///|
pub fn RepairGateReport::is_passed(self : RepairGateReport) -> Bool {
  self.passed
}

///|
pub fn RepairGateReport::summary(self : RepairGateReport) -> String {
  let status = if self.passed { "pass" } else { "fail" }
  "repair-gate=\{status}, failures=\{self.failures.length()}, additions=\{self.additions}, initial-missing=\{self.initial_missing}, final-missing=\{self.final_missing}, largest-gain=\{self.largest_gain}"
}

///|
pub fn RepairGateReport::failure_text(self : RepairGateReport) -> String {
  if self.failures.length() == 0 {
    return "no repair gate failures\n"
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
pub fn RepairGateReport::to_markdown(self : RepairGateReport) -> String {
  let builder = StringBuilder::new()
  builder.write_string("## CaseWeave Repair Gate\n\n")
  builder.write_string("- status: ")
  builder.write_string(if self.passed { "pass" } else { "fail" })
  builder.write_char('\n')
  builder.write_string("- additions: ")
  builder.write_string(self.additions.to_string())
  builder.write_char('\n')
  builder.write_string("- initial missing: ")
  builder.write_string(self.initial_missing.to_string())
  builder.write_char('\n')
  builder.write_string("- final missing: ")
  builder.write_string(self.final_missing.to_string())
  builder.write_char('\n')
  builder.write_string("- largest gain: ")
  builder.write_string(self.largest_gain.to_string())
  builder.write_string("\n\n")
  if self.failures.length() == 0 {
    builder.write_string("No repair gate failures.\n")
  } else {
    for failure in self.failures {
      builder.write_string("- ")
      builder.write_string(failure.message)
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
pub fn RepairOptions::normalize(self : RepairOptions) -> RepairOptions {
  {
    strength: if self.strength < 1 {
      1
    } else {
      self.strength
    },
    max_candidates: if self.max_candidates < 1 {
      1
    } else {
      self.max_candidates
    },
    max_suggestions: if self.max_suggestions < 0 {
      0
    } else {
      self.max_suggestions
    },
  }
}
