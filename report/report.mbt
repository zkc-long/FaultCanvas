///|
pub(all) enum Outcome {
  Response(Int)
  Aborted(String)
  UpstreamFailure(String)
} derive(Debug, Eq)

///|
pub(all) struct Event {
  sequence : Int
  decision : @runtime.Decision
  outcome : Outcome
  elapsed_ms : Int
} derive(Debug, Eq)

///|
pub struct Journal {
  capacity : Int
  mut next_sequence : Int
  entries : Array[Event]
}

///|
pub fn Journal::new(capacity : Int) -> Journal {
  if capacity < 1 {
    panic()
  }
  { capacity, next_sequence: 1, entries: [], }
}

///|
pub fn Journal::record(
  self : Journal,
  decision : @runtime.Decision,
  outcome : Outcome,
  elapsed_ms : Int,
) -> Unit {
  if self.entries.length() == self.capacity {
    ignore(self.entries.remove(0))
  }
  self.entries.push({
    sequence: self.next_sequence,
    decision,
    outcome,
    elapsed_ms,
  })
  self.next_sequence = self.next_sequence + 1
}

///|
pub fn Journal::events(self : Journal) -> Array[Event] {
  self.entries.copy()
}

///|
fn outcome_text(outcome : Outcome) -> String {
  match outcome {
    Response(status) => "response:" + status.to_string()
    Aborted(reason) => "aborted:" + reason
    UpstreamFailure(reason) => "upstream_failure:" + reason
  }
}

///|
fn rule_text(rule_id : String?) -> String {
  match rule_id {
    Some(value) => value
    None => "<fallback>"
  }
}

///|
/// Stable newline-delimited text intended for terminals, CI logs and demos.
pub fn Journal::to_text(self : Journal) -> String {
  let lines : Array[String] = []
  for event in self.entries {
    lines.push(
      "#" +
      event.sequence.to_string() +
      " session=" +
      event.decision.session +
      " rule=" +
      rule_text(event.decision.rule_id) +
      " phase=" +
      event.decision.phase_before +
      "->" +
      event.decision.phase_after +
      " outcome=" +
      outcome_text(event.outcome) +
      " elapsed_ms=" +
      event.elapsed_ms.to_string(),
    )
  }
  lines.join("\n")
}

///|
fn outcome_json(outcome : Outcome) -> Json {
  match outcome {
    Response(status) =>
      Json::object({
        "kind": Json::string("response"),
        "status": Json::number(status.to_double()),
      })
    Aborted(reason) =>
      Json::object({
        "kind": Json::string("aborted"),
        "reason": Json::string(reason),
      })
    UpstreamFailure(reason) =>
      Json::object({
        "kind": Json::string("upstream_failure"),
        "reason": Json::string(reason),
      })
  }
}

///|
/// Machine-readable report with deterministic event ordering.
pub fn Journal::to_json(self : Journal) -> String {
  let events : Array[Json] = []
  for event in self.entries {
    events.push(
      Json::object({
        "sequence": Json::number(event.sequence.to_double()),
        "session": Json::string(event.decision.session),
        "phase_before": Json::string(event.decision.phase_before),
        "phase_after": Json::string(event.decision.phase_after),
        "rule_id": match event.decision.rule_id {
          Some(value) => Json::string(value)
          None => Json::null()
        },
        "elapsed_ms": Json::number(event.elapsed_ms.to_double()),
        "outcome": outcome_json(event.outcome),
      }),
    )
  }
  Json::object({ "events": Json::array(events) }).stringify()
}
