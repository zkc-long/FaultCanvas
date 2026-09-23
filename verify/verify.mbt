///|
/// One deterministic interaction in an acceptance or regression suite.
pub(all) struct Step {
  id : String
  request : @core.HttpRequest
  expected_rule_id : String?
  expected_phase_before : String?
  expected_phase_after : String?
  expected_outcome : String?
  expected_status : Int?
  expected_body_contains : String?
  expected_delay_ms : Int?
} derive(Debug, Eq)

///|
/// A suite models a baseline upstream response so passthrough rules can be
/// checked without opening a network connection.
pub(all) struct Suite {
  version : Int
  upstream_status : Int
  steps : Array[Step]
} derive(Debug, Eq)

///|
pub(all) enum SuiteError {
  InvalidJson
  ExpectedObject(String)
  ExpectedArray(String)
  ExpectedString(String)
  ExpectedInteger(String)
  MissingField(String)
  UnsupportedVersion(Int)
  InvalidUpstreamStatus(Int)
  InvalidOutcome(String)
  EmptySuite
  TooManySteps(Int)
  EmptyStepId
  DuplicateStepId(String)
} derive(Debug, Eq)

///|
pub(all) struct StepResult {
  id : String
  passed : Bool
  failures : Array[String]
  rule_id : String?
  phase_before : String
  phase_after : String
  outcome : String
  status : Int?
  delay_ms : Int
} derive(Debug, Eq)

///|
pub(all) struct Report {
  passed : Int
  failed : Int
  steps : Array[StepResult]
} derive(Debug, Eq)

///|
fn object_at(
  value : Json,
  path : String,
) -> Result[Map[String, Json], SuiteError] {
  match value {
    Object(object) => Ok(object)
    _ => Err(ExpectedObject(path))
  }
}

///|
fn array_at(value : Json, path : String) -> Result[Array[Json], SuiteError] {
  match value {
    Array(items) => Ok(items)
    _ => Err(ExpectedArray(path))
  }
}

///|
fn string_at(value : Json, path : String) -> Result[String, SuiteError] {
  match value {
    String(text) => Ok(text)
    _ => Err(ExpectedString(path))
  }
}

///|
fn integer_at(value : Json, path : String) -> Result[Int, SuiteError] {
  match value {
    Number(number, ..) => {
      let integer = number.to_int()
      if integer.to_double() == number {
        Ok(integer)
      } else {
        Err(ExpectedInteger(path))
      }
    }
    _ => Err(ExpectedInteger(path))
  }
}

///|
fn required(
  object : Map[String, Json],
  key : String,
) -> Result[Json, SuiteError] {
  match object.get(key) {
    Some(value) => Ok(value)
    None => Err(MissingField(key))
  }
}

///|
fn optional_string(
  object : Map[String, Json],
  key : String,
) -> Result[String?, SuiteError] {
  match object.get(key) {
    None => Ok(None)
    Some(value) =>
      match string_at(value, key) {
        Ok(text) => Ok(Some(text))
        Err(error) => Err(error)
      }
  }
}

///|
fn optional_integer(
  object : Map[String, Json],
  key : String,
  fallback : Int,
) -> Result[Int, SuiteError] {
  match object.get(key) {
    None => Ok(fallback)
    Some(value) => integer_at(value, key)
  }
}

///|
fn optional_integer_field(
  object : Map[String, Json],
  key : String,
) -> Result[Int?, SuiteError] {
  match object.get(key) {
    None => Ok(None)
    Some(value) =>
      match integer_at(value, key) {
        Ok(number) => Ok(Some(number))
        Err(error) => Err(error)
      }
  }
}

///|
fn decode_pairs(
  value : Json,
  path : String,
) -> Result[Array[@core.Header], SuiteError] {
  let values = match array_at(value, path) {
    Ok(items) => items
    Err(error) => return Err(error)
  }
  let pairs : Array[@core.Header] = []
  for item in values {
    let pair = match object_at(item, path + "[]") {
      Ok(object) => object
      Err(error) => return Err(error)
    }
    let name = match required(pair, "name") {
      Ok(value) =>
        match string_at(value, path + "[].name") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    let content = match required(pair, "value") {
      Ok(value) =>
        match string_at(value, path + "[].value") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    pairs.push(@core.Header::new(name, content))
  }
  Ok(pairs)
}

///|
fn decode_query(value : Json) -> Result[Array[@core.QueryParam], SuiteError] {
  let values = match array_at(value, "request.query") {
    Ok(items) => items
    Err(error) => return Err(error)
  }
  let query : Array[@core.QueryParam] = []
  for item in values {
    let pair = match object_at(item, "request.query[]") {
      Ok(object) => object
      Err(error) => return Err(error)
    }
    let name = match required(pair, "name") {
      Ok(value) =>
        match string_at(value, "request.query[].name") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    let content = match required(pair, "value") {
      Ok(value) =>
        match string_at(value, "request.query[].value") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    query.push(@core.QueryParam::new(name, content))
  }
  Ok(query)
}

///|
fn decode_request(value : Json) -> Result[@core.HttpRequest, SuiteError] {
  let request = match object_at(value, "request") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let verb = match required(request, "method") {
    Ok(value) =>
      match string_at(value, "request.method") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let path = match required(request, "path") {
    Ok(value) =>
      match string_at(value, "request.path") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let query = match request.get("query") {
    None => []
    Some(value) =>
      match decode_query(value) {
        Ok(items) => items
        Err(error) => return Err(error)
      }
  }
  let headers = match request.get("headers") {
    None => []
    Some(value) =>
      match decode_pairs(value, "request.headers") {
        Ok(items) => items
        Err(error) => return Err(error)
      }
  }
  let body = match optional_string(request, "body") {
    Ok(Some(value)) => value
    Ok(None) => ""
    Err(error) => return Err(error)
  }
  Ok(@core.HttpRequest::new(verb, path, query, headers, body))
}

///|
fn decode_step(value : Json) -> Result[Step, SuiteError] {
  let object = match object_at(value, "steps[]") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let id = match required(object, "id") {
    Ok(value) =>
      match string_at(value, "steps[].id") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if id.trim().is_empty() {
    return Err(EmptyStepId)
  }
  let request = match required(object, "request") {
    Ok(value) =>
      match decode_request(value) {
        Ok(request) => request
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let expected = match object.get("expect") {
    None => Map([])
    Some(value) =>
      match object_at(value, "steps[].expect") {
        Ok(fields) => fields
        Err(error) => return Err(error)
      }
  }
  let expected_delay_ms = match optional_integer_field(expected, "delay_ms") {
    Ok(None) => None
    Ok(Some(value)) if value >= 0 => Some(value)
    Ok(Some(_)) =>
      return Err(ExpectedInteger("expect.delay_ms (must be non-negative)"))
    Err(error) => return Err(error)
  }
  let expected_outcome = match optional_string(expected, "outcome") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match expected_outcome {
    Some("response") | Some("aborted") | None => ()
    Some(value) => return Err(InvalidOutcome(value))
  }
  Ok({
    id,
    request,
    expected_rule_id: match optional_string(expected, "rule_id") {
      Ok(value) => value
      Err(error) => return Err(error)
    },
    expected_phase_before: match optional_string(expected, "phase_before") {
      Ok(value) => value
      Err(error) => return Err(error)
    },
    expected_phase_after: match optional_string(expected, "phase_after") {
      Ok(value) => value
      Err(error) => return Err(error)
    },
    expected_outcome,
    expected_status: match optional_integer_field(expected, "status") {
      Ok(None) => None
      Ok(Some(value)) if value >= 100 && value <= 599 => Some(value)
      Ok(Some(_)) => return Err(ExpectedInteger("expect.status (100..599)"))
      Err(error) => return Err(error)
    },
    expected_body_contains: match optional_string(expected, "body_contains") {
      Ok(value) => value
      Err(error) => return Err(error)
    },
    expected_delay_ms,
  })
}

///|
/// Parse a versioned JSON suite. Each step is a full request and optional set
/// of assertions; steps run in order against one fresh scenario engine.
pub fn parse(text : String) -> Result[Suite, SuiteError] {
  let json = @json.parse(text) catch { _ => return Err(InvalidJson) }
  let root = match object_at(json, "root") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let version = match required(root, "version") {
    Ok(value) =>
      match integer_at(value, "version") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if version != 1 {
    return Err(UnsupportedVersion(version))
  }
  let upstream_status = match optional_integer(root, "upstream_status", 200) {
    Ok(status) if status >= 100 && status <= 599 => status
    Ok(status) => return Err(InvalidUpstreamStatus(status))
    Err(_) => return Err(ExpectedInteger("upstream_status"))
  }
  let values = match required(root, "steps") {
    Ok(value) =>
      match array_at(value, "steps") {
        Ok(values) => values
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if values.length() == 0 {
    return Err(EmptySuite)
  }
  if values.length() > 10_000 {
    return Err(TooManySteps(values.length()))
  }
  let steps : Array[Step] = []
  for value in values {
    let step = match decode_step(value) {
      Ok(step) => step
      Err(error) => return Err(error)
    }
    for existing in steps {
      if existing.id == step.id {
        return Err(DuplicateStepId(step.id))
      }
    }
    steps.push(step)
  }
  Ok({ version, upstream_status, steps, })
}

///|
fn add_failure(
  failures : Array[String],
  name : String,
  expected : String,
  actual : String,
) -> Unit {
  failures.push(name + " expected=" + expected + " actual=" + actual)
}

///|
fn expected_optional_string(
  failures : Array[String],
  name : String,
  expected : String?,
  actual : String?,
) -> Unit {
  match expected {
    None => ()
    Some(wanted) if actual == Some(wanted) => ()
    Some(wanted) =>
      add_failure(
        failures,
        name,
        wanted,
        match actual {
          Some(value) => value
          None => "<none>"
        },
      )
  }
}

///|
fn expected_optional_int(
  failures : Array[String],
  name : String,
  expected : Int?,
  actual : Int?,
) -> Unit {
  match expected {
    None => ()
    Some(wanted) if actual == Some(wanted) => ()
    Some(wanted) =>
      add_failure(
        failures,
        name,
        wanted.to_string(),
        match actual {
          Some(value) => value.to_string()
          None => "<none>"
        },
      )
  }
}

///|
fn render_rule_id(rule_id : String?) -> String {
  match rule_id {
    Some(value) => value
    None => "<fallback>"
  }
}

///|
fn result_for_step(
  config : @config.Config,
  suite : Suite,
  engine : @runtime.Engine,
  step : Step,
) -> StepResult {
  let validation = step.request.validate(@core.RequestLimits::safe_defaults())
  let policy_validation = config.policy.validate_request(step.request)
  match (validation, policy_validation) {
    (Err(_), _) | (_, Err(_)) =>
      {
        id: step.id,
        passed: false,
        failures: ["request_policy expected=accepted actual=rejected"],
        rule_id: None,
        phase_before: "<not-run>",
        phase_after: "<not-run>",
        outcome: "rejected",
        status: None,
        delay_ms: 0,
      }
    (Ok(_), Ok(_)) => {
      let decision = engine.decide(step.request)
      let actual_outcome = match decision.plan.source {
        @fault.ConnectionAbort(_) => "aborted"
        @fault.Fixed(_) | @fault.Upstream => "response"
      }
      let actual_response = match decision.plan.source {
        @fault.ConnectionAbort(_) => None
        @fault.Fixed(response) => Some(response)
        @fault.Upstream =>
          Some(@core.HttpResponse::new(suite.upstream_status, [], ""))
      }
      let filtered = match actual_response {
        Some(response) =>
          Some(
            config.policy.filter_response(
              decision.plan.transform_response(response),
            ),
          )
        None => None
      }
      let actual_status = match filtered {
        Some(response) => Some(response.status)
        None => None
      }
      let actual_body = match filtered {
        Some(response) => Some(response.body)
        None => None
      }
      let failures : Array[String] = []
      expected_optional_string(
        failures,
        "rule_id",
        step.expected_rule_id,
        decision.rule_id,
      )
      expected_optional_string(
        failures,
        "phase_before",
        step.expected_phase_before,
        Some(decision.phase_before),
      )
      expected_optional_string(
        failures,
        "phase_after",
        step.expected_phase_after,
        Some(decision.phase_after),
      )
      expected_optional_string(
        failures,
        "outcome",
        step.expected_outcome,
        Some(actual_outcome),
      )
      expected_optional_int(
        failures,
        "status",
        step.expected_status,
        actual_status,
      )
      expected_optional_int(
        failures,
        "delay_ms",
        step.expected_delay_ms,
        Some(decision.plan.delay_ms),
      )
      match step.expected_body_contains {
        None => ()
        Some(needle) =>
          match actual_body {
            Some(body) if body.contains(needle) => ()
            Some(_) =>
              add_failure(failures, "body_contains", needle, "<not-present>")
            None => add_failure(failures, "body_contains", needle, "<no-body>")
          }
      }
      {
        id: step.id,
        passed: failures.length() == 0,
        failures,
        rule_id: decision.rule_id,
        phase_before: decision.phase_before,
        phase_after: decision.phase_after,
        outcome: actual_outcome,
        status: actual_status,
        delay_ms: decision.plan.delay_ms,
      }
    }
  }
}

///|
/// Run every suite step against one fresh engine. No sockets or wall clock are
/// used, so the same configuration and suite always produce the same report.
pub fn run(config : @config.Config, suite : Suite) -> Report {
  let engine = @runtime.Engine::new(config)
  let results : Array[StepResult] = []
  let mut passed = 0
  let mut failed = 0
  for step in suite.steps {
    let result = result_for_step(config, suite, engine, step)
    if result.passed {
      passed = passed + 1
    } else {
      failed = failed + 1
    }
    results.push(result)
  }
  { passed, failed, steps: results, }
}

///|
fn nullable_string(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn nullable_integer(value : Int?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
pub fn Report::succeeded(self : Report) -> Bool {
  self.failed == 0
}

///|
pub fn Report::to_json(self : Report) -> String {
  let values : Array[Json] = []
  for step in self.steps {
    let failures : Array[Json] = []
    for failure in step.failures {
      failures.push(Json::string(failure))
    }
    values.push(
      Json::object({
        "id": Json::string(step.id),
        "passed": @json.to_json(step.passed),
        "failures": Json::array(failures),
        "rule_id": nullable_string(step.rule_id),
        "phase_before": Json::string(step.phase_before),
        "phase_after": Json::string(step.phase_after),
        "outcome": Json::string(step.outcome),
        "status": nullable_integer(step.status),
        "delay_ms": Json::number(step.delay_ms.to_double()),
      }),
    )
  }
  Json::object({
    "passed": Json::number(self.passed.to_double()),
    "failed": Json::number(self.failed.to_double()),
    "success": @json.to_json(self.succeeded()),
    "steps": Json::array(values),
  }).stringify()
}

///|
pub fn Report::to_text(self : Report) -> String {
  let lines : Array[String] = []
  lines.push(
    "verify: " +
    (if self.succeeded() { "PASS" } else { "FAIL" }) +
    " passed=" +
    self.passed.to_string() +
    " failed=" +
    self.failed.to_string(),
  )
  for step in self.steps {
    let status_text = match step.status {
      Some(status) => status.to_string()
      None => "<none>"
    }
    lines.push(
      "[" +
      (if step.passed { "PASS" } else { "FAIL" }) +
      "] " +
      step.id +
      " rule=" +
      render_rule_id(step.rule_id) +
      " phase=" +
      step.phase_before +
      "->" +
      step.phase_after +
      " outcome=" +
      step.outcome +
      " status=" +
      status_text +
      " delay_ms=" +
      step.delay_ms.to_string(),
    )
    for failure in step.failures {
      lines.push("  - " + failure)
    }
  }
  lines.join("\n")
}
