///|
fn event(
  sequence : Int,
  session : String,
  outcome : @report.Outcome,
  elapsed_ms : Int,
) -> @report.Event {
  {
    sequence,
    decision: @runtime.Decision::fallback(session, "phase"),
    outcome,
    elapsed_ms,
  }
}

///|
fn event_with_rule(
  sequence : Int,
  rule_id : String,
  session : String,
  outcome : @report.Outcome,
  elapsed_ms : Int,
) -> @report.Event {
  {
    sequence,
    decision: {
      session,
      phase_before: "phase",
      phase_after: "phase",
      rule_id: Some(rule_id),
      plan: @runtime.Decision::fallback(session, "phase").plan,
    },
    outcome,
    elapsed_ms,
  }
}

///|
test "summarizes outcomes and latency percentiles" {
  let events = [
    event_with_rule(1, "retry", "a", @report.Response(503), 10),
    event_with_rule(2, "retry", "a", @report.Aborted("reset"), 20),
    event_with_rule(3, "forward", "a", @report.Response(200), 30),
    event_with_rule(4, "forward", "b", @report.UpstreamFailure("timeout"), 40),
  ]
  let stats = @observe.summarize(
    events,
    @observe.EventFilter::for_rule("retry"),
  )
  assert_eq(stats.total, 2)
  assert_eq(stats.responses, 1)
  assert_eq(stats.aborted, 1)
  assert_eq(stats.average_elapsed_ms, 15)
  assert_eq(stats.p50_elapsed_ms, 10)
  assert_eq(stats.p95_elapsed_ms, 20)
  assert_eq(stats.failure_rate_percent(), 50)
}

///|
test "filters by session outcome and minimum latency" {
  let events = [
    event(1, "a", @report.Response(200), 4),
    event(2, "a", @report.UpstreamFailure("timeout"), 40),
    event(3, "b", @report.Aborted("reset"), 80),
  ]
  let filter = @observe.EventFilter::for_session("a")
    .with_outcome("upstream_failure")
    .with_min_elapsed(10)
  let selected = @observe.select(events, filter, 10)
  assert_eq(selected.length(), 1)
  assert_eq(selected[0].elapsed_ms, 40)
}

///|
test "selection is bounded and empty summaries are stable" {
  let events = [
    event(1, "a", @report.Response(200), 1),
    event(2, "a", @report.Response(200), 2),
  ]
  assert_eq(@observe.select(events, @observe.EventFilter::any(), 1).length(), 1)
  let empty = @observe.summarize(
    events,
    @observe.EventFilter::for_rule("missing"),
  )
  assert_eq(
    empty.to_text(),
    "total=0 responses=0 aborted=0 upstream_failures=0 failure_rate_percent=0 avg_ms=0 p50_ms=0 p95_ms=0 max_ms=0",
  )
  assert_eq(
    empty.to_json(),
    "{\"total\":0,\"responses\":0,\"aborted\":0,\"upstream_failures\":0,\"failure_rate_percent\":0,\"total_elapsed_ms\":0,\"average_elapsed_ms\":0,\"p50_elapsed_ms\":0,\"p95_elapsed_ms\":0,\"max_elapsed_ms\":0}",
  )
}
