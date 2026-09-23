# FaultCanvas development retrospective

## Problem and project boundary

FaultCanvas addresses a gap between a client and a real HTTP service. Mock
servers and in-process record/replay tools are useful, but they do not exercise
an unchanged client across a real socket boundary while the service behavior
changes over a sequence of requests. FaultCanvas therefore became a local
HTTP/1.1 reverse proxy with a deterministic MoonBit decision engine.

The boundary is deliberately small: one cleartext HTTP/1.1 upstream, loopback
listener, declarative JSON rules and bounded reports. This makes the demo
reproducible and avoids presenting a partially implemented general-purpose
gateway as a finished product.

## Architecture decisions

Request normalization, matching, state transitions, fault planning, safety
policy and verification are pure MoonBit packages. Socket handling is isolated
in `native`, and `cmd/main` connects configuration to the library. This allows
most behavior to run under the portable test target while native tests cover
the real transport boundary.

Fault rules are validated before execution. One rule chooses at most one
response source, then may apply ordered response transformations. Scenario
state is keyed by a configured request header; an explicit hit threshold moves
the session from degraded to healthy. Reports omit request bodies and apply
redaction to sensitive failure details.

The new verification-suite runner reuses the runtime instead of implementing a
second rule engine. A suite declares complete requests and expected observable
results. It runs in a fresh engine without sockets, so acceptance and CI checks
are stable across environments. The native loopback test remains necessary
because a modeled passthrough response does not validate HTTP parsing, socket
closure or upstream integration.

## Validation and use of AI tools

AI assistance was used to inspect the existing module boundaries, draft the
verification format, implement parser and assertion paths, and identify build
and test issues. The suite shape and examples are tied to the declared payment
retry scope rather than generated independently of the project. Validation is
performed against the repository's own MoonBit checks, portable tests, native
loopback tests and executable acceptance command; generated code is not treated
as evidence that a behavior works.

Design references include the problem classes addressed by Toxiproxy,
WireMock and MockServer. FaultCanvas does not copy their source or claim to
replace their broader protocol support. The implementation follows the
repository's Apache-2.0 license, and third-party dependencies are listed in
`THIRD_PARTY.md`.

## Lessons and next steps

Keeping decisions pure made sequence behavior easier to test, but it also
exposes the importance of clear boundaries between a deterministic simulation
and actual network behavior. The acceptance suite now makes that distinction
visible in its output and documentation. Future work should prioritize
bounded long-running session state, streaming body limits, and additional HTTP
transport edge cases before adding protocol breadth. TLS interception,
HTTP/2, gRPC and a web console require separate designs and are not claimed as
completed here.
