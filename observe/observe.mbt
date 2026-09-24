///|
pub(all) struct EventFilter {
  rule_id : String?
  session : String?
  outcome : String?
  min_elapsed_ms : Int?
} derive(Debug, Eq)

///|
pub extend EventFilter with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EventFilter with Eq::{not_equal, equal}

///|
pub fn EventFilter::any() -> EventFilter {
  { rule_id: None, session: None, outcome: None, min_elapsed_ms: None, }
}

///|
pub fn EventFilter::for_rule(rule_id : String) -> EventFilter {
  {
    rule_id: Some(rule_id),
    session: None,
    outcome: None,
    min_elapsed_ms: None,
  }
}

///|
pub fn EventFilter::for_session(session : String) -> EventFilter {
  {
    rule_id: None,
    session: Some(session),
    outcome: None,
    min_elapsed_ms: None,
  }
}

///|
pub fn EventFilter::with_outcome(
  self : EventFilter,
  outcome : String,
) -> EventFilter {
  {
    rule_id: self.rule_id,
    session: self.session,
    outcome: Some(outcome),
    min_elapsed_ms: self.min_elapsed_ms,
  }
}

///|
pub fn EventFilter::with_min_elapsed(
  self : EventFilter,
  elapsed_ms : Int,
) -> EventFilter {
  {
    rule_id: self.rule_id,
    session: self.session,
    outcome: self.outcome,
    min_elapsed_ms: Some(elapsed_ms),
  }
}

///|
pub(all) struct Stats {
  total : Int
  responses : Int
  aborted : Int
  upstream_failures : Int
  total_elapsed_ms : Int
  average_elapsed_ms : Int
  max_elapsed_ms : Int
  p50_elapsed_ms : Int
  p95_elapsed_ms : Int
} derive(Debug, Eq)

///|
pub extend Stats with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Stats with Eq::{not_equal, equal}

///|
fn outcome_name(outcome : @report.Outcome) -> String {
  match outcome {
    @report.Response(_) => "response"
    @report.Aborted(_) => "aborted"
    @report.UpstreamFailure(_) => "upstream_failure"
  }
}

///|
fn EventFilter::matches(self : EventFilter, event : @report.Event) -> Bool {
  let rule_matches = match self.rule_id {
    None => true
    Some(wanted) => event.decision.rule_id == Some(wanted)
  }
  let session_matches = match self.session {
    None => true
    Some(wanted) => event.decision.session == wanted
  }
  let outcome_matches = match self.outcome {
    None => true
    Some(wanted) => outcome_name(event.outcome) == wanted
  }
  let elapsed_matches = match self.min_elapsed_ms {
    None => true
    Some(minimum) => event.elapsed_ms >= minimum
  }
  rule_matches && session_matches && outcome_matches && elapsed_matches
}

///|
pub fn select(
  events : Array[@report.Event],
  filter : EventFilter,
  limit : Int,
) -> Array[@report.Event] {
  let result : Array[@report.Event] = []
  if limit <= 0 {
    return result
  }
  for event in events {
    if result.length() < limit && filter.matches(event) {
      result.push(event)
    }
  }
  result
}

///|
fn percentile(values : Array[Int], percentage : Int) -> Int {
  if values.length() == 0 {
    return 0
  }
  let sorted = values.copy()
  sorted.sort()
  let rank = (sorted.length() * percentage + 99) / 100
  let index = (rank - 1).clamp(min=0, max=sorted.length() - 1)
  sorted[index]
}

///|
pub fn summarize(events : Array[@report.Event], filter : EventFilter) -> Stats {
  let latencies : Array[Int] = []
  let mut responses = 0
  let mut aborted = 0
  let mut upstream_failures = 0
  let mut total_elapsed_ms = 0
  let mut max_elapsed_ms = 0
  for event in events {
    if filter.matches(event) {
      latencies.push(event.elapsed_ms)
      total_elapsed_ms = total_elapsed_ms + event.elapsed_ms
      if event.elapsed_ms > max_elapsed_ms {
        max_elapsed_ms = event.elapsed_ms
      }
      match event.outcome {
        @report.Response(_) => responses = responses + 1
        @report.Aborted(_) => aborted = aborted + 1
        @report.UpstreamFailure(_) => upstream_failures = upstream_failures + 1
      }
    }
  }
  let total = latencies.length()
  {
    total,
    responses,
    aborted,
    upstream_failures,
    total_elapsed_ms,
    average_elapsed_ms: if total == 0 {
      0
    } else {
      total_elapsed_ms / total
    },
    max_elapsed_ms,
    p50_elapsed_ms: percentile(latencies, 50),
    p95_elapsed_ms: percentile(latencies, 95),
  }
}

///|
pub fn Stats::failure_count(self : Stats) -> Int {
  self.aborted + self.upstream_failures
}

///|
pub fn Stats::failure_rate_percent(self : Stats) -> Int {
  if self.total == 0 {
    0
  } else {
    self.failure_count() * 100 / self.total
  }
}

///|
pub fn Stats::to_text(self : Stats) -> String {
  "total=" +
  self.total.to_string() +
  " responses=" +
  self.responses.to_string() +
  " aborted=" +
  self.aborted.to_string() +
  " upstream_failures=" +
  self.upstream_failures.to_string() +
  " failure_rate_percent=" +
  self.failure_rate_percent().to_string() +
  " avg_ms=" +
  self.average_elapsed_ms.to_string() +
  " p50_ms=" +
  self.p50_elapsed_ms.to_string() +
  " p95_ms=" +
  self.p95_elapsed_ms.to_string() +
  " max_ms=" +
  self.max_elapsed_ms.to_string()
}

///|
pub fn Stats::to_json(self : Stats) -> String {
  "{\"total\":" +
  self.total.to_string() +
  ",\"responses\":" +
  self.responses.to_string() +
  ",\"aborted\":" +
  self.aborted.to_string() +
  ",\"upstream_failures\":" +
  self.upstream_failures.to_string() +
  ",\"failure_rate_percent\":" +
  self.failure_rate_percent().to_string() +
  ",\"total_elapsed_ms\":" +
  self.total_elapsed_ms.to_string() +
  ",\"average_elapsed_ms\":" +
  self.average_elapsed_ms.to_string() +
  ",\"p50_elapsed_ms\":" +
  self.p50_elapsed_ms.to_string() +
  ",\"p95_elapsed_ms\":" +
  self.p95_elapsed_ms.to_string() +
  ",\"max_elapsed_ms\":" +
  self.max_elapsed_ms.to_string() +
  "}"
}
