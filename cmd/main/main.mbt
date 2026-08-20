///|
fn sample_scenario() -> String {
  "name: Deployment risk matrix\n" +
  "strength: 2\n" +
  "max-candidates: 1000\n" +
  "minimize: true\n" +
  "param os: linux, windows, macos\n" +
  "param browser: chrome, firefox, safari\n" +
  "param auth: password, oidc\n" +
  "param region: cn, eu, us\n" +
  "constraint safari requires macos: browser == safari => os == macos\n" +
  "exclude: os=windows, browser=safari\n" +
  "include: os=linux, browser=chrome, auth=oidc, region=cn\n" +
  "risk browser=safari: 4: browser-specific rendering risk\n" +
  "risk os=macos, browser=safari: 9: Safari path must stay visible\n"
}

///|
fn main {
  let spec = match @caseweave.ScenarioSpec::parse(sample_scenario()) {
    Ok(value) => value
    Err(_) => panic()
  }
  let run = match spec.run() {
    Ok(value) => value
    Err(_) => panic()
  }
  let gate = run.evaluate_gate(spec, gate=@caseweave.ScenarioGate::strict())
  println("CaseWeave scenario-driven deployment matrix")
  println(spec.summary())
  println(run.suite.summary())
  println(run.coverage.summary())
  println(gate.summary())
  println("")
  println("Top risk-ranked cases")
  println(run.risk_markdown(top=5))
  println("Generated matrix")
  println(run.cases_markdown())
}
