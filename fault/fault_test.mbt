///|
test "builds an ordered plan around a stub response" {
  let plan = @fault.build([
    Delay(120),
    Stub(@core.HttpResponse::new(201, [], "accepted")),
    OverrideStatus(503),
    Truncate(4),
    Corrupt("!"),
  ]).unwrap()
  assert_eq(plan.delay_ms, 120)
  assert_eq(plan.source, Fixed(@core.HttpResponse::new(201, [], "accepted")))
  assert_eq(
    plan.transform_response(@core.HttpResponse::new(201, [], "accepted")),
    @core.HttpResponse::new(503, [], "acce!"),
  )
}

///|
test "delay-only rules default to passthrough" {
  let plan = @fault.build([Delay(25)]).unwrap()
  assert_eq(plan.source, Upstream)
  assert_eq(plan.delay_ms, 25)
}

///|
test "rejects unsafe and conflicting action combinations" {
  assert_eq(@fault.build([Delay(-1)]), Err(NegativeDelay(-1)))
  assert_eq(
    @fault.build([Stub(@core.HttpResponse::new(200, [], "ok")), PassThrough]),
    Err(MultipleResponseSources),
  )
  assert_eq(
    @fault.build([Abort("drop"), Corrupt("noise")]),
    Err(TransformAfterAbort),
  )
  assert_eq(@fault.build([OverrideStatus(700)]), Err(InvalidStatus(700)))
}
