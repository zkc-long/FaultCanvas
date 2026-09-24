///|
fn method_name(request_method : @http.RequestMethod) -> String {
  match request_method {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
fn split_target(target : String) -> (String, Array[@core.QueryParam]) {
  match target.find("?") {
    None => (target, [])
    Some(index) => {
      let path = target[:index].to_owned()
      let raw_query = target[index + 1:]
      let query : Array[@core.QueryParam] = []
      for item in raw_query.split("&") {
        match item.find("=") {
          None => query.push(@core.QueryParam::new(item.to_owned(), ""))
          Some(separator) =>
            query.push(
              @core.QueryParam::new(
                item[:separator].to_owned(),
                item[separator + 1:].to_owned(),
              ),
            )
        }
      }
      (path, query)
    }
  }
}

///|
fn normalize(request : @http.Request, body : String) -> @core.HttpRequest {
  let headers : Array[@core.Header] = []
  for name, value in request.headers {
    headers.push(@core.Header::new(name.to_string(), value))
  }
  let (path, query) = split_target(request.path)
  @core.HttpRequest::new(method_name(request.meth), path, query, headers, body)
}

///|
fn reason_for(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    400 => "Bad Request"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    413 => "Payload Too Large"
    431 => "Request Header Fields Too Large"
    _ => "FaultCanvas"
  }
}

///|
fn policy_error_status(error : @policy.PolicyError) -> Int {
  match error {
    @policy.TooManyHeaders(_, _) => 431
    @policy.RequestBodyTooLarge(_, _) => 413
    @policy.NonLoopbackListen(_) => 400
    @policy.InvalidLimit(_, _) | @policy.EmptyRedactionHeader => 400
  }
}

///|
async fn send_core_response(
  connection : @http.ServerConnection,
  response : @core.HttpResponse,
) -> Unit {
  connection
  ..send_response(response.status, reason_for(response.status))
  ..write(response.body)
  .end_response()
}

///|
const BODY_READ_CHUNK_SIZE : Int = 4096

///|
const MAX_BODY_BYTES : Int = 2_147_483_647

///|
fn utf16_units_in(bytes : Bytes) -> Int {
  for byte in bytes; units = 0 {
    let value = byte.to_int()
    if value >= 0x80 && value <= 0xBF {
      continue units
    }
    continue units + (if value >= 0xF0 && value <= 0xF4 { 2 } else { 1 })
  } nobreak {
    units
  }
}

///|
fn missing_utf8_suffix(bytes : Bytes) -> Int {
  let start = (bytes.length() - 4).clamp(min=0, max=bytes.length())
  let mut index = bytes.length() - 1
  let mut continuation_bytes = 0
  while index >= start {
    let value = bytes[index].to_int()
    if value >= 0x80 && value <= 0xBF {
      continuation_bytes += 1
      index -= 1
    } else {
      let expected = if value >= 0xC2 && value <= 0xDF {
        2
      } else if value >= 0xE0 && value <= 0xEF {
        3
      } else if value >= 0xF0 && value <= 0xF4 {
        4
      } else {
        1
      }
      let present = continuation_bytes + 1
      return if expected > present { expected - present } else { 0 }
    }
  }
  0
}

///|
/// Read at most max_chars UTF-16 code units plus one fixed-size chunk. The
/// byte ceiling also bounds malformed UTF-8 input, which cannot be counted as
/// characters safely until it has been decoded.
async fn[R : @io.Reader] read_bounded_body(
  reader : R,
  max_chars : Int,
  complete_utf8_suffix? : Bool = true,
) -> (Bytes, Bool) {
  let buffer = Buffer()
  let byte_limit = if max_chars > MAX_BODY_BYTES / 3 {
    MAX_BODY_BYTES
  } else {
    max_chars * 3
  }
  let mut chars = 0
  let mut byte_count = 0
  let mut oversized = false
  while !oversized {
    match reader.read_some(max_len=BODY_READ_CHUNK_SIZE) {
      None => break
      Some(chunk) => {
        let chunk_chars = utf16_units_in(chunk)
        buffer.write_bytes(chunk)
        if chunk_chars > max_chars - chars ||
          chunk.length() > byte_limit - byte_count {
          oversized = true
        } else {
          chars += chunk_chars
          byte_count += chunk.length()
        }
      }
    }
  }
  if oversized && complete_utf8_suffix {
    let mut missing = missing_utf8_suffix(buffer.contents())
    while missing > 0 {
      match reader.read_some(max_len=missing) {
        None => break
        Some(chunk) => {
          buffer.write_bytes(chunk)
          missing = missing_utf8_suffix(buffer.contents())
        }
      }
    }
  }
  (buffer.contents(), oversized)
}

///|
fn upstream_target(
  upstream : String,
  request_path : String,
) -> (String, String) {
  let protocol_end = upstream.find("://").unwrap()
  let authority_start = protocol_end + 3
  let remainder = upstream[authority_start:]
  match remainder.find("/") {
    None => (upstream, request_path)
    Some(path_start) => {
      let origin = upstream[:authority_start + path_start].to_owned()
      let base_path = remainder[path_start:]
      let prefix = if base_path == "/" {
        ""
      } else if base_path.has_suffix("/") {
        base_path[:base_path.length() - 1].to_owned()
      } else {
        base_path.to_owned()
      }
      let suffix = if request_path.has_prefix("/") {
        request_path
      } else {
        "/" + request_path
      }
      (origin, prefix + suffix)
    }
  }
}

///|
async fn forward_upstream(
  config : @config.Config,
  request : @http.Request,
  body : Bytes,
) -> (@http.Response, String) {
  let (origin, path) = upstream_target(config.upstream, request.path)
  let client = @http.Client::Client(origin, headers=request.headers)
  defer client.close()
  client.request(request.meth, path)
  client.write(body)
  let response = client.end_request()
  let (response_body, _) = read_bounded_body(
    client,
    config.policy.max_response_body_chars(),
  )
  (response, @utf8.decode(response_body))
}

///|
async fn handle(
  config : @config.Config,
  engine : @runtime.Engine,
  journal : @report.Journal,
  request : @http.Request,
  body_reader : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let (raw_body, request_body_too_large) = read_bounded_body(
    body_reader,
    config.policy.max_request_body_chars(),
    complete_utf8_suffix=false,
  )
  if request_body_too_large {
    let decision = @runtime.Decision::fallback("invalid", "invalid")
    send_core_response(
      connection,
      @core.HttpResponse::new(413, [], "request rejected by policy"),
    )
    journal.record(decision, @report.Response(413), 0)
    connection.close()
    return
  }
  let normalized = normalize(request, @utf8.decode(raw_body))
  match config.policy.validate_request(normalized) {
    Err(error) => {
      let status = policy_error_status(error)
      let decision = @runtime.Decision::fallback("invalid", "invalid")
      send_core_response(
        connection,
        @core.HttpResponse::new(status, [], "request rejected by policy"),
      )
      journal.record(decision, @report.Response(status), 0)
      return
    }
    Ok(_) => ()
  }
  match normalized.validate(@core.RequestLimits::safe_defaults()) {
    Err(_) => {
      let decision = @runtime.Decision::fallback("invalid", "invalid")
      send_core_response(
        connection,
        @core.HttpResponse::new(400, [], "invalid request"),
      )
      journal.record(decision, @report.Response(400), 0)
      return
    }
    Ok(_) => ()
  }
  let decision = engine.decide(normalized)
  if decision.plan.delay_ms > 0 {
    @async.sleep(decision.plan.delay_ms)
  }
  match decision.plan.source {
    @fault.ConnectionAbort(reason) => {
      connection.close()
      journal.record(decision, @report.Aborted(reason), decision.plan.delay_ms)
    }
    @fault.Fixed(response) => {
      let response = config.policy.filter_response(
        decision.plan.transform_response(response),
      )
      send_core_response(connection, response)
      journal.record(
        decision,
        @report.Response(response.status),
        decision.plan.delay_ms,
      )
    }
    @fault.Upstream => {
      let (response, upstream_body) = forward_upstream(
        config, request, raw_body,
      ) catch {
        _ => {
          let failure = @core.HttpResponse::new(502, [], "upstream unavailable")
          send_core_response(connection, failure)
          journal.record(
            decision,
            @report.UpstreamFailure("request failed"),
            decision.plan.delay_ms,
          )
          return
        }
      }
      let transformed = decision.plan.transform_response(
        @core.HttpResponse::new(response.code, [], upstream_body),
      )
      let transformed = config.policy.filter_response(transformed)
      send_core_response(connection, transformed)
      journal.record(
        decision,
        @report.Response(transformed.status),
        decision.plan.delay_ms,
      )
    }
  }
}

///|
/// Run FaultCanvas on an already-bound HTTP server. Keeping the server object
/// injectable makes loopback integration tests and embedders able to control
/// the listening socket without exposing the decision engine to network code.
pub async fn run(
  server : @http.Server,
  config : @config.Config,
  journal : @report.Journal,
) -> Unit {
  let engine = @runtime.Engine::new(config)
  server.run_forever((request, body, connection) => {
    handle(config, engine, journal, request, body, connection)
  })
}

///|
/// Bind and run a loopback-safe configured proxy indefinitely.
pub async fn serve(config : @config.Config) -> Unit {
  let server = @http.Server(@socket.Addr::parse(config.listen))
  let journal = @report.Journal::new(config.policy.max_events())
  run(server, config, journal)
}
