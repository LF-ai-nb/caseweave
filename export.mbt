///|
/// Render a generated suite as CSV with a header row in model order.
pub fn Suite::to_csv(self : Suite, model : Model) -> String {
  cases_to_csv(model, self.cases)
}

///|
/// Render a generated suite as a compact JSON document.
pub fn Suite::to_json(self : Suite, model : Model) -> String {
  let builder = StringBuilder::new()
  let stats = self.stats
  builder.write_string("{\n")
  builder.write_string("  \"strength\": ")
  builder.write_string(self.strength.to_string())
  builder.write_string(",\n")
  builder.write_string("  \"stats\": {\n")
  write_json_int64_field(builder, "cartesian_size", stats.cartesian_size, true)
  write_json_int_field(
    builder,
    "examined_candidates",
    stats.examined_candidates,
    true,
  )
  write_json_int_field(
    builder,
    "feasible_candidates",
    stats.feasible_candidates,
    true,
  )
  write_json_int_field(
    builder,
    "required_interactions",
    stats.required_interactions,
    true,
  )
  write_json_int_field(builder, "selected_cases", stats.selected_cases, true)
  write_json_int_field(
    builder,
    "removed_redundant_cases",
    stats.removed_redundant_cases,
    false,
  )
  builder.write_string("  },\n")
  builder.write_string("  \"parameters\": [\n")
  for i = 0; i < model.parameters.length(); i = i + 1 {
    let parameter = model.parameters[i]
    builder.write_string("    {\"name\": ")
    builder.write_string(json_string(parameter.name))
    builder.write_string(", \"values\": [")
    for j = 0; j < parameter.values.length(); j = j + 1 {
      if j > 0 {
        builder.write_string(", ")
      }
      builder.write_string(json_string(parameter.values[j]))
    }
    builder.write_string("]}")
    if i + 1 < model.parameters.length() {
      builder.write_string(",")
    }
    builder.write_string("\n")
  }
  builder.write_string("  ],\n")
  builder.write_string("  \"cases\": [\n")
  for case_index = 0
      case_index < self.cases.length()
      case_index = case_index + 1 {
    write_json_case(builder, model, self.cases[case_index], "    ")
    if case_index + 1 < self.cases.length() {
      builder.write_string(",")
    }
    builder.write_string("\n")
  }
  builder.write_string("  ]\n")
  builder.write_string("}\n")
  builder.to_string()
}

///|
/// Render a generated suite as a Markdown table for READMEs and issue reports.
pub fn Suite::to_markdown(self : Suite, model : Model) -> String {
  cases_to_markdown(model, self.cases)
}

///|
/// Render arbitrary cases as CSV. This is useful when callers load a suite from
/// another source and want the same escaping rules as generated suites.
pub fn cases_to_csv(model : Model, cases : Array[TestCase]) -> String {
  let builder = StringBuilder::new()
  for parameter_index = 0
      parameter_index < model.parameters.length()
      parameter_index = parameter_index + 1 {
    if parameter_index > 0 {
      builder.write_char(',')
    }
    builder.write_string(csv_field(model.parameters[parameter_index].name))
  }
  builder.write_char('\n')
  for test_case in cases {
    for value_index = 0
        value_index < test_case.values.length()
        value_index = value_index + 1 {
      if value_index > 0 {
        builder.write_char(',')
      }
      builder.write_string(csv_field(test_case.values[value_index]))
    }
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
/// Render arbitrary cases as a Markdown table.
pub fn cases_to_markdown(model : Model, cases : Array[TestCase]) -> String {
  let builder = StringBuilder::new()
  builder.write_string("| # |")
  for parameter in model.parameters {
    builder.write_char(' ')
    builder.write_string(markdown_cell(parameter.name))
    builder.write_string(" |")
  }
  builder.write_char('\n')
  builder.write_string("| --- |")
  for _ in model.parameters {
    builder.write_string(" --- |")
  }
  builder.write_char('\n')
  for case_index = 0; case_index < cases.length(); case_index = case_index + 1 {
    builder.write_string("| ")
    builder.write_string((case_index + 1).to_string())
    builder.write_string(" |")
    let test_case = cases[case_index]
    for value in test_case.values {
      builder.write_char(' ')
      builder.write_string(markdown_cell(value))
      builder.write_string(" |")
    }
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
/// One-line generation summary suitable for CLI output.
pub fn Suite::summary(self : Suite) -> String {
  let stats = self.stats
  "strength=\{self.strength}, cases=\{self.cases.length()}, interactions=\{stats.required_interactions}, candidates=\{stats.feasible_candidates}/\{stats.cartesian_size}, removed=\{stats.removed_redundant_cases}"
}

///|
/// One-line coverage summary suitable for CI logs.
pub fn CoverageReport::summary(self : CoverageReport) -> String {
  "strength=\{self.strength}, cases=\{self.case_count}, coverage=\{self.coverage_percent}%, covered=\{self.covered_interactions}/\{self.total_interactions}, missing=\{self.missing.length()}"
}

///|
/// Render missing interactions as readable lines.
pub fn CoverageReport::missing_text(self : CoverageReport) -> String {
  let builder = StringBuilder::new()
  if self.missing.length() == 0 {
    builder.write_string("no missing interactions\n")
    return builder.to_string()
  }
  for index = 0; index < self.missing.length(); index = index + 1 {
    builder.write_string("- ")
    let interaction = self.missing[index]
    for choice_index = 0
        choice_index < interaction.choices.length()
        choice_index = choice_index + 1 {
      if choice_index > 0 {
        builder.write_string(", ")
      }
      let choice = interaction.choices[choice_index]
      builder.write_string(choice.parameter)
      builder.write_char('=')
      builder.write_string(choice.value)
    }
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn write_json_int_field(
  builder : StringBuilder,
  name : String,
  value : Int,
  comma : Bool,
) -> Unit {
  builder.write_string("    ")
  builder.write_string(json_string(name))
  builder.write_string(": ")
  builder.write_string(value.to_string())
  if comma {
    builder.write_string(",")
  }
  builder.write_string("\n")
}

///|
fn write_json_int64_field(
  builder : StringBuilder,
  name : String,
  value : Int64,
  comma : Bool,
) -> Unit {
  builder.write_string("    ")
  builder.write_string(json_string(name))
  builder.write_string(": ")
  builder.write_string(value.to_string())
  if comma {
    builder.write_string(",")
  }
  builder.write_string("\n")
}

///|
fn write_json_case(
  builder : StringBuilder,
  model : Model,
  test_case : TestCase,
  indent : String,
) -> Unit {
  builder.write_string(indent)
  builder.write_char('{')
  for parameter_index = 0
      parameter_index < model.parameters.length()
      parameter_index = parameter_index + 1 {
    if parameter_index > 0 {
      builder.write_string(", ")
    }
    builder.write_string(json_string(model.parameters[parameter_index].name))
    builder.write_string(": ")
    builder.write_string(json_string(test_case.values[parameter_index]))
  }
  builder.write_char('}')
}

///|
fn csv_field(value : String) -> String {
  let chars = value.to_array()
  let mut quoted = false
  for char in chars {
    if char == ',' || char == '"' || char == '\n' || char == '\r' {
      quoted = true
    }
  }
  if !quoted {
    return value
  }
  let builder = StringBuilder::new()
  builder.write_char('"')
  for char in chars {
    if char == '"' {
      builder.write_string("\"\"")
    } else {
      builder.write_char(char)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn json_string(value : String) -> String {
  let builder = StringBuilder::new()
  builder.write_char('"')
  for char in value.to_array() {
    match char {
      '"' => builder.write_string("\\\"")
      '\\' => builder.write_string("\\\\")
      '\n' => builder.write_string("\\n")
      '\r' => builder.write_string("\\r")
      '\t' => builder.write_string("\\t")
      _ => builder.write_char(char)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn markdown_cell(value : String) -> String {
  let builder = StringBuilder::new()
  for char in value.to_array() {
    match char {
      '|' => builder.write_string("\\|")
      '\\' => builder.write_string("\\\\")
      '\n' => builder.write_string("<br>")
      '\r' => ()
      _ => builder.write_char(char)
    }
  }
  builder.to_string()
}
