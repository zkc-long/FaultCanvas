# Contributing

1. Keep request matching, scenario transitions and fault planning pure and
   deterministic.
2. Add unit tests for every new behavior and a native integration test when it
   changes HTTP I/O.
3. Run `moon fmt` and the portable test command from the README.
4. Do not add TLS MITM, HTTP/2 or WebSocket behavior to the MVP without a
   separate architecture decision.
5. Keep default bind addresses loopback-safe and validate all configuration at
   startup.
