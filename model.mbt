///|
/// One dimension in the input space. Values are kept in declaration order so
/// generation and exported output remain deterministic.
pub(all) struct Parameter {
  name : String
  values : Array[String]
} derive(Debug, Eq)

///|
pub fn Parameter::new(name : String, values : Array[String]) -> Parameter {
  { name, values }
}

///|
/// A validated ordered collection of parameters.
pub struct Model {
  parameters : Array[Parameter]
}

///|
pub fn Model::new(
  parameters : Array[Parameter],
) -> Result[Model, CaseWeaveError] {
  if parameters.length() == 0 {
    return Err(EmptyModel)
  }
  for i = 0; i < parameters.length(); i = i + 1 {
    let parameter = parameters[i]
    if parameter.name.length() == 0 {
      return Err(EmptyParameterName(i))
    }
    for j = 0; j < i; j = j + 1 {
      if parameters[j].name == parameter.name {
        return Err(DuplicateParameter(parameter.name))
      }
    }
    if parameter.values.length() == 0 {
      return Err(EmptyValues(parameter.name))
    }
    for value_index = 0
        value_index < parameter.values.length()
        value_index = value_index + 1 {
      let value = parameter.values[value_index]
      if value.length() == 0 {
        return Err(EmptyValue(parameter.name, value_index))
      }
      for previous = 0; previous < value_index; previous = previous + 1 {
        if parameter.values[previous] == value {
          return Err(DuplicateValue(parameter.name, value))
        }
      }
    }
  }
  Ok({ parameters, })
}

///|
pub fn Model::parameter_count(self : Model) -> Int {
  self.parameters.length()
}

///|
pub fn Model::parameters(self : Model) -> Array[Parameter] {
  self.parameters.copy()
}

///|
pub fn Model::parameter(self : Model, index : Int) -> Parameter? {
  if index < 0 || index >= self.parameters.length() {
    None
  } else {
    Some(self.parameters[index])
  }
}

///|
pub fn Model::parameter_index(self : Model, name : String) -> Int? {
  for i = 0; i < self.parameters.length(); i = i + 1 {
    if self.parameters[i].name == name {
      return Some(i)
    }
  }
  None
}

///|
pub fn Model::value_index(
  self : Model,
  parameter_index : Int,
  value : String,
) -> Int? {
  if parameter_index < 0 || parameter_index >= self.parameters.length() {
    return None
  }
  let values = self.parameters[parameter_index].values
  for i = 0; i < values.length(); i = i + 1 {
    if values[i] == value {
      return Some(i)
    }
  }
  None
}

///|
pub fn Model::combination_count(self : Model) -> Int64 {
  let mut count = 1L
  for parameter in self.parameters {
    count = count * parameter.values.length().to_int64()
  }
  count
}

///|
/// A concrete test vector in model order.
pub(all) struct TestCase {
  values : Array[String]
} derive(Debug, Eq)

///|
pub fn TestCase::new(values : Array[String]) -> TestCase {
  { values, }
}

///|
pub fn TestCase::get(self : TestCase, index : Int) -> String? {
  if index < 0 || index >= self.values.length() {
    None
  } else {
    Some(self.values[index])
  }
}

///|
pub fn TestCase::value_for(
  self : TestCase,
  model : Model,
  parameter : String,
) -> String? {
  match model.parameter_index(parameter) {
    None => None
    Some(index) => self.get(index)
  }
}

///|
pub fn Model::validate_case(
  self : Model,
  test_case : TestCase,
) -> Result[Unit, CaseWeaveError] {
  if test_case.values.length() != self.parameters.length() {
    return Err(
      InvalidCaseWidth(self.parameters.length(), test_case.values.length()),
    )
  }
  for i = 0; i < self.parameters.length(); i = i + 1 {
    if self.value_index(i, test_case.values[i]) is None {
      return Err(InvalidCaseValue(self.parameters[i].name, test_case.values[i]))
    }
  }
  Ok(())
}

///|
fn Model::decode(self : Model, row : Array[Int]) -> TestCase {
  let values : Array[String] = []
  for i = 0; i < self.parameters.length(); i = i + 1 {
    values.push(self.parameters[i].values[row[i]])
  }
  { values, }
}

///|
fn Model::encode(
  self : Model,
  test_case : TestCase,
) -> Result[Array[Int], CaseWeaveError] {
  match self.validate_case(test_case) {
    Err(error) => Err(error)
    Ok(_) => {
      let row : Array[Int] = []
      for i = 0; i < self.parameters.length(); i = i + 1 {
        match self.value_index(i, test_case.values[i]) {
          None =>
            return Err(
              InvalidCaseValue(self.parameters[i].name, test_case.values[i]),
            )
          Some(value_index) => row.push(value_index)
        }
      }
      Ok(row)
    }
  }
}
