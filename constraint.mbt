///|
/// Boolean constraint language used to exclude impossible or unwanted test
/// combinations. Atoms address parameters and values by name, keeping models
/// readable and independent from internal indexes.
pub(all) enum ConstraintExpr {
  Equal(String, String)
  NotEqual(String, String)
  OneOf(String, Array[String])
  NoneOf(String, Array[String])
  And(ConstraintExpr, ConstraintExpr)
  Or(ConstraintExpr, ConstraintExpr)
  Implies(ConstraintExpr, ConstraintExpr)
  Not(ConstraintExpr)
  Always
  Never
} derive(Debug, Eq)

///|
pub(all) struct Constraint {
  label : String
  expression : ConstraintExpr
} derive(Debug, Eq)

///|
pub fn Constraint::new(
  label : String,
  expression : ConstraintExpr,
) -> Constraint {
  { label, expression }
}

///|
pub fn Constraint::parse(
  label : String,
  source : String,
) -> Result[Constraint, CaseWeaveError] {
  match tokenize_constraint(source) {
    Err(error) => Err(error)
    Ok(tokens) => {
      let parser = Parser::new(tokens)
      match parser.parse_expression() {
        Err(error) => Err(error)
        Ok(expression) =>
          if parser.current().token != End {
            Err(ParseError(parser.current().position, "unexpected token"))
          } else {
            Ok({ label, expression })
          }
      }
    }
  }
}

///|
pub fn Constraint::validate(
  self : Constraint,
  model : Model,
) -> Result[Unit, CaseWeaveError] {
  validate_expression(self.expression, model)
}

///|
pub fn Constraint::matches(
  self : Constraint,
  model : Model,
  test_case : TestCase,
) -> Result[Bool, CaseWeaveError] {
  match self.validate(model) {
    Err(error) => Err(error)
    Ok(_) =>
      match model.validate_case(test_case) {
        Err(error) => Err(error)
        Ok(_) => {
          let row : Array[Int] = []
          for i = 0; i < model.parameter_count(); i = i + 1 {
            let value = test_case.values[i]
            match model.value_index(i, value) {
              Some(index) => row.push(index)
              None =>
                return Err(InvalidCaseValue(model.parameters[i].name, value))
            }
          }
          Ok(evaluate_expression(self.expression, model, row) == Yes)
        }
      }
  }
}

///|
fn validate_expression(
  expression : ConstraintExpr,
  model : Model,
) -> Result[Unit, CaseWeaveError] {
  match expression {
    Equal(parameter, value) | NotEqual(parameter, value) =>
      validate_atom(parameter, [value], model)
    OneOf(parameter, values) | NoneOf(parameter, values) => {
      if values.length() == 0 {
        return Err(ParseError(0, "value list must not be empty"))
      }
      validate_atom(parameter, values, model)
    }
    And(left, right) | Or(left, right) | Implies(left, right) =>
      match validate_expression(left, model) {
        Err(error) => Err(error)
        Ok(_) => validate_expression(right, model)
      }
    Not(inner) => validate_expression(inner, model)
    Always | Never => Ok(())
  }
}

///|
fn validate_atom(
  parameter : String,
  values : Array[String],
  model : Model,
) -> Result[Unit, CaseWeaveError] {
  match model.parameter_index(parameter) {
    None => Err(UnknownParameter(parameter))
    Some(parameter_index) => {
      for value in values {
        if model.value_index(parameter_index, value) is None {
          return Err(UnknownValue(parameter, value))
        }
      }
      Ok(())
    }
  }
}

///|
priv enum Truth {
  Yes
  No
  Unknown
} derive(Eq)

///|
fn not_truth(value : Truth) -> Truth {
  match value {
    Yes => No
    No => Yes
    Unknown => Unknown
  }
}

///|
fn evaluate_expression(
  expression : ConstraintExpr,
  model : Model,
  row : Array[Int],
) -> Truth {
  match expression {
    Equal(parameter, value) =>
      evaluate_atom(parameter, [value], false, model, row)
    NotEqual(parameter, value) =>
      evaluate_atom(parameter, [value], true, model, row)
    OneOf(parameter, values) =>
      evaluate_atom(parameter, values, false, model, row)
    NoneOf(parameter, values) =>
      evaluate_atom(parameter, values, true, model, row)
    And(left, right) => {
      let left_result = evaluate_expression(left, model, row)
      let right_result = evaluate_expression(right, model, row)
      if left_result == No || right_result == No {
        No
      } else if left_result == Yes && right_result == Yes {
        Yes
      } else {
        Unknown
      }
    }
    Or(left, right) => {
      let left_result = evaluate_expression(left, model, row)
      let right_result = evaluate_expression(right, model, row)
      if left_result == Yes || right_result == Yes {
        Yes
      } else if left_result == No && right_result == No {
        No
      } else {
        Unknown
      }
    }
    Implies(left, right) => {
      let antecedent = evaluate_expression(left, model, row)
      let consequent = evaluate_expression(right, model, row)
      if antecedent == No || consequent == Yes {
        Yes
      } else if antecedent == Yes && consequent == No {
        No
      } else {
        Unknown
      }
    }
    Not(inner) => not_truth(evaluate_expression(inner, model, row))
    Always => Yes
    Never => No
  }
}

///|
fn evaluate_atom(
  parameter : String,
  accepted : Array[String],
  negate : Bool,
  model : Model,
  row : Array[Int],
) -> Truth {
  let parameter_index = match model.parameter_index(parameter) {
    Some(index) => index
    None => return No
  }
  if row[parameter_index] < 0 {
    return Unknown
  }
  let actual = model.parameters[parameter_index].values[row[parameter_index]]
  let mut found = false
  for value in accepted {
    if value == actual {
      found = true
    }
  }
  let matches = if negate { !found } else { found }
  if matches {
    Yes
  } else {
    No
  }
}

///|
fn validate_constraints(
  constraints : Array[Constraint],
  model : Model,
) -> Result[Unit, CaseWeaveError] {
  for constraint in constraints {
    match constraint.validate(model) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn partial_is_allowed(
  constraints : Array[Constraint],
  model : Model,
  row : Array[Int],
) -> Bool {
  for constraint in constraints {
    if evaluate_expression(constraint.expression, model, row) == No {
      return false
    }
  }
  true
}

///|
priv enum Token {
  Identifier(String)
  Text(String)
  EqualEqual
  BangEqual
  AndAnd
  OrOr
  Arrow
  Bang
  LeftParen
  RightParen
  LeftBracket
  RightBracket
  Comma
  KeywordIn
  KeywordNot
  KeywordAnd
  KeywordOr
  KeywordTrue
  KeywordFalse
  End
} derive(Eq)

///|
priv struct SpannedToken {
  token : Token
  position : Int
}

///|
fn is_space(character : Char) -> Bool {
  character == ' ' ||
  character == '\t' ||
  character == '\r' ||
  character == '\n'
}

///|
fn is_identifier_start(character : Char) -> Bool {
  (character >= 'a' && character <= 'z') ||
  (character >= 'A' && character <= 'Z') ||
  character == '_'
}

///|
fn is_identifier_continue(character : Char) -> Bool {
  is_identifier_start(character) ||
  (character >= '0' && character <= '9') ||
  character == '-' ||
  character == '.' ||
  character == ':' ||
  character == '/'
}

///|
fn keyword_or_identifier(text : String) -> Token {
  match text {
    "in" => KeywordIn
    "not" => KeywordNot
    "and" => KeywordAnd
    "or" => KeywordOr
    "true" => KeywordTrue
    "false" => KeywordFalse
    _ => Identifier(text)
  }
}

///|
fn tokenize_constraint(
  source : String,
) -> Result[Array[SpannedToken], CaseWeaveError] {
  let characters = source.to_array()
  let tokens : Array[SpannedToken] = []
  let mut index = 0
  while index < characters.length() {
    let character = characters[index]
    if is_space(character) {
      index = index + 1
      continue
    }
    if is_identifier_start(character) {
      let start = index
      let builder = StringBuilder::new()
      while index < characters.length() &&
            is_identifier_continue(characters[index]) {
        builder.write_char(characters[index])
        index = index + 1
      }
      tokens.push({
        token: keyword_or_identifier(builder.to_string()),
        position: start,
      })
      continue
    }
    if character == '"' {
      let start = index
      index = index + 1
      let builder = StringBuilder::new()
      let mut closed = false
      while index < characters.length() {
        let current = characters[index]
        if current == '"' {
          closed = true
          index = index + 1
          break
        }
        if current == '\\' {
          if index + 1 >= characters.length() {
            return Err(ParseError(index, "unterminated escape sequence"))
          }
          let escaped = characters[index + 1]
          match escaped {
            '"' => builder.write_char('"')
            '\\' => builder.write_char('\\')
            'n' => builder.write_char('\n')
            'r' => builder.write_char('\r')
            't' => builder.write_char('\t')
            _ => return Err(ParseError(index, "unsupported escape sequence"))
          }
          index = index + 2
        } else {
          builder.write_char(current)
          index = index + 1
        }
      }
      if !closed {
        return Err(ParseError(start, "unterminated string literal"))
      }
      tokens.push({ token: Text(builder.to_string()), position: start })
      continue
    }
    let start = index
    match character {
      '=' =>
        if index + 1 < characters.length() && characters[index + 1] == '=' {
          tokens.push({ token: EqualEqual, position: start })
          index = index + 2
        } else if index + 1 < characters.length() &&
          characters[index + 1] == '>' {
          tokens.push({ token: Arrow, position: start })
          index = index + 2
        } else {
          return Err(ParseError(index, "expected '==' or '=>'"))
        }
      '!' =>
        if index + 1 < characters.length() && characters[index + 1] == '=' {
          tokens.push({ token: BangEqual, position: start })
          index = index + 2
        } else {
          tokens.push({ token: Bang, position: start })
          index = index + 1
        }
      '&' =>
        if index + 1 < characters.length() && characters[index + 1] == '&' {
          tokens.push({ token: AndAnd, position: start })
          index = index + 2
        } else {
          return Err(ParseError(index, "expected '&&'"))
        }
      '|' =>
        if index + 1 < characters.length() && characters[index + 1] == '|' {
          tokens.push({ token: OrOr, position: start })
          index = index + 2
        } else {
          return Err(ParseError(index, "expected '||'"))
        }
      '(' => {
        tokens.push({ token: LeftParen, position: start })
        index = index + 1
      }
      ')' => {
        tokens.push({ token: RightParen, position: start })
        index = index + 1
      }
      '[' => {
        tokens.push({ token: LeftBracket, position: start })
        index = index + 1
      }
      ']' => {
        tokens.push({ token: RightBracket, position: start })
        index = index + 1
      }
      ',' => {
        tokens.push({ token: Comma, position: start })
        index = index + 1
      }
      _ => return Err(ParseError(index, "unexpected character"))
    }
  }
  tokens.push({ token: End, position: characters.length() })
  Ok(tokens)
}

///|
priv struct Parser {
  tokens : Array[SpannedToken]
  mut index : Int
}

///|
fn Parser::new(tokens : Array[SpannedToken]) -> Parser {
  { tokens, index: 0 }
}

///|
fn Parser::current(self : Parser) -> SpannedToken {
  self.tokens[self.index]
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.index + 1 < self.tokens.length() {
    self.index = self.index + 1
  }
}

///|
fn Parser::parse_expression(
  self : Parser,
) -> Result[ConstraintExpr, CaseWeaveError] {
  self.parse_implies()
}

///|
fn Parser::parse_implies(
  self : Parser,
) -> Result[ConstraintExpr, CaseWeaveError] {
  let left = match self.parse_or() {
    Err(error) => return Err(error)
    Ok(expression) => expression
  }
  if self.current().token == Arrow {
    self.advance()
    match self.parse_implies() {
      Err(error) => Err(error)
      Ok(right) => Ok(Implies(left, right))
    }
  } else {
    Ok(left)
  }
}

///|
fn Parser::parse_or(self : Parser) -> Result[ConstraintExpr, CaseWeaveError] {
  let mut expression = match self.parse_and() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  while self.current().token == OrOr || self.current().token == KeywordOr {
    self.advance()
    let right = match self.parse_and() {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    expression = Or(expression, right)
  }
  Ok(expression)
}

///|
fn Parser::parse_and(self : Parser) -> Result[ConstraintExpr, CaseWeaveError] {
  let mut expression = match self.parse_unary() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  while self.current().token == AndAnd || self.current().token == KeywordAnd {
    self.advance()
    let right = match self.parse_unary() {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    expression = And(expression, right)
  }
  Ok(expression)
}

///|
fn Parser::parse_unary(self : Parser) -> Result[ConstraintExpr, CaseWeaveError] {
  if self.current().token == Bang || self.current().token == KeywordNot {
    self.advance()
    match self.parse_unary() {
      Err(error) => Err(error)
      Ok(expression) => Ok(Not(expression))
    }
  } else {
    self.parse_primary()
  }
}

///|
fn Parser::parse_primary(
  self : Parser,
) -> Result[ConstraintExpr, CaseWeaveError] {
  match self.current().token {
    KeywordTrue => {
      self.advance()
      Ok(Always)
    }
    KeywordFalse => {
      self.advance()
      Ok(Never)
    }
    LeftParen => {
      self.advance()
      let expression = match self.parse_expression() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if self.current().token != RightParen {
        return Err(ParseError(self.current().position, "expected ')'"))
      }
      self.advance()
      Ok(expression)
    }
    Identifier(parameter) => {
      self.advance()
      self.parse_comparison(parameter)
    }
    _ => Err(ParseError(self.current().position, "expected expression"))
  }
}

///|
fn Parser::parse_comparison(
  self : Parser,
  parameter : String,
) -> Result[ConstraintExpr, CaseWeaveError] {
  match self.current().token {
    EqualEqual => {
      self.advance()
      match self.parse_value() {
        Err(error) => Err(error)
        Ok(value) => Ok(Equal(parameter, value))
      }
    }
    BangEqual => {
      self.advance()
      match self.parse_value() {
        Err(error) => Err(error)
        Ok(value) => Ok(NotEqual(parameter, value))
      }
    }
    KeywordIn => {
      self.advance()
      match self.parse_value_list() {
        Err(error) => Err(error)
        Ok(values) => Ok(OneOf(parameter, values))
      }
    }
    KeywordNot => {
      self.advance()
      if self.current().token != KeywordIn {
        return Err(
          ParseError(self.current().position, "expected 'in' after 'not'"),
        )
      }
      self.advance()
      match self.parse_value_list() {
        Err(error) => Err(error)
        Ok(values) => Ok(NoneOf(parameter, values))
      }
    }
    _ =>
      Err(
        ParseError(
          self.current().position,
          "expected '==', '!=', 'in', or 'not in'",
        ),
      )
  }
}

///|
fn Parser::parse_value(self : Parser) -> Result[String, CaseWeaveError] {
  match self.current().token {
    Text(value) | Identifier(value) => {
      self.advance()
      Ok(value)
    }
    KeywordTrue => {
      self.advance()
      Ok("true")
    }
    KeywordFalse => {
      self.advance()
      Ok("false")
    }
    _ => Err(ParseError(self.current().position, "expected value"))
  }
}

///|
fn Parser::parse_value_list(
  self : Parser,
) -> Result[Array[String], CaseWeaveError] {
  if self.current().token != LeftBracket {
    return Err(ParseError(self.current().position, "expected '['"))
  }
  self.advance()
  let values : Array[String] = []
  if self.current().token == RightBracket {
    return Err(
      ParseError(self.current().position, "value list must not be empty"),
    )
  }
  while true {
    match self.parse_value() {
      Err(error) => return Err(error)
      Ok(value) => values.push(value)
    }
    if self.current().token == Comma {
      self.advance()
      continue
    }
    if self.current().token != RightBracket {
      return Err(ParseError(self.current().position, "expected ',' or ']'"))
    }
    self.advance()
    break
  }
  Ok(values)
}
