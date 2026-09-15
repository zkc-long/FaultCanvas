///|
fn proxy_config(upstream : String) -> @config.Config {
  @config.parse(
    "{\"version\":1,\"upstream\":\"" +
    upstream +
    "\",\"rules\":[{\"id\":\"stub\",\"match\":{\"method\":\"GET\",\"path\":\"/stub\"},\"actions\":[{\"type\":\"stub\",\"status\":503,\"body\":\"simulated\"}]}]}",
  ).unwrap()
}

///|
async test "loopback proxy serves faults and forwards unmatched HTTP requests" {
  @async.with_task_group <| root => {
    let upstream = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    root.spawn_bg(no_wait=true, () => {
      upstream.run_forever((request, _body, connection) => {
        connection..send_response(200, "OK").write("upstream:" + request.path)
      })
    })
    let config = proxy_config("http://127.0.0.1:\{upstream.addr.port()}")
    let proxy = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let journal = @report.Journal::new(10)
    root.spawn_bg(no_wait=true, () => run(proxy, config, journal))
    @async.sleep(40)
    let (stub_response, stub_body) = @http.get(
      "http://127.0.0.1:\{proxy.addr.port()}/stub",
    )
    assert_eq(stub_response.code, 503)
    assert_eq(stub_body.text(), "simulated")
    let (forwarded_response, forwarded_body) = @http.get(
      "http://127.0.0.1:\{proxy.addr.port()}/catalog",
    )
    assert_eq(forwarded_response.code, 200)
    assert_eq(forwarded_body.text(), "upstream:/catalog")
    assert_eq(journal.events().length(), 2)
    proxy.close()
    upstream.close()
  }
}
