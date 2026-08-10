///|
/// Controls covering-array generation. `max_candidates` bounds the exhaustive
/// candidate phase; constraints are evaluated during enumeration so invalid
/// branches are pruned early.
pub(all) struct GenerationOptions {
  strength : Int
  max_candidates : Int
  minimize : Bool
} derive(Debug, Eq)

///|
pub fn GenerationOptions::default() -> GenerationOptions {
  { strength: 2, max_candidates: 100000, minimize: true }
}

///|
pub fn GenerationOptions::pairwise(
  max_candidates? : Int = 100000,
) -> GenerationOptions {
  { strength: 2, max_candidates, minimize: true }
}

///|
pub(all) struct GenerationStats {
  cartesian_size : Int64
  examined_candidates : Int
  feasible_candidates : Int
  required_interactions : Int
  selected_cases : Int
  removed_redundant_cases : Int
} derive(Debug, Eq)

///|
/// Generated cases plus reproducibility and compression statistics.
pub struct Suite {
  cases : Array[TestCase]
  strength : Int
  stats : GenerationStats
}

///|
pub fn Suite::cases(self : Suite) -> Array[TestCase] {
  self.cases.copy()
}

///|
pub fn Suite::length(self : Suite) -> Int {
  self.cases.length()
}

///|
pub fn Suite::strength(self : Suite) -> Int {
  self.strength
}

///|
pub fn Suite::stats(self : Suite) -> GenerationStats {
  self.stats
}

///|
/// Generate a deterministic constrained covering array. Candidate order,
/// greedy tie-breaking, and redundancy elimination are stable, so identical
/// inputs always produce identical suites.
pub fn generate(
  model : Model,
  constraints? : Array[Constraint] = [],
  options? : GenerationOptions = GenerationOptions::default(),
) -> Result[Suite, CaseWeaveError] {
  if options.strength < 1 || options.strength > model.parameter_count() {
    return Err(InvalidStrength(options.strength, model.parameter_count()))
  }
  if options.max_candidates < 1 {
    return Err(InvalidCandidateLimit(options.max_candidates))
  }
  match validate_constraints(constraints, model) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let enumeration = match
    enumerate_valid_rows(model, constraints, options.max_candidates) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  if enumeration.rows.length() == 0 {
    return Err(NoValidCases)
  }
  let interactions = collect_interactions(enumeration.rows, options.strength)
  let selected = match greedy_cover(enumeration.rows, interactions) {
    Err(error) => return Err(error)
    Ok(rows) => rows
  }
  let before_minimization = selected.length()
  if options.minimize {
    remove_redundant_rows(selected, interactions)
  }
  let cases : Array[TestCase] = []
  for row in selected {
    cases.push(model.decode(row))
  }
  let stats : GenerationStats = {
    cartesian_size: model.combination_count(),
    examined_candidates: enumeration.examined,
    feasible_candidates: enumeration.rows.length(),
    required_interactions: interactions.length(),
    selected_cases: cases.length(),
    removed_redundant_cases: before_minimization - cases.length(),
  }
  Ok({ cases, strength: options.strength, stats })
}

///|
priv struct EnumerationResult {
  rows : Array[Array[Int]]
  examined : Int
}

///|
priv struct EnumerationState {
  rows : Array[Array[Int]]
  mut examined : Int
  max_candidates : Int
}

///|
fn enumerate_valid_rows(
  model : Model,
  constraints : Array[Constraint],
  max_candidates : Int,
) -> Result[EnumerationResult, CaseWeaveError] {
  let row = Array::make(model.parameter_count(), -1)
  let state : EnumerationState = { rows: [], examined: 0, max_candidates }
  match enumerate_parameter(model, constraints, row, 0, state) {
    Err(error) => Err(error)
    Ok(_) => Ok({ rows: state.rows, examined: state.examined })
  }
}

///|
fn enumerate_parameter(
  model : Model,
  constraints : Array[Constraint],
  row : Array[Int],
  parameter_index : Int,
  state : EnumerationState,
) -> Result[Unit, CaseWeaveError] {
  if parameter_index == model.parameter_count() {
    state.examined = state.examined + 1
    if state.examined > state.max_candidates {
      return Err(CandidateLimitExceeded(state.max_candidates))
    }
    if partial_is_allowed(constraints, model, row) {
      state.rows.push(row.copy())
    }
    return Ok(())
  }
  let value_count = model.parameters[parameter_index].values.length()
  for value_index = 0; value_index < value_count; value_index = value_index + 1 {
    row[parameter_index] = value_index
    if partial_is_allowed(constraints, model, row) {
      match
        enumerate_parameter(model, constraints, row, parameter_index + 1, state) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    row[parameter_index] = -1
  }
  Ok(())
}

///|
priv struct Choice {
  parameter : Int
  value : Int
} derive(Eq)

///|
priv struct Interaction {
  choices : Array[Choice]
} derive(Eq)

///|
fn collect_interactions(
  valid_rows : Array[Array[Int]],
  strength : Int,
) -> Array[Interaction] {
  let interactions : Array[Interaction] = []
  if valid_rows.length() == 0 {
    return interactions
  }
  let parameter_indexes : Array[Int] = []
  choose_parameter_indexes(
    valid_rows, strength, 0, parameter_indexes, interactions,
  )
  interactions
}

///|
fn choose_parameter_indexes(
  valid_rows : Array[Array[Int]],
  remaining : Int,
  start : Int,
  chosen : Array[Int],
  interactions : Array[Interaction],
) -> Unit {
  if remaining == 0 {
    for row in valid_rows {
      let choices : Array[Choice] = []
      for parameter in chosen {
        choices.push({ parameter, value: row[parameter] })
      }
      let interaction : Interaction = { choices, }
      if !contains_interaction(interactions, interaction) {
        interactions.push(interaction)
      }
    }
    return
  }
  let parameter_count = valid_rows[0].length()
  let last_start = parameter_count - remaining
  for parameter = start; parameter <= last_start; parameter = parameter + 1 {
    chosen.push(parameter)
    choose_parameter_indexes(
      valid_rows,
      remaining - 1,
      parameter + 1,
      chosen,
      interactions,
    )
    ignore(chosen.pop())
  }
}

///|
fn contains_interaction(
  interactions : Array[Interaction],
  target : Interaction,
) -> Bool {
  for interaction in interactions {
    if interaction == target {
      return true
    }
  }
  false
}

///|
fn row_covers(row : Array[Int], interaction : Interaction) -> Bool {
  for choice in interaction.choices {
    if row[choice.parameter] != choice.value {
      return false
    }
  }
  true
}

///|
fn uncovered_gain(
  row : Array[Int],
  interactions : Array[Interaction],
  covered : Array[Bool],
) -> Int {
  let mut gain = 0
  for i = 0; i < interactions.length(); i = i + 1 {
    if !covered[i] && row_covers(row, interactions[i]) {
      gain = gain + 1
    }
  }
  gain
}

///|
fn greedy_cover(
  valid_rows : Array[Array[Int]],
  interactions : Array[Interaction],
) -> Result[Array[Array[Int]], CaseWeaveError] {
  let selected : Array[Array[Int]] = []
  let chosen = Array::make(valid_rows.length(), false)
  let covered = Array::make(interactions.length(), false)
  let mut covered_count = 0
  while covered_count < interactions.length() {
    let mut best_index = -1
    let mut best_gain = 0
    for row_index = 0
        row_index < valid_rows.length()
        row_index = row_index + 1 {
      if chosen[row_index] {
        continue
      }
      let gain = uncovered_gain(valid_rows[row_index], interactions, covered)
      if gain > best_gain {
        best_gain = gain
        best_index = row_index
      }
    }
    if best_index < 0 || best_gain == 0 {
      return Err(UncoverableInteraction)
    }
    chosen[best_index] = true
    let best_row = valid_rows[best_index]
    selected.push(best_row.copy())
    for interaction_index = 0
        interaction_index < interactions.length()
        interaction_index = interaction_index + 1 {
      if !covered[interaction_index] &&
        row_covers(best_row, interactions[interaction_index]) {
        covered[interaction_index] = true
        covered_count = covered_count + 1
      }
    }
  }
  Ok(selected)
}

///|
fn remove_redundant_rows(
  selected : Array[Array[Int]],
  interactions : Array[Interaction],
) -> Unit {
  let counts = Array::make(interactions.length(), 0)
  for row in selected {
    for interaction_index = 0
        interaction_index < interactions.length()
        interaction_index = interaction_index + 1 {
      if row_covers(row, interactions[interaction_index]) {
        counts[interaction_index] = counts[interaction_index] + 1
      }
    }
  }
  let mut row_index = selected.length() - 1
  while row_index >= 0 {
    let row = selected[row_index]
    let mut removable = true
    for interaction_index = 0
        interaction_index < interactions.length()
        interaction_index = interaction_index + 1 {
      if row_covers(row, interactions[interaction_index]) &&
        counts[interaction_index] <= 1 {
        removable = false
      }
    }
    if removable {
      for interaction_index = 0
          interaction_index < interactions.length()
          interaction_index = interaction_index + 1 {
        if row_covers(row, interactions[interaction_index]) {
          counts[interaction_index] = counts[interaction_index] - 1
        }
      }
      ignore(selected.remove(row_index))
    }
    row_index = row_index - 1
  }
}
