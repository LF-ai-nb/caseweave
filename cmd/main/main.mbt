///|
fn main {
  let model = match
    @caseweave.Model::new([
      @caseweave.Parameter::new("os", ["linux", "windows", "macos"]),
      @caseweave.Parameter::new("browser", ["chrome", "firefox", "safari"]),
      @caseweave.Parameter::new("auth", ["password", "oidc"]),
      @caseweave.Parameter::new("region", ["cn", "eu", "us"]),
    ]) {
    Ok(value) => value
    Err(_) => panic()
  }
  let safari_rule = match
    @caseweave.Constraint::parse(
      "Safari is only supported on macOS", "browser == safari => os == macos",
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
  let suite = match
    @caseweave.generate(
      model,
      constraints=[safari_rule],
      options=@caseweave.GenerationOptions::pairwise(),
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
  let report = match
    @caseweave.audit(model, suite.cases(), strength=2, constraints=[safari_rule]) {
    Ok(value) => value
    Err(_) => panic()
  }
  println("CaseWeave deployment matrix")
  println(suite.summary())
  println(report.summary())
  println("")
  println(suite.to_markdown(model))
}
