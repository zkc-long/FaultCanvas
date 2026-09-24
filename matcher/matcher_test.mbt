///|
fn checkout_request() -> @core.HttpRequest {
  @core.HttpRequest::new(
    "post",
    "/api/checkout",
    [@core.QueryParam::new("region", "cn")],
    [@core.Header::new("X-Tenant", "demo")],
    "{\"total\":42}",
  )
}

///|
test "matches method path query header and body" {
  let pattern = @matcher.RequestPattern::new(
    Some("POST"),
    Some(Exact("/api/checkout")),
    [@matcher.FieldPattern::new("region", "cn")],
    [@matcher.FieldPattern::new("x-tenant", "demo")],
    Some("\"total\":42"),
  )
  let result = pattern.evaluate(checkout_request())
  assert_true(result.matched)
  assert_eq(result.specificity, 5)
  assert_eq(result.mismatch, None)
}

///|
test "returns a useful mismatch" {
  let pattern = @matcher.RequestPattern::new(
    Some("GET"),
    Some(Prefix("/api/")),
    [],
    [],
    None,
  )
  assert_eq(
    pattern.evaluate(checkout_request()).mismatch,
    Some(Verb(expected="GET", actual="POST")),
  )
}

///|
test "selection is deterministic by priority specificity then order" {
  let broad = @matcher.RuleCandidate::new(
    "broad",
    10,
    @matcher.RequestPattern::new(
      Some("POST"),
      Some(Prefix("/api/")),
      [],
      [],
      None,
    ),
  )
  let exact = @matcher.RuleCandidate::new(
    "exact",
    10,
    @matcher.RequestPattern::new(
      Some("POST"),
      Some(Exact("/api/checkout")),
      [@matcher.FieldPattern::new("region", "cn")],
      [],
      None,
    ),
  )
  let lower = @matcher.RuleCandidate::new(
    "lower",
    1,
    @matcher.RequestPattern::new(None, None, [], [], None),
  )
  assert_eq(
    @matcher.select_index([broad, exact, lower], checkout_request()),
    Some(1),
  )
}
