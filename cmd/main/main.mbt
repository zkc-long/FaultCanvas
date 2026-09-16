///|

///|
async fn load_config(path : String) -> @config.Config {
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => fail("cannot open configuration: " + path)
  }
  defer file.close()
  let text = file.read_all().text()
  match @config.parse(text) {
    Ok(config) => config
    Err(_) => fail("invalid FaultCanvas configuration: " + path)
  }
}

///|
fn simulated_request(arguments : Array[String]) -> @core.HttpRequest {
  match arguments {
    [verb, path, ..] => @core.HttpRequest::new(verb, path, [], [], "")
    _ => @core.HttpRequest::new("GET", "/", [], [], "")
  }
}

///|
fn print_decision(decision : @runtime.Decision) -> Unit {
  let rule = match decision.rule_id {
    Some(value) => value
    None => "<fallback>"
  }
  println(
    "session=" +
    decision.session +
    " rule=" +
    rule +
    " phase=" +
    decision.phase_before +
    "->" +
    decision.phase_after +
    " delay_ms=" +
    decision.plan.delay_ms.to_string(),
  )
}

///|
fn simulated_outcome(decision : @runtime.Decision) -> @report.Outcome {
  match decision.plan.source {
    @fault.Fixed(response) => @report.Response(response.status)
    @fault.ConnectionAbort(reason) => @report.Aborted(reason)
    @fault.Upstream => @report.Response(200)
  }
}

///|
fn print_simulation_stats(
  config : @config.Config,
  arguments : Array[String],
) -> Unit {
  let engine = @runtime.Engine::new(config)
  let journal = @report.Journal::new(config.policy.max_events())
  for sequence = 1; sequence <= 3; sequence = sequence + 1 {
    let decision = engine.decide(simulated_request(arguments))
    journal.record(decision, simulated_outcome(decision), sequence * 10)
  }
  let stats = @observe.summarize(journal.events(), @observe.EventFilter::any())
  println(stats.to_json())
}

///|
/// Native FaultCanvas command line interface.
///
/// Usage:
/// `faultcanvas check CONFIG`
/// `faultcanvas simulate CONFIG [METHOD PATH]`
/// `faultcanvas serve CONFIG`
/// `faultcanvas report CONFIG`
/// `faultcanvas stats CONFIG [METHOD PATH]`
/// `faultcanvas redact CONFIG TEXT...`
async fn run_cli() -> Unit {
  let matches = @argparse.Command(
    "faultcanvas",
    about="Programmable HTTP fault proxy and service virtualization gateway",
    positionals=[
      PositionArg("command"),
      PositionArg("config"),
      PositionArg("arguments", num_args=ValueRange(lower=0)),
    ],
  ).parse()
  guard matches.values
    is {
      "command": [command],
      "config": [config_path],
      "arguments": arguments,
      ..
    } else {
    fail("expected COMMAND and CONFIG")
  }
  let config = load_config(config_path)
  match command {
    "check" =>
      println("valid version=1 rules=" + config.rules.length().to_string())
    "simulate" => {
      let engine = @runtime.Engine::new(config)
      print_decision(engine.decide(simulated_request(arguments)))
    }
    "serve" => @native.serve(config)
    "report" =>
      println(
        "{\"version\":1,\"rules\":" +
        config.rules.length().to_string() +
        ",\"transitions\":" +
        config.transitions.length().to_string() +
        "}",
      )
    "stats" => print_simulation_stats(config, arguments)
    "redact" => println(config.policy.redact_free_text(arguments.join(" ")))
    _ => fail("unknown command: " + command)
  }
}

///|
async fn main {
  run_cli() catch {
    _ => println("faultcanvas: command failed")
  }
}
