# Configuration reference

FaultCanvas reads one JSON document. Parsing is atomic: any syntax, schema or
fault-plan error rejects the complete configuration before a listener starts.

## Root object

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | yes | Schema version. Only `1` is accepted. |
| `upstream` | yes | HTTP upstream URL. Must begin with `http://`. |
| `listen` | no | Bind address; defaults to `127.0.0.1:8080`. |
| `session_header` | no | Header that partitions scenario state; absent values use `global`. |
| `initial_phase` | no | Initial phase; defaults to `default`. |
| `transitions` | no | Ordered phase transitions. |
| `rules` | yes | Ordered fault rules. IDs must be unique. |

## Safety policy

The optional `limits` object accepts `max_headers`,
`max_request_body_chars`, `max_response_body_chars` and `max_events`. Values
default to 128 headers, 1 MiB request/response bodies and 1000 retained events.
The optional `security.redact_headers` array adds case-insensitive header names
to the built-in authorization/cookie/token redaction set. Invalid limits are
rejected before the listener opens.

FaultCanvas accepts loopback listeners (`127.0.0.1`, `localhost` and `::1`)
only in the competition profile. Public binding must be an explicit future
deployment decision, not an accidental configuration typo.

## Rules

Each rule has `id`, optional integer `priority`, optional `phase`, optional
`match`, and required `actions`.

The matcher chooses the highest priority match, then the most specific match,
then declaration order. `match` may include:

- `method`
- `path` for exact matching, or `path_prefix` (the two are exclusive)
- `query` and `headers`: arrays of `{ "name": "…", "value": "…" }`
- `body_contains`

## Actions

Actions execute as one validated plan. A plan has at most one response source:
`passthrough`, `stub`, or `abort`. An omitted source defaults to passthrough.

```json
{ "type": "passthrough" }
{ "type": "delay", "ms": 120 }
{ "type": "stub", "status": 503, "body": "retry later" }
{ "type": "abort", "reason": "simulate peer reset" }
{ "type": "status", "code": 429 }
{ "type": "truncate", "chars": 64 }
{ "type": "corrupt", "suffix": "<corrupt>" }
```

Status override, truncation and corruption transform a fixed or upstream
response in that order. They cannot be combined with `abort`.

## State transitions

Transitions are checked after a matched interaction. The first matching
transition wins. This makes the following setup return two 503 responses before
the `healthy` phase is active:

```json
{
  "initial_phase": "degraded",
  "transitions": [
    { "from": "degraded", "to": "healthy", "on_hit": 2 }
  ]
}
```

Use `examples/payment/faultcanvas.json` as a complete runnable scenario.

## Deterministic verification suites

`faultcanvas verify CONFIG SUITE.json` replays a request sequence against a
fresh in-memory engine. This checks stateful transitions and response actions
without starting a listener or contacting the configured upstream. The suite's
optional `upstream_status` field (default `200`) is the response used to model
successful passthrough steps.

Each step has a unique `id`, a full request (`method`, `path`, optional `query`,
`headers` and `body`) and optional assertions. Query and header entries are
arrays of `{ "name": "…", "value": "…" }`; this preserves duplicate headers.
Assertions may check `rule_id`, `phase_before`, `phase_after`, `outcome`
(`response` or `aborted`), `status`, `body_contains` and `delay_ms`.

```json
{
  "version": 1,
  "steps": [
    {
      "id": "first-retry",
      "request": {
        "method": "POST",
        "path": "/payments",
        "headers": [{ "name": "X-Checkout-Id", "value": "demo-order" }]
      },
      "expect": {
        "rule_id": "checkout-retries-are-unavailable",
        "phase_before": "degraded",
        "status": 503,
        "delay_ms": 120
      }
    }
  ]
}
```

Steps run in order and share scenario state, while each CLI invocation starts
from a clean state. A failed assertion exits non-zero. The suite models the
decision engine; use the native loopback tests and the `serve` demo to verify
real HTTP transport behavior.
