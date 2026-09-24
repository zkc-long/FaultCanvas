///|
test "hit counters advance a phase deterministically" {
  let store = @scenario.StateStore::new("degraded").unwrap()
  let transitions = [@scenario.Transition::new("degraded", "healthy", OnHit(2))]
  let first = store.record_hit("checkout", transitions).unwrap()
  assert_eq(first.before.phase, "degraded")
  assert_eq(first.after, {
    session: "checkout",
    phase: "degraded",
    hits_in_phase: 1,
  })
  assert_false(first.transitioned)
  let second = store.record_hit("checkout", transitions).unwrap()
  assert_true(second.transitioned)
  assert_eq(second.after, {
    session: "checkout",
    phase: "healthy",
    hits_in_phase: 0,
  })
}

///|
test "sessions are isolated and resettable" {
  let store = @scenario.StateStore::new("cold").unwrap()
  let transitions = [@scenario.Transition::new("cold", "warm", Always)]
  ignore(store.record_hit("tenant-a", transitions))
  assert_eq(store.snapshot("tenant-a").unwrap().phase, "warm")
  assert_eq(store.snapshot("tenant-b").unwrap().phase, "cold")
  assert_eq(store.session_count(), 2)
  assert_eq(store.reset("tenant-a").unwrap().phase, "cold")
  store.reset_all()
  assert_eq(store.session_count(), 0)
}

///|
test "transition validation rejects unusable thresholds" {
  let store = @scenario.StateStore::new("ready").unwrap()
  assert_eq(
    store.record_hit("demo", [
      @scenario.Transition::new("ready", "done", AtLeast(0)),
    ]),
    Err(InvalidHitThreshold(0)),
  )
  match @scenario.StateStore::new("  ") {
    Err(error) => assert_eq(error, EmptyInitialPhase)
    Ok(_) => fail("empty phase must be rejected")
  }
}
