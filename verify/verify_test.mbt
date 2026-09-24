///|
fn payment_config() -> @config.Config {
  @config.parse(
    (
      #|{
      #|  "version":1,
      #|  "upstream":"http://127.0.0.1:9000",
      #|  "session_header":"X-Checkout-Id",
      #|  "initial_phase":"degraded",
      #|  "transitions":[{"from":"degraded","to":"healthy","on_hit":2}],
      #|  "rules":[
      #|    {"id":"fail","phase":"degraded","match":{"method":"POST","path":"/payments"},"actions":[{"type":"delay","ms":25},{"type":"stub","status":503,"body":"temporary_unavailable"}]},
      #|    {"id":"recover","phase":"healthy","match":{"method":"POST","path":"/payments"},"actions":[{"type":"passthrough"}]}
      #|  ]
      #|}
    ),
  ).unwrap()
}

///|
let valid_suite =
  #|{
  #|  "version":1,
  #|  "steps":[
  #|    {"id":"first","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"order-a"}]},"expect":{"rule_id":"fail","phase_before":"degraded","phase_after":"degraded","outcome":"response","status":503,"body_contains":"temporary","delay_ms":25}},
  #|    {"id":"second","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"order-a"}]},"expect":{"rule_id":"fail","phase_before":"degraded","phase_after":"healthy","status":503}},
  #|    {"id":"recovered","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"order-a"}]},"expect":{"rule_id":"recover","phase_before":"healthy","phase_after":"healthy","status":200}}
  #|  ]
  #|}

///|
test "parses and replays a stateful acceptance suite deterministically" {
  let suite = @verify.parse(valid_suite).unwrap()
  let first = @verify.run(payment_config(), suite)
  let second = @verify.run(payment_config(), suite)
  assert_eq(first, second)
  assert_eq(first.passed, 3)
  assert_eq(first.failed, 0)
  assert_true(first.succeeded())
  assert_eq(first.steps[1].phase_after, "healthy")
  assert_eq(first.steps[2].status, Some(200))
  assert_true(first.to_text().contains("verify: PASS passed=3 failed=0"))
  assert_true(first.to_json().contains("\"success\":true"))
}

///|
test "keeps scenario state isolated by the configured session header" {
  let suite = @verify.parse(
    (
      #|{"version":1,"steps":[
      #|{"id":"a1","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"a"}]},"expect":{"phase_after":"degraded"}},
      #|{"id":"b1","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"b"}]},"expect":{"phase_before":"degraded","phase_after":"degraded"}},
      #|{"id":"a2","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"a"}]},"expect":{"phase_after":"healthy"}},
      #|{"id":"b2","request":{"method":"POST","path":"/payments","headers":[{"name":"X-Checkout-Id","value":"b"}]},"expect":{"phase_after":"healthy"}}]}
    ),
  ).unwrap()
  let report = @verify.run(payment_config(), suite)
  assert_eq(report.failed, 0)
  assert_eq(report.steps[1].phase_before, "degraded")
  assert_eq(report.steps[3].phase_after, "healthy")
}

///|
test "reports assertion mismatches without exposing response bodies" {
  let suite = @verify.parse(
    (
      #|{"version":1,"steps":[{"id":"wrong-status","request":{"method":"POST","path":"/payments"},"expect":{"status":200,"body_contains":"missing"}}]}
    ),
  ).unwrap()
  let report = @verify.run(payment_config(), suite)
  assert_eq(report.passed, 0)
  assert_eq(report.failed, 1)
  assert_true(report.to_text().contains("status expected=200 actual=503"))
  assert_true(
    report
    .to_text()
    .contains("body_contains expected=missing actual=<not-present>"),
  )
  assert_false(report.to_json().contains("temporary_unavailable"))
}

///|
test "rejects malformed suites, duplicate ids and invalid statuses" {
  assert_eq(@verify.parse("{"), Err(InvalidJson))
  assert_eq(
    @verify.parse("{\"version\":2,\"steps\":[{}]}"),
    Err(UnsupportedVersion(2)),
  )
  assert_eq(@verify.parse("{\"version\":1,\"steps\":[]}"), Err(EmptySuite))
  assert_eq(
    @verify.parse("{\"version\":1,\"upstream_status\":99,\"steps\":[{}]}"),
    Err(InvalidUpstreamStatus(99)),
  )
  assert_eq(
    @verify.parse(
      "{\"version\":1,\"steps\":[{\"id\":\"same\",\"request\":{\"method\":\"GET\",\"path\":\"/\"}},{\"id\":\"same\",\"request\":{\"method\":\"GET\",\"path\":\"/\"}}]}",
    ),
    Err(DuplicateStepId("same")),
  )
}

///|
test "rejects invalid expected status and negative delay assertion" {
  assert_eq(
    @verify.parse(
      "{\"version\":1,\"steps\":[{\"id\":\"bad\",\"request\":{\"method\":\"GET\",\"path\":\"/\"},\"expect\":{\"status\":700}}]}",
    ),
    Err(ExpectedInteger("expect.status (100..599)")),
  )
  assert_eq(
    @verify.parse(
      "{\"version\":1,\"steps\":[{\"id\":\"bad\",\"request\":{\"method\":\"GET\",\"path\":\"/\"},\"expect\":{\"delay_ms\":-1}}]}",
    ),
    Err(ExpectedInteger("expect.delay_ms (must be non-negative)")),
  )
}

///|
test "rejects unknown outcome assertions before replay" {
  assert_eq(
    @verify.parse(
      "{\"version\":1,\"steps\":[{\"id\":\"bad\",\"request\":{\"method\":\"GET\",\"path\":\"/\"},\"expect\":{\"outcome\":\"timeout\"}}]}",
    ),
    Err(InvalidOutcome("timeout")),
  )
}
