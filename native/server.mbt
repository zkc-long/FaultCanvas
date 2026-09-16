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
  .write(response.body)
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
  let raw_body = body_reader.read_all()
  let normalized = normalize(request, raw_body.text())
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
      let (response, upstream_body) = @http.request(
        config.upstream + request.path,
        request.meth,
        request.headers,
        raw_body,
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
        @core.HttpResponse::new(response.code, [], upstream_body.text()),
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
