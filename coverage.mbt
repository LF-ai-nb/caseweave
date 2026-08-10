///|
pub(all) struct NamedChoice {
  parameter : String
  value : String
} derive(Debug, Eq)

///|
pub(all) struct MissingInteraction {
  choices : Array[NamedChoice]
} derive(Debug, Eq)

///|
/// Coverage audit for an arbitrary suite. Missing interactions are named so
/// they can be printed directly in CI diagnostics.
pub(all) struct CoverageReport {
  strength : Int
  case_count : Int
  total_interactions : Int
  covered_interactions : Int
  coverage_percent : Double
  missing : Array[MissingInteraction]
} derive(Debug)

///|
pub fn CoverageReport::is_complete(self : CoverageReport) -> Bool {
  self.covered_interactions == self.total_interactions
}

///|
pub fn audit(
  model : Model,
  cases : Array[TestCase],
  strength? : Int = 2,
  constraints? : Array[Constraint] = [],
  max_candidates? : Int = 100000,
) -> Result[CoverageReport, CaseWeaveError] {
  if strength < 1 || strength > model.parameter_count() {
    return Err(InvalidStrength(strength, model.parameter_count()))
  }
  if max_candidates < 1 {
    return Err(InvalidCandidateLimit(max_candidates))
  }
  match validate_constraints(constraints, model) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let enumeration = match
    enumerate_valid_rows(model, constraints, max_candidates) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  if enumeration.rows.length() == 0 {
    return Err(NoValidCases)
  }
  let interactions = collect_interactions(enumeration.rows, strength)
  let covered = Array::make(interactions.length(), false)
  for case_index = 0; case_index < cases.length(); case_index = case_index + 1 {
    let row = match model.encode(cases[case_index]) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    for constraint in constraints {
      if evaluate_expression(constraint.expression, model, row) != Yes {
        return Err(ConstraintViolation(case_index, constraint.label))
      }
    }
    for interaction_index = 0
        interaction_index < interactions.length()
        interaction_index = interaction_index + 1 {
      if row_covers(row, interactions[interaction_index]) {
        covered[interaction_index] = true
      }
    }
  }
  let missing : Array[MissingInteraction] = []
  let mut covered_count = 0
  for interaction_index = 0
      interaction_index < interactions.length()
      interaction_index = interaction_index + 1 {
    if covered[interaction_index] {
      covered_count = covered_count + 1
    } else {
      missing.push(named_interaction(model, interactions[interaction_index]))
    }
  }
  let percent = if interactions.length() == 0 {
    100.0
  } else {
    covered_count.to_double() * 100.0 / interactions.length().to_double()
  }
  Ok({
    strength,
    case_count: cases.length(),
    total_interactions: interactions.length(),
    covered_interactions: covered_count,
    coverage_percent: percent,
    missing,
  })
}

///|
fn named_interaction(
  model : Model,
  interaction : Interaction,
) -> MissingInteraction {
  let choices : Array[NamedChoice] = []
  for choice in interaction.choices {
    choices.push({
      parameter: model.parameters[choice.parameter].name,
      value: model.parameters[choice.parameter].values[choice.value],
    })
  }
  { choices, }
}
