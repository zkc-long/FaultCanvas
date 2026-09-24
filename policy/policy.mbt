///|
/// Policy values are deliberately explicit so callers can display the active
/// safety boundary in a demo or CI log.
pub(all) struct Policy {
  max_headers : Int
  max_request_body_chars : Int
  max_response_body_chars : Int
  max_events : Int
  redact_headers : Array[String]
} derive(Debug, Eq)

///|
pub(all) enum PolicyError {
  InvalidLimit(String, Int)
  EmptyRedactionHeader
  NonLoopbackListen(String)
  TooManyHeaders(Int, Int)
  RequestBodyTooLarge(Int, Int)
} derive(Debug, Eq)

///|
pub(all) enum HeaderDisposition {
  Keep
  Redact
  Drop
} derive(Debug, Eq)

///|
pub fn Policy::safe_defaults() -> Policy {
  {
    max_headers: 128,
    max_request_body_chars: 1_048_576,
    max_response_body_chars: 1_048_576,
    max_events: 1_000,
    redact_headers: [
      "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key",
      "x-auth-token",
    ],
  }
}

///|
pub fn Policy::new(
  max_headers : Int,
  max_request_body_chars : Int,
  max_response_body_chars : Int,
  max_events : Int,
  redact_headers : Array[String],
) -> Result[Policy, PolicyError] {
  if max_headers < 1 {
    return Err(InvalidLimit("max_headers", max_headers))
  }
  if max_request_body_chars < 0 {
    return Err(InvalidLimit("max_request_body_chars", max_request_body_chars))
  }
  if max_response_body_chars < 0 {
    return Err(InvalidLimit("max_response_body_chars", max_response_body_chars))
  }
  if max_events < 1 {
    return Err(InvalidLimit("max_events", max_events))
  }
  for header in redact_headers {
    if header.trim().is_empty() {
      return Err(EmptyRedactionHeader)
    }
  }
  Ok({
    max_headers,
    max_request_body_chars,
    max_response_body_chars,
    max_events,
    redact_headers: redact_headers.map(fn(value) { value.to_lower() }),
  })
}

///|
pub fn Policy::max_headers(self : Policy) -> Int {
  self.max_headers
}

///|
pub fn Policy::max_request_body_chars(self : Policy) -> Int {
  self.max_request_body_chars
}

///|
pub fn Policy::max_response_body_chars(self : Policy) -> Int {
  self.max_response_body_chars
}

///|
pub fn Policy::max_events(self : Policy) -> Int {
  self.max_events
}

///|
pub fn Policy::listen_is_safe(
  self : Policy,
  listen : String,
) -> Result[Unit, PolicyError] {
  ignore(self)
  if listen.has_prefix("[::1]") || listen == "::1" {
    return Ok(())
  }
  let host = match listen.find(":") {
    Some(index) => listen[:index]
    None => listen
  }
  if host == "127.0.0.1" ||
    host == "localhost" ||
    host == "[::1]" ||
    host == "::1" {
    Ok(())
  } else {
    Err(NonLoopbackListen(listen))
  }
}

///|
fn Policy::configured_redaction(self : Policy, name : String) -> Bool {
  let wanted = name.to_lower()
  for configured in self.redact_headers {
    if configured == wanted {
      return true
    }
  }
  false
}

///|
pub fn Policy::header_disposition(
  self : Policy,
  name : String,
) -> HeaderDisposition {
  let wanted = name.to_lower()
  if self.configured_redaction(wanted) ||
    wanted.has_suffix("-token") ||
    wanted.has_suffix("-secret") ||
    wanted.has_suffix("-password") {
    Redact
  } else if wanted == "connection" ||
    wanted == "keep-alive" ||
    wanted == "proxy-authenticate" ||
    wanted == "proxy-authorization" ||
    wanted == "te" ||
    wanted == "trailer" ||
    wanted == "transfer-encoding" ||
    wanted == "upgrade" {
    Drop
  } else {
    Keep
  }
}

///|
pub fn Policy::redact_value(
  self : Policy,
  name : String,
  value : String,
) -> String {
  match self.header_disposition(name) {
    Redact => "<redacted>"
    _ => value
  }
}

///|
/// Redact common credential markers in free-form error text. The policy is
/// intentionally conservative: it replaces the complete detail when a marker
/// appears rather than attempting to parse arbitrary application payloads.
pub fn Policy::redact_free_text(self : Policy, text : String) -> String {
  ignore(self)
  let lower = text.to_lower()
  if lower.contains("token=") ||
    lower.contains("password=") ||
    lower.contains("secret=") ||
    lower.contains("authorization:") ||
    lower.contains("cookie:") {
    "<redacted-detail>"
  } else {
    text
  }
}

///|
pub fn Policy::sanitize_headers(
  self : Policy,
  headers : Array[@core.Header],
) -> Array[@core.Header] {
  let result : Array[@core.Header] = []
  for header in headers {
    match self.header_disposition(header.name) {
      Drop => ()
      Redact => result.push(@core.Header::new(header.name, "<redacted>"))
      Keep => result.push(header)
    }
  }
  result
}

///|
pub fn Policy::validate_request(
  self : Policy,
  request : @core.HttpRequest,
) -> Result[Unit, PolicyError] {
  if request.headers.length() > self.max_headers {
    return Err(TooManyHeaders(request.headers.length(), self.max_headers))
  }
  if request.body.length() > self.max_request_body_chars {
    return Err(
      RequestBodyTooLarge(request.body.length(), self.max_request_body_chars),
    )
  }
  match
    request.validate({
      max_headers: self.max_headers,
      max_body_chars: self.max_request_body_chars,
    }) {
    Ok(_) => Ok(())
    Err(_) =>
      Err(
        RequestBodyTooLarge(request.body.length(), self.max_request_body_chars),
      )
  }
}

///|
/// Filter hop-by-hop and sensitive response headers before they reach a test
/// client. Content-Length is also removed because the async server recalculates
/// it for the final transformed body.
pub fn Policy::filter_response(
  self : Policy,
  response : @core.HttpResponse,
) -> @core.HttpResponse {
  let headers : Array[@core.Header] = []
  for header in response.headers {
    if header.name.to_lower() != "content-length" {
      match self.header_disposition(header.name) {
        Drop | Redact => ()
        Keep => headers.push(header)
      }
    }
  }
  let body = response.body[:self.max_response_body_chars.clamp(
    min=0,
    max=response.body.length(),
  )].to_owned()
  @core.HttpResponse::new(response.status, headers, body)
}

///|
pub extend Policy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Policy with Eq::{not_equal, equal}

///|
pub extend PolicyError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyError with Eq::{not_equal, equal}

///|
pub extend HeaderDisposition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HeaderDisposition with Eq::{not_equal, equal}
