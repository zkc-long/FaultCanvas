///|
test "safe defaults classify secrets and hop-by-hop headers" {
  let policy = Policy::safe_defaults()
  assert_eq(policy.header_disposition("Authorization"), Redact)
  assert_eq(policy.header_disposition("X-Session-Token"), Redact)
  assert_eq(policy.header_disposition("Connection"), Drop)
  assert_eq(policy.header_disposition("Content-Type"), Keep)
  assert_eq(policy.redact_value("Cookie", "session=secret"), "<redacted>")
}

///|
test "custom limits reject oversized requests" {
  let policy = Policy::new(2, 4, 8, 3, ["X-Debug-Secret"]).unwrap()
  let request = @core.HttpRequest::new(
    "POST",
    "/upload",
    [],
    [@core.Header::new("X-Debug-Secret", "value")],
    "12345",
  )
  assert_eq(policy.validate_request(request), Err(RequestBodyTooLarge(5, 4)))
  assert_eq(policy.sanitize_headers(request.headers), [
    @core.Header::new("X-Debug-Secret", "<redacted>"),
  ])
}

///|
test "response filtering truncates and removes unsafe headers" {
  let policy = Policy::new(8, 8, 4, 2, []).unwrap()
  let response = policy.filter_response(
    @core.HttpResponse::new(
      200,
      [
        @core.Header::new("Content-Length", "99"),
        @core.Header::new("Connection", "close"),
        @core.Header::new("Content-Type", "text/plain"),
      ],
      "abcdef",
    ),
  )
  assert_eq(response.body, "abcd")
  assert_eq(response.headers, [@core.Header::new("Content-Type", "text/plain")])
}

///|
test "listen policy only accepts loopback addresses" {
  let policy = Policy::safe_defaults()
  assert_eq(policy.listen_is_safe("127.0.0.1:8080"), Ok(()))
  assert_eq(policy.listen_is_safe("localhost:8080"), Ok(()))
  assert_eq(
    policy.listen_is_safe("0.0.0.0:8080"),
    Err(NonLoopbackListen("0.0.0.0:8080")),
  )
}

///|
test "invalid limits are rejected before policy construction" {
  assert_eq(Policy::new(0, 1, 1, 1, []), Err(InvalidLimit("max_headers", 0)))
  assert_eq(Policy::new(1, 1, 1, 1, ["  "]), Err(EmptyRedactionHeader))
}
