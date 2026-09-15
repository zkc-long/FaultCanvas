///|
/// A normalized HTTP header. Lookup is case-insensitive, while the original
/// spelling is retained for forwarding and diagnostics.
pub(all) struct Header {
  name : String
  value : String
} derive(Debug, Eq)

///|
pub fn Header::new(name : String, value : String) -> Header {
  { name, value, }
}

///|
pub(all) struct QueryParam {
  name : String
  value : String
} derive(Debug, Eq)

///|
pub fn QueryParam::new(name : String, value : String) -> QueryParam {
  { name, value, }
}

///|
/// The transport-independent request consumed by the matcher.
pub(all) struct HttpRequest {
  verb : String
  path : String
  query : Array[QueryParam]
  headers : Array[Header]
  body : String
} derive(Debug, Eq)

///|
pub fn HttpRequest::new(
  verb : String,
  path : String,
  query : Array[QueryParam],
  headers : Array[Header],
  body : String,
) -> HttpRequest {
  { verb: verb.to_upper(), path, query, headers, body, }
}

///|
pub fn HttpRequest::header(self : HttpRequest, name : String) -> String? {
  let wanted = name.to_lower()
  for header in self.headers {
    if header.name.to_lower() == wanted {
      return Some(header.value)
    }
  }
  None
}

///|
pub fn HttpRequest::query_first(self : HttpRequest, name : String) -> String? {
  for item in self.query {
    if item.name == name {
      return Some(item.value)
    }
  }
  None
}

///|
pub(all) struct HttpResponse {
  status : Int
  headers : Array[Header]
  body : String
} derive(Debug, Eq)

///|
pub fn HttpResponse::new(
  status : Int,
  headers : Array[Header],
  body : String,
) -> HttpResponse {
  { status, headers, body, }
}

///|
pub(all) struct RequestLimits {
  max_headers : Int
  max_body_chars : Int
} derive(Debug, Eq)

///|
pub fn RequestLimits::safe_defaults() -> RequestLimits {
  { max_headers: 128, max_body_chars: 1_048_576, }
}

///|
pub(all) enum ValidationError {
  EmptyMethod
  InvalidPath(String)
  TooManyHeaders(actual~ : Int, limit~ : Int)
  BodyTooLarge(actual~ : Int, limit~ : Int)
  InvalidStatus(Int)
} derive(Debug, Eq)

///|
pub fn HttpRequest::validate(
  self : HttpRequest,
  limits : RequestLimits,
) -> Result[Unit, ValidationError] {
  if self.verb.trim().is_empty() {
    return Err(EmptyMethod)
  }
  if !self.path.has_prefix("/") {
    return Err(InvalidPath(self.path))
  }
  if self.headers.length() > limits.max_headers {
    return Err(
      TooManyHeaders(actual=self.headers.length(), limit=limits.max_headers),
    )
  }
  if self.body.length() > limits.max_body_chars {
    return Err(
      BodyTooLarge(actual=self.body.length(), limit=limits.max_body_chars),
    )
  }
  Ok(())
}

///|
pub fn HttpResponse::validate(
  self : HttpResponse,
) -> Result[Unit, ValidationError] {
  if self.status < 100 || self.status > 599 {
    Err(InvalidStatus(self.status))
  } else {
    Ok(())
  }
}
