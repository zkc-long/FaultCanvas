///|
pub(all) struct ConfiguredRule {
  candidate : @matcher.RuleCandidate
  phase : String?
  actions : Array[@fault.FaultAction]
} derive(Debug, Eq)

///|
pub(all) struct Config {
  version : Int
  listen : String
  upstream : String
  session_header : String?
  initial_phase : String
  transitions : Array[@scenario.Transition]
  rules : Array[ConfiguredRule]
  policy : @policy.Policy
} derive(Debug, Eq)

///|
pub(all) enum ConfigError {
  InvalidJson
  ExpectedObject(String)
  ExpectedArray(String)
  ExpectedString(String)
  ExpectedInteger(String)
  MissingField(String)
  UnsupportedVersion(Int)
  InvalidUpstream(String)
  EmptyRuleId
  DuplicateRuleId(String)
  InvalidAction(String)
  InvalidTransition(String)
  InvalidPolicy(String)
} derive(Debug, Eq)

///|
fn object_at(
  value : Json,
  path : String,
) -> Result[Map[String, Json], ConfigError] {
  match value {
    Object(object) => Ok(object)
    _ => Err(ExpectedObject(path))
  }
}

///|
fn array_at(value : Json, path : String) -> Result[Array[Json], ConfigError] {
  match value {
    Array(items) => Ok(items)
    _ => Err(ExpectedArray(path))
  }
}

///|
fn string_at(value : Json, path : String) -> Result[String, ConfigError] {
  match value {
    String(text) => Ok(text)
    _ => Err(ExpectedString(path))
  }
}

///|
fn integer_at(value : Json, path : String) -> Result[Int, ConfigError] {
  match value {
    Number(number, ..) => {
      let value = number.to_int()
      if value.to_double() == number {
        Ok(value)
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
) -> Result[Json, ConfigError] {
  match object.get(key) {
    Some(value) => Ok(value)
    None => Err(MissingField(key))
  }
}

///|
fn optional_string(
  object : Map[String, Json],
  key : String,
) -> Result[String?, ConfigError] {
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
) -> Result[Int, ConfigError] {
  match object.get(key) {
    None => Ok(fallback)
    Some(value) => integer_at(value, key)
  }
}

///|
fn decode_redaction_headers(value : Json) -> Result[Array[String], ConfigError] {
  let values = match array_at(value, "security.redact_headers") {
    Ok(values) => values
    Err(error) => return Err(error)
  }
  let headers : Array[String] = []
  for item in values {
    match string_at(item, "security.redact_headers[]") {
      Ok(value) => headers.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(headers)
}

///|
fn decode_policy(
  root : Map[String, Json],
  listen : String,
) -> Result[@policy.Policy, ConfigError] {
  let defaults = @policy.Policy::safe_defaults()
  let empty_limits : Map[String, Json] = Map([])
  let limits = match root.get("limits") {
    None => empty_limits
    Some(value) =>
      match object_at(value, "limits") {
        Ok(object) => object
        Err(error) => return Err(error)
      }
  }
  let max_headers = match
    optional_integer(limits, "max_headers", defaults.max_headers()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_request_body_chars = match
    optional_integer(
      limits,
      "max_request_body_chars",
      defaults.max_request_body_chars(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_response_body_chars = match
    optional_integer(
      limits,
      "max_response_body_chars",
      defaults.max_response_body_chars(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_events = match
    optional_integer(limits, "max_events", defaults.max_events()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let redact_headers = match root.get("security") {
    None => defaults.redact_headers
    Some(value) => {
      let security = match object_at(value, "security") {
        Ok(object) => object
        Err(error) => return Err(error)
      }
      match security.get("redact_headers") {
        None => defaults.redact_headers
        Some(value) =>
          match decode_redaction_headers(value) {
            Ok(headers) => headers
            Err(error) => return Err(error)
          }
      }
    }
  }
  let policy = match
    @policy.Policy::new(
      max_headers, max_request_body_chars, max_response_body_chars, max_events, redact_headers,
    ) {
    Ok(policy) => policy
    Err(_) => return Err(InvalidPolicy("limits or security are invalid"))
  }
  match policy.listen_is_safe(listen) {
    Ok(_) => Ok(policy)
    Err(_) => Err(InvalidPolicy("listen must be loopback"))
  }
}

///|
fn decode_fields(
  value : Json,
  path : String,
) -> Result[Array[@matcher.FieldPattern], ConfigError] {
  let items = match array_at(value, path) {
    Ok(items) => items
    Err(error) => return Err(error)
  }
  let fields : Array[@matcher.FieldPattern] = []
  for item in items {
    let object = match object_at(item, path) {
      Ok(object) => object
      Err(error) => return Err(error)
    }
    let name = match required(object, "name") {
      Ok(value) =>
        match string_at(value, path + ".name") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    let field_value = match required(object, "value") {
      Ok(value) =>
        match string_at(value, path + ".value") {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
    fields.push(@matcher.FieldPattern::new(name, field_value))
  }
  Ok(fields)
}

///|
fn decode_pattern(
  object : Map[String, Json],
) -> Result[@matcher.RequestPattern, ConfigError] {
  let verb = match optional_string(object, "method") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let exact = match optional_string(object, "path") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let prefix = match optional_string(object, "path_prefix") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if exact is Some(_) && prefix is Some(_) {
    return Err(InvalidAction("match.path and match.path_prefix are exclusive"))
  }
  let path = match (exact, prefix) {
    (Some(value), None) => Some(@matcher.Exact(value))
    (None, Some(value)) => Some(@matcher.Prefix(value))
    _ => None
  }
  let query = match object.get("query") {
    None => []
    Some(value) =>
      match decode_fields(value, "match.query") {
        Ok(fields) => fields
        Err(error) => return Err(error)
      }
  }
  let headers = match object.get("headers") {
    None => []
    Some(value) =>
      match decode_fields(value, "match.headers") {
        Ok(fields) => fields
        Err(error) => return Err(error)
      }
  }
  let body_contains = match optional_string(object, "body_contains") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(@matcher.RequestPattern::new(verb, path, query, headers, body_contains))
}

///|
fn decode_action(value : Json) -> Result[@fault.FaultAction, ConfigError] {
  let object = match object_at(value, "action") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let kind = match required(object, "type") {
    Ok(value) =>
      match string_at(value, "action.type") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  match kind {
    "passthrough" => Ok(@fault.PassThrough)
    "delay" =>
      match required(object, "ms") {
        Ok(value) =>
          match integer_at(value, "action.ms") {
            Ok(ms) => Ok(@fault.Delay(ms))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    "abort" =>
      match required(object, "reason") {
        Ok(value) =>
          match string_at(value, "action.reason") {
            Ok(reason) => Ok(@fault.Abort(reason))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    "status" =>
      match required(object, "code") {
        Ok(value) =>
          match integer_at(value, "action.code") {
            Ok(code) => Ok(@fault.OverrideStatus(code))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    "truncate" =>
      match required(object, "chars") {
        Ok(value) =>
          match integer_at(value, "action.chars") {
            Ok(chars) => Ok(@fault.Truncate(chars))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    "corrupt" =>
      match required(object, "suffix") {
        Ok(value) =>
          match string_at(value, "action.suffix") {
            Ok(suffix) => Ok(@fault.Corrupt(suffix))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    "stub" => {
      let status = match required(object, "status") {
        Ok(value) =>
          match integer_at(value, "action.status") {
            Ok(code) => code
            Err(error) => return Err(error)
          }
        Err(error) => return Err(error)
      }
      let body = match optional_string(object, "body") {
        Ok(Some(value)) => value
        Ok(None) => ""
        Err(error) => return Err(error)
      }
      Ok(@fault.Stub(@core.HttpResponse::new(status, [], body)))
    }
    _ => Err(InvalidAction(kind))
  }
}

///|
fn decode_rule(value : Json) -> Result[ConfiguredRule, ConfigError] {
  let object = match object_at(value, "rule") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let id = match required(object, "id") {
    Ok(value) =>
      match string_at(value, "rule.id") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if id.trim().is_empty() {
    return Err(EmptyRuleId)
  }
  let priority = match optional_integer(object, "priority", 0) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let phase = match optional_string(object, "phase") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pattern = match object.get("match") {
    None => @matcher.RequestPattern::new(None, None, [], [], None)
    Some(value) =>
      match object_at(value, "rule.match") {
        Ok(match_object) =>
          match decode_pattern(match_object) {
            Ok(pattern) => pattern
            Err(error) => return Err(error)
          }
        Err(error) => return Err(error)
      }
  }
  let action_values = match required(object, "actions") {
    Ok(value) =>
      match array_at(value, "rule.actions") {
        Ok(values) => values
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let actions : Array[@fault.FaultAction] = []
  for action_value in action_values {
    match decode_action(action_value) {
      Ok(action) => actions.push(action)
      Err(error) => return Err(error)
    }
  }
  match @fault.build(actions) {
    Ok(_) =>
      Ok({
        candidate: @matcher.RuleCandidate::new(id, priority, pattern),
        phase,
        actions,
      })
    Err(_) => Err(InvalidAction("fault action combination is invalid"))
  }
}

///|
fn decode_transition(value : Json) -> Result[@scenario.Transition, ConfigError] {
  let object = match object_at(value, "transition") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let from = match required(object, "from") {
    Ok(value) =>
      match string_at(value, "transition.from") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let to = match required(object, "to") {
    Ok(value) =>
      match string_at(value, "transition.to") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let condition = match optional_integer(object, "on_hit", 1) {
    Ok(value) => @scenario.OnHit(value)
    Err(error) => return Err(error)
  }
  let transition = @scenario.Transition::new(from, to, condition)
  match transition.validate() {
    Ok(_) => Ok(transition)
    Err(_) => Err(InvalidTransition("transition is invalid"))
  }
}

///|
/// Decode schema version 1. It validates every rule's fault composition at
/// load time so a bad scenario never produces a partially running proxy.
pub fn parse(text : String) -> Result[Config, ConfigError] {
  let json = @json.parse(text) catch { _ => return Err(InvalidJson) }
  let root = match object_at(json, "root") {
    Ok(object) => object
    Err(error) => return Err(error)
  }
  let version = match required(root, "version") {
    Ok(value) =>
      match integer_at(value, "version") {
        Ok(version) => version
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if version != 1 {
    return Err(UnsupportedVersion(version))
  }
  let upstream = match required(root, "upstream") {
    Ok(value) =>
      match string_at(value, "upstream") {
        Ok(text) => text
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  if !upstream.has_prefix("http://") {
    return Err(InvalidUpstream(upstream))
  }
  let listen = match optional_string(root, "listen") {
    Ok(Some(value)) => value
    Ok(None) => "127.0.0.1:8080"
    Err(error) => return Err(error)
  }
  let session_header = match optional_string(root, "session_header") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let initial_phase = match optional_string(root, "initial_phase") {
    Ok(Some(value)) if !value.trim().is_empty() => value
    Ok(Some(_)) =>
      return Err(InvalidTransition("initial_phase must not be empty"))
    Ok(None) => "default"
    Err(error) => return Err(error)
  }
  let policy = match decode_policy(root, listen) {
    Ok(policy) => policy
    Err(error) => return Err(error)
  }
  let transition_values = match root.get("transitions") {
    None => []
    Some(value) =>
      match array_at(value, "transitions") {
        Ok(items) => items
        Err(error) => return Err(error)
      }
  }
  let transitions : Array[@scenario.Transition] = []
  for value in transition_values {
    match decode_transition(value) {
      Ok(transition) => transitions.push(transition)
      Err(error) => return Err(error)
    }
  }
  let rule_values = match required(root, "rules") {
    Ok(value) =>
      match array_at(value, "rules") {
        Ok(items) => items
        Err(error) => return Err(error)
      }
    Err(error) => return Err(error)
  }
  let rules : Array[ConfiguredRule] = []
  for value in rule_values {
    let rule = match decode_rule(value) {
      Ok(rule) => rule
      Err(error) => return Err(error)
    }
    for existing in rules {
      if existing.candidate.id == rule.candidate.id {
        return Err(DuplicateRuleId(rule.candidate.id))
      }
    }
    rules.push(rule)
  }
  Ok({
    version,
    listen,
    upstream,
    session_header,
    initial_phase,
    transitions,
    rules,
    policy,
  })
}

///|
pub extend ConfiguredRule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfiguredRule with Eq::{not_equal, equal}

///|
pub extend Config with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Config with Eq::{not_equal, equal}

///|
pub extend ConfigError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigError with Eq::{not_equal, equal}
