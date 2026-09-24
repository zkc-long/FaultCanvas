///|
/// A transition guard is evaluated after the current phase records a hit.
pub(all) enum TransitionGuard {
  Always
  OnHit(Int)
  AtLeast(Int)
} derive(Debug, Eq)

///|
pub(all) struct Transition {
  from : String
  to : String
  condition : TransitionGuard
} derive(Debug, Eq)

///|
pub fn Transition::new(
  from : String,
  to : String,
  condition : TransitionGuard,
) -> Transition {
  { from, to, condition, }
}

///|
pub(all) enum ScenarioError {
  EmptyInitialPhase
  EmptySessionKey
  EmptyTransitionPhase
  InvalidHitThreshold(Int)
} derive(Debug, Eq)

///|
pub(all) struct ScenarioSnapshot {
  session : String
  phase : String
  hits_in_phase : Int
} derive(Debug, Eq)

///|
pub(all) struct ScenarioAdvance {
  before : ScenarioSnapshot
  after : ScenarioSnapshot
  transitioned : Bool
} derive(Debug, Eq)

///|
struct SessionState {
  session : String
  phase : String
  hits_in_phase : Int
}

///|
pub extend TransitionGuard with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransitionGuard with Eq::{not_equal, equal}

///|
pub extend Transition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Transition with Eq::{not_equal, equal}

///|
pub extend ScenarioError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScenarioError with Eq::{not_equal, equal}

///|
pub extend ScenarioSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScenarioSnapshot with Eq::{not_equal, equal}

///|
pub extend ScenarioAdvance with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScenarioAdvance with Eq::{not_equal, equal}

///|
/// StateStore intentionally uses a small ordered collection: scenario sessions
/// stay deterministic across backends, and the competition runtime applies a
/// separate upper bound before admitting session keys.
pub struct StateStore {
  initial_phase : String
  entries : Array[SessionState]
}

///|
pub fn StateStore::new(
  initial_phase : String,
) -> Result[StateStore, ScenarioError] {
  if initial_phase.trim().is_empty() {
    Err(EmptyInitialPhase)
  } else {
    Ok({ initial_phase, entries: [], })
  }
}

///|
fn StateStore::find_index(self : StateStore, session : String) -> Int? {
  for index = 0; index < self.entries.length(); index = index + 1 {
    if self.entries[index].session == session {
      return Some(index)
    }
  }
  None
}

///|
fn StateStore::ensure_index(
  self : StateStore,
  session : String,
) -> Result[Int, ScenarioError] {
  if session.trim().is_empty() {
    return Err(EmptySessionKey)
  }
  match self.find_index(session) {
    Some(index) => Ok(index)
    None => {
      self.entries.push({
        session,
        phase: self.initial_phase,
        hits_in_phase: 0,
      })
      Ok(self.entries.length() - 1)
    }
  }
}

///|
pub fn StateStore::snapshot(
  self : StateStore,
  session : String,
) -> Result[ScenarioSnapshot, ScenarioError] {
  let index = match self.ensure_index(session) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let entry = self.entries[index]
  Ok({
    session: entry.session,
    phase: entry.phase,
    hits_in_phase: entry.hits_in_phase,
  })
}

///|
fn TransitionGuard::validate(
  self : TransitionGuard,
) -> Result[Unit, ScenarioError] {
  match self {
    Always => Ok(())
    OnHit(value) | AtLeast(value) =>
      if value < 1 {
        Err(InvalidHitThreshold(value))
      } else {
        Ok(())
      }
  }
}

///|
pub fn Transition::validate(self : Transition) -> Result[Unit, ScenarioError] {
  if self.from.trim().is_empty() || self.to.trim().is_empty() {
    return Err(EmptyTransitionPhase)
  }
  self.condition.validate()
}

///|
fn TransitionGuard::allows(self : TransitionGuard, hits : Int) -> Bool {
  match self {
    Always => true
    OnHit(expected) => hits == expected
    AtLeast(minimum) => hits >= minimum
  }
}

///|
/// Record one completed interaction. The first declared matching transition
/// wins, which keeps scenario playback stable and easy to explain in reports.
pub fn StateStore::record_hit(
  self : StateStore,
  session : String,
  transitions : Array[Transition],
) -> Result[ScenarioAdvance, ScenarioError] {
  for transition in transitions {
    match transition.validate() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let index = match self.ensure_index(session) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let current = self.entries[index]
  let before : ScenarioSnapshot = {
    session: current.session,
    phase: current.phase,
    hits_in_phase: current.hits_in_phase,
  }
  let hits = current.hits_in_phase + 1
  let mut next_phase = current.phase
  let mut transitioned = false
  for transition in transitions {
    if !transitioned &&
      transition.from == current.phase &&
      transition.condition.allows(hits) {
      next_phase = transition.to
      transitioned = true
    }
  }
  let next_hits = if transitioned { 0 } else { hits }
  self.entries[index] = {
    session: current.session,
    phase: next_phase,
    hits_in_phase: next_hits,
  }
  Ok({
    before,
    after: {
      session: current.session,
      phase: next_phase,
      hits_in_phase: next_hits,
    },
    transitioned,
  })
}

///|
pub fn StateStore::reset(
  self : StateStore,
  session : String,
) -> Result[ScenarioSnapshot, ScenarioError] {
  if session.trim().is_empty() {
    return Err(EmptySessionKey)
  }
  match self.find_index(session) {
    Some(index) => {
      self.entries[index] = {
        session,
        phase: self.initial_phase,
        hits_in_phase: 0,
      }
      self.snapshot(session)
    }
    None => self.snapshot(session)
  }
}

///|
pub fn StateStore::reset_all(self : StateStore) -> Unit {
  self.entries.clear()
}

///|
pub fn StateStore::session_count(self : StateStore) -> Int {
  self.entries.length()
}
