///|
/// Errors returned by model validation, constraint parsing, generation and
/// coverage analysis. Public operations return `Result` so callers can report
/// input problems without relying on panics.
pub(all) enum CaseWeaveError {
  EmptyModel
  EmptyParameterName(Int)
  DuplicateParameter(String)
  EmptyValues(String)
  EmptyValue(String, Int)
  DuplicateValue(String, String)
  InvalidStrength(Int, Int)
  InvalidCandidateLimit(Int)
  InvalidSuggestionLimit(Int)
  CandidateLimitExceeded(Int)
  NoValidCases
  UncoverableInteraction
  ParseError(Int, String)
  UnknownParameter(String)
  UnknownValue(String, String)
  InvalidCaseWidth(Int, Int)
  InvalidCaseValue(String, String)
  ConstraintViolation(Int, String)
} derive(Debug, Eq)
