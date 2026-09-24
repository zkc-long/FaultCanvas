///|
/// Fault actions are intentionally transport-independent. The native adapter
/// later maps a built plan to HTTP bytes, a delay, or a closed connection.
pub(all) enum FaultAction {
  PassThrough
  Stub(@core.HttpResponse)
  Delay(Int)
  Abort(String)
  OverrideStatus(Int)
  Truncate(Int)
  Corrupt(String)
} derive(Debug, Eq)

///|
pub(all) enum ResponseSource {
  Upstream
  Fixed(@core.HttpResponse)
  ConnectionAbort(String)
} derive(Debug, Eq)

///|
pub(all) struct FaultPlan {
  source : ResponseSource
  delay_ms : Int
  status_override : Int?
  truncate_to_chars : Int?
  corrupt_suffix : String?
} derive(Debug, Eq)

///|
pub(all) enum FaultError {
  NegativeDelay(Int)
  InvalidStatus(Int)
  NegativeTruncate(Int)
  EmptyAbortReason
  EmptyCorruption
  MultipleResponseSources
  MultipleStatusOverrides
  MultipleTruncations
  MultipleCorruptions
  TransformAfterAbort
} derive(Debug, Eq)

///|
pub extend FaultAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FaultAction with Eq::{not_equal, equal}

///|
pub extend ResponseSource with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ResponseSource with Eq::{not_equal, equal}

///|
pub extend FaultPlan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FaultPlan with Eq::{not_equal, equal}

///|
pub extend FaultError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FaultError with Eq::{not_equal, equal}

///|
fn source_is_abort(source : ResponseSource) -> Bool {
  match source {
    ConnectionAbort(_) => true
    _ => false
  }
}

///|
/// Turn actions into one normalized execution plan. An action list with no
/// source action defaults to passthrough, making a delay-only rule useful.
pub fn build(actions : Array[FaultAction]) -> Result[FaultPlan, FaultError] {
  let mut source = Upstream
  let mut source_was_explicit = false
  let mut delay_ms = 0
  let mut status_override : Int? = None
  let mut truncate_to_chars : Int? = None
  let mut corrupt_suffix : String? = None
  for action in actions {
    match action {
      PassThrough => {
        if source_was_explicit {
          return Err(MultipleResponseSources)
        }
        source_was_explicit = true
        source = Upstream
      }
      Stub(response) => {
        if source_was_explicit {
          return Err(MultipleResponseSources)
        }
        match response.validate() {
          Ok(_) => ()
          Err(_) => return Err(InvalidStatus(response.status))
        }
        source_was_explicit = true
        source = Fixed(response)
      }
      Abort(reason) => {
        if source_was_explicit {
          return Err(MultipleResponseSources)
        }
        if reason.trim().is_empty() {
          return Err(EmptyAbortReason)
        }
        source_was_explicit = true
        source = ConnectionAbort(reason)
      }
      Delay(value) => {
        if value < 0 {
          return Err(NegativeDelay(value))
        }
        delay_ms = delay_ms + value
      }
      OverrideStatus(value) => {
        if value < 100 || value > 599 {
          return Err(InvalidStatus(value))
        }
        match status_override {
          Some(_) => return Err(MultipleStatusOverrides)
          None => status_override = Some(value)
        }
      }
      Truncate(value) => {
        if value < 0 {
          return Err(NegativeTruncate(value))
        }
        match truncate_to_chars {
          Some(_) => return Err(MultipleTruncations)
          None => truncate_to_chars = Some(value)
        }
      }
      Corrupt(value) => {
        if value.is_empty() {
          return Err(EmptyCorruption)
        }
        match corrupt_suffix {
          Some(_) => return Err(MultipleCorruptions)
          None => corrupt_suffix = Some(value)
        }
      }
    }
  }
  if source_is_abort(source) &&
    (
      status_override is Some(_) ||
      truncate_to_chars is Some(_) ||
      corrupt_suffix is Some(_)
    ) {
    return Err(TransformAfterAbort)
  }
  Ok({ source, delay_ms, status_override, truncate_to_chars, corrupt_suffix, })
}

///|
/// Apply response-level fault transformations in their fixed order: status,
/// truncation, then corruption. A connection abort has no response to mutate.
pub fn FaultPlan::transform_response(
  self : FaultPlan,
  response : @core.HttpResponse,
) -> @core.HttpResponse {
  let status = match self.status_override {
    Some(value) => value
    None => response.status
  }
  let body = match self.truncate_to_chars {
    Some(limit) =>
      response.body[:limit.clamp(min=0, max=response.body.length())].to_owned()
    None => response.body
  }
  let body = match self.corrupt_suffix {
    Some(suffix) => body + suffix
    None => body
  }
  @core.HttpResponse::new(status, response.headers, body)
}
