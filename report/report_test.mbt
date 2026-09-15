///|
fn decision() -> @runtime.Decision {
  {
    session: "checkout-7",
    phase_before: "degraded",
    phase_after: "healthy",
    rule_id: Some("retry"),
    plan: @runtime.Decision::fallback("checkout-7", "degraded").plan,
  }
}

///|
test "journal is bounded and reports stable text" {
  let journal = Journal::new(2)
  journal.record(decision(), Response(503), 120)
  journal.record(decision(), Aborted("socket closed"), 2)
  journal.record(decision(), Response(200), 4)
  assert_eq(journal.events().length(), 2)
  assert_eq(
    journal.to_text(),
    (
      #|#2 session=checkout-7 rule=retry phase=degraded->healthy outcome=aborted:socket closed elapsed_ms=2
      #|#3 session=checkout-7 rule=retry phase=degraded->healthy outcome=response:200 elapsed_ms=4
    ),
  )
}

///|
test "journal produces machine-readable JSON" {
  let journal = Journal::new(1)
  journal.record(decision(), Response(503), 120)
  assert_eq(
    journal.to_json(),
    "{\"events\":[{\"sequence\":1,\"session\":\"checkout-7\",\"phase_before\":\"degraded\",\"phase_after\":\"healthy\",\"rule_id\":\"retry\",\"elapsed_ms\":120,\"outcome\":{\"kind\":\"response\",\"status\":503}}]}",
  )
}
