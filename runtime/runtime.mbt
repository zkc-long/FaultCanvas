///|
pub(all) struct Decision {
  session : String
  phase_before : String
  phase_after : String
  rule_id : String?
  plan : @fault.FaultPlan
} derive(Debug, Eq)

///|
pub fn Decision::fallback(session : String, phase : String) -> Decision {
  {
    session,
    phase_before: phase,
    phase_after: phase,
    rule_id: None,
    plan: @fault.build([]).unwrap(),
  }
}

///|
pub struct Engine {
  config : @config.Config
  states : @scenario.StateStore
}

///|
pub fn Engine::new(config : @config.Config) -> Engine {
  let states = match @scenario.StateStore::new(config.initial_phase) {
    Ok(store) => store
    Err(_) => panic()
  }
  { config, states, }
}

///|
fn Engine::session_for(self : Engine, request : @core.HttpRequest) -> String {
  match self.config.session_header {
    Some(header) =>
      match request.header(header) {
        Some(value) if !value.trim().is_empty() => value
        _ => "global"
      }
    None => "global"
  }
}

///|
fn rule_is_active(rule : @config.ConfiguredRule, phase : String) -> Bool {
  match rule.phase {
    None => true
    Some(wanted) => wanted == phase
  }
}

///|
/// Produce a decision before performing any socket I/O. Matched interactions
/// advance their scenario after the decision is made: a two-hit degraded phase
/// therefore returns two degraded responses before recovery becomes active.
pub fn Engine::decide(self : Engine, request : @core.HttpRequest) -> Decision {
  let session = self.session_for(request)
  let before = match self.states.snapshot(session) {
    Ok(snapshot) => snapshot
    Err(_) => panic()
  }
  let eligible : Array[@config.ConfiguredRule] = []
  let candidates : Array[@matcher.RuleCandidate] = []
  for rule in self.config.rules {
    if rule_is_active(rule, before.phase) {
      eligible.push(rule)
      candidates.push(rule.candidate)
    }
  }
  match @matcher.select_index(candidates, request) {
    None => Decision::fallback(session, before.phase)
    Some(index) => {
      let rule = eligible[index]
      let plan = @fault.build(rule.actions).unwrap()
      let advance = match
        self.states.record_hit(session, self.config.transitions) {
        Ok(value) => value
        Err(_) => panic()
      }
      {
        session,
        phase_before: advance.before.phase,
        phase_after: advance.after.phase,
        rule_id: Some(rule.candidate.id),
        plan,
      }
    }
  }
}

///|
pub fn Engine::reset_session(self : Engine, session : String) -> Unit {
  ignore(self.states.reset(session))
}
