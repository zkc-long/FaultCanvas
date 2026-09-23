# Acceptance guide

This guide maps the project to the [September 2026 MoonBit Hackathon
acceptance criteria](https://moonbitlang.github.io/Hackathon2026/). The
official schedule calls for source code, README, tests and a reproducible demo.
It also requires MoonBit as the primary language, a public repository with
traceable development, substantive new work, an OSI-approved license and an
explainable result. The official FAQ says a project does not need to be large;
clear boundaries, reliable tests, complete documentation and real usability
matter more than code volume.

## Reproducible acceptance path

Run these commands from the repository root with MoonBit installed:

```sh
moon check
moon test --target wasm-gc --deny-warn core matcher scenario fault config runtime report observe policy verify
moon test --target native --deny-warn native
moon run cmd/main -- check examples/payment/faultcanvas.json
moon run cmd/main -- verify examples/payment/faultcanvas.json examples/payment/acceptance-suite.json
```

The portable suite verifies matching, fault-plan validation, session isolation,
configuration and reports without network access. The native loopback suite
starts local HTTP endpoints and verifies the adapter against real requests. The
acceptance suite replays four interactions: two injected 503 responses, phase
recovery, successful passthrough, and isolation of a second checkout. It exits
non-zero when any expected rule, phase, outcome, status, body fragment or delay
does not match.

For the interactive demo and dependency setup, see [DEMO.md](DEMO.md) and
[CONFIGURATION.md](CONFIGURATION.md). The workflow in `.github/workflows/ci.yml`
runs the portable engine tests, native loopback checks and package validation.

## Evaluation evidence

| Criterion | Evidence in this repository |
| --- | --- |
| Functional completeness | `core`, `matcher`, `scenario`, `fault`, `runtime`, `native`, `verify`; payment retry fixture |
| Engineering quality | Package boundaries, input limits, redaction policy, unit tests, native loopback tests and CI |
| Explainability | [Architecture decision](adr/0001-real-network-proxy.md), [development retrospective](DEVELOPMENT_RETROSPECTIVE.md), comments and demo steps |
| User experience | CLI `check`, `simulate`, `verify`, `serve`, `report`, `stats` and `redact`; versioned JSON examples and actionable assertion output |
| Open source | Public GitHub history, Apache-2.0 license, dependency notices and build instructions |

## Scope and limits

FaultCanvas currently targets HTTP/1.1 with cleartext HTTP upstreams. TLS
interception, HTTP/2, gRPC, WebSocket, public listeners and distributed
control planes remain out of scope. `verify` validates deterministic decision
logic and modeled responses; real socket behavior is covered separately by
native tests and the loopback demo.
