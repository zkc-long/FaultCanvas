///|
test "request normalization and lookup" {
  let request = @core.HttpRequest::new(
    "post",
    "/checkout",
    [@core.QueryParam::new("attempt", "2")],
    [@core.Header::new("Content-Type", "application/json")],
    "{\"total\":42}",
  )
  assert_eq(request.verb, "POST")
  assert_eq(request.header("content-type"), Some("application/json"))
  assert_eq(request.query_first("attempt"), Some("2"))
  assert_eq(request.validate(@core.RequestLimits::safe_defaults()), Ok(()))
}

///|
test "request limits reject unsafe input" {
  let request = @core.HttpRequest::new("GET", "not-absolute", [], [], "12345")
  assert_eq(
    request.validate({ max_headers: 0, max_body_chars: 4, }),
    Err(InvalidPath("not-absolute")),
  )
  let body_request = @core.HttpRequest::new("GET", "/", [], [], "12345")
  assert_eq(
    body_request.validate({ max_headers: 0, max_body_chars: 4, }),
    Err(BodyTooLarge(actual=5, limit=4)),
  )
}

///|
test "response status is validated" {
  assert_eq(@core.HttpResponse::new(200, [], "ok").validate(), Ok(()))
  assert_eq(
    @core.HttpResponse::new(42, [], "bad").validate(),
    Err(InvalidStatus(42)),
  )
}
