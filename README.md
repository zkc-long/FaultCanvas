# FaultCanvas

FaultCanvas is a MoonBit-native programmable HTTP fault proxy and stateful
service-virtualization gateway. It sits between a client and a real HTTP/1.1
upstream, so retry, fallback and error-handling behavior can be demonstrated
without changing the client.

## Why it exists

FaultCanvas deliberately covers a different boundary from existing MoonBit
projects:

- contract mock servers generate responses from an API specification;
- cassette libraries replay calls made through an in-process transport;
- model simulators explore a model instead of a live network;
- FaultCanvas intercepts a real loopback HTTP boundary and can change behavior
  as a scenario evolves.

The portable library packages (`core`, `matcher`, `scenario`, `fault`,
`config`, `runtime`, `report`) are deterministic and testable without a
network. The `native` package owns sockets and the HTTP adapter.

## Competition MVP

- HTTP/1.1 reverse proxy for `http://` upstreams
- deterministic method/path/query/header/body matching
- `passthrough`, `stub`, `delay`, `abort`, status override, truncation and
  body corruption
- session-keyed phases and hit-count transitions
- bounded runtime journal with text and JSON reports
- a reusable Mooncakes-ready library plus `check`, `simulate`, `serve` and
  `report`, `stats`, `redact` and assertion-based `verify` CLI commands

Out of scope: TLS interception, HTTP/2, gRPC, WebSocket, public-by-default
listeners, distributed control planes and browser UI.

## Quick start

Install MoonBit, then run the portable test suite:

```sh
moon test --target wasm-gc --deny-warn core matcher scenario fault config runtime report observe policy verify
```

Validate the payment retry scenario:

```sh
moon run cmd/main -- check examples/payment/faultcanvas.json
moon run cmd/main -- simulate examples/payment/faultcanvas.json POST /payments
moon run cmd/main -- stats examples/payment/faultcanvas.json POST /payments
moon run cmd/main -- redact examples/payment/faultcanvas.json "upstream token=demo"
moon run cmd/main -- verify examples/payment/faultcanvas.json examples/payment/acceptance-suite.json
```

Start a local HTTP upstream on `127.0.0.1:9000`, then run the proxy:

```sh
moon run cmd/main -- serve examples/payment/faultcanvas.json
```

The first two `POST /payments` interactions for one `X-Checkout-Id` session
receive delayed 503 responses. The third is passed through to the upstream.

`stats` runs the same deterministic scenario three times and prints latency and
failure counters. `redact` demonstrates the exact free-text redaction policy
used by report renderers.

`verify` replays an ordered request suite through a fresh copy of the same
scenario engine. It checks expected rules, phase transitions, fault outcomes,
response status/body fragments and delay values without opening sockets. A
failed assertion prints the mismatched fields and exits with a non-zero status,
so the same scenario can be used locally or in CI. The sample suite exercises
two degraded payment attempts followed by recovery and verifies session
isolation.

The native adapter requires a C compiler (Clang, GCC, or MSVC) available to
MoonBit. See [Configuration](docs/CONFIGURATION.md) for the exact schema and
[the demo](docs/DEMO.md) for a 3–5 minute presentation flow.

## Package layout

| Package | Purpose |
| --- | --- |
| `core` | Normalized HTTP types and limits |
| `matcher` | Deterministic request selection and diagnostics |
| `scenario` | Session isolation, phases and transitions |
| `fault` | Validated fault execution plans |
| `config` | Versioned JSON configuration decoder |
| `runtime` | Pure request-to-decision orchestration |
| `report` | Bounded evidence journal and renderers |
| `native` | HTTP/1.1 server/upstream adapter |
| `verify` | Deterministic, assertion-based scenario replay for CI and acceptance |
| `cmd/main` | Native CLI executable |

## License

Apache-2.0. See [LICENSE](LICENSE).
