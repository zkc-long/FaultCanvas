///|
fn retry_config() -> @config.Config {
  @config.parse(
    (
      #|{
      #|  "version":1,
      #|  "upstream":"http://127.0.0.1:9000",
      #|  "session_header":"X-Session",
      #|  "initial_phase":"degraded",
      #|  "transitions":[{"from":"degraded","to":"healthy","on_hit":2}],
      #|  "rules":[
      #|    {"id":"fail","priority":10,"phase":"degraded","match":{"method":"GET","path":"/catalog"},"actions":[{"type":"stub","status":503,"body":"retry"}]},
      #|    {"id":"forward","phase":"healthy","match":{"method":"GET","path":"/catalog"},"actions":[{"type":"passthrough"}]}
      #|  ]
      #|}
    ),
  ).unwrap()
}

///|
fn catalog_request(session : String) -> @core.HttpRequest {
  @core.HttpRequest::new(
    "GET",
    "/catalog",
    [],
    [@core.Header::new("X-Session", session)],
    "",
  )
}

///|
test "decisions preserve the two-failure then recovery sequence" {
  let engine = @runtime.Engine::new(retry_config())
  let first = engine.decide(catalog_request("a"))
  assert_eq(first.rule_id, Some("fail"))
  assert_eq(first.phase_before, "degraded")
  assert_eq(first.phase_after, "degraded")
  let second = engine.decide(catalog_request("a"))
  assert_eq(second.rule_id, Some("fail"))
  assert_eq(second.phase_after, "healthy")
  let third = engine.decide(catalog_request("a"))
  assert_eq(third.rule_id, Some("forward"))
  assert_eq(third.plan.source, @fault.Upstream)
}

///|
test "sessions and unmatched requests do not interfere" {
  let engine = @runtime.Engine::new(retry_config())
  ignore(engine.decide(catalog_request("a")))
  let other = engine.decide(catalog_request("b"))
  assert_eq(other.rule_id, Some("fail"))
  let unmatched = engine.decide(
    @core.HttpRequest::new("GET", "/other", [], [], ""),
  )
  assert_eq(unmatched.rule_id, None)
  assert_eq(unmatched.plan.source, @fault.Upstream)
}
