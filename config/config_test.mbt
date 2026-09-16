///|
let complete_config =
  #|{
  #|  "version": 1,
  #|  "upstream": "http://127.0.0.1:9000",
  #|  "session_header": "X-Checkout-Id",
  #|  "initial_phase": "degraded",
  #|  "transitions": [{"from":"degraded","to":"healthy","on_hit":2}],
  #|  "rules": [{
  #|    "id":"first-two-retries",
  #|    "priority": 10,
  #|    "phase":"degraded",
  #|    "match":{"method":"POST","path":"/payments"},
  #|    "actions":[{"type":"delay","ms":25},{"type":"stub","status":503,"body":"retry"}]
  #|  }]
  #|}

///|
test "decodes a versioned stateful service-virtualization configuration" {
  let config = parse(complete_config).unwrap()
  assert_eq(config.listen, "127.0.0.1:8080")
  assert_eq(config.initial_phase, "degraded")
  assert_eq(config.transitions.length(), 1)
  assert_eq(config.rules[0].candidate.id, "first-two-retries")
  assert_eq(config.rules[0].candidate.pattern.verb, Some("POST"))
  assert_eq(config.rules[0].actions, [
    @fault.Delay(25),
    @fault.Stub(@core.HttpResponse::new(503, [], "retry")),
  ])
  assert_eq(config.policy.max_events(), 1000)
}

///|
test "rejects invalid JSON versions and duplicate rule identifiers" {
  assert_eq(parse("{"), Err(InvalidJson))
  assert_eq(
    parse("{\"version\":2,\"upstream\":\"http://127.0.0.1\",\"rules\":[]}"),
    Err(UnsupportedVersion(2)),
  )
  assert_eq(
    parse(
      (
        #|{"version":1,"upstream":"http://127.0.0.1","rules":[
        #|{"id":"same","actions":[]},{"id":"same","actions":[]}]}
      ),
    ),
    Err(DuplicateRuleId("same")),
  )
}

///|
test "rejects unsupported upstream schemes and invalid action plans" {
  assert_eq(
    parse("{\"version\":1,\"upstream\":\"https://example.test\",\"rules\":[]}"),
    Err(InvalidUpstream("https://example.test")),
  )
  match
    parse(
      (
        #|{"version":1,"upstream":"http://127.0.0.1","rules":[
        #|{"id":"broken","actions":[{"type":"abort","reason":"x"},{"type":"corrupt","suffix":"!"}]}]}
      ),
    ) {
    Err(InvalidAction(_)) => ()
    _ => fail("conflicting actions must be rejected")
  }
}

///|
test "decodes custom limits and rejects public listeners" {
  let config = parse(
    (
      #|{"version":1,"upstream":"http://127.0.0.1","limits":{"max_headers":4,"max_request_body_chars":64,"max_response_body_chars":32,"max_events":9},"security":{"redact_headers":["X-Customer-Secret"]},"rules":[]}
    ),
  ).unwrap()
  assert_eq(config.policy.max_headers(), 4)
  assert_eq(config.policy.max_response_body_chars(), 32)
  assert_eq(
    config.policy.header_disposition("X-Customer-Secret"),
    @policy.Redact,
  )
  match
    parse(
      (
        #|{"version":1,"listen":"0.0.0.0:8080","upstream":"http://127.0.0.1","rules":[]}
      ),
    ) {
    Err(InvalidPolicy(_)) => ()
    _ => fail("public listeners must be rejected by default")
  }
}
