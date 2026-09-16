# 3–5 minute demo script

1. Show the payment configuration and point out `initial_phase: degraded`, the
   `on_hit: 2` transition, and the separate healthy passthrough rule.
2. Run `faultcanvas check examples/payment/faultcanvas.json` to show that the
   scenario is validated before any port is opened.
3. Run `faultcanvas simulate examples/payment/faultcanvas.json POST /payments`.
   Explain that the selected rule is deterministic and produces a delayed 503.
4. Start a tiny upstream on port 9000 and run `faultcanvas serve
   examples/payment/faultcanvas.json`.
5. Send three `POST /payments` requests with the same `X-Checkout-Id` header.
   The first two receive the injected failure; the third reaches the real
   upstream. Repeat with a new header value to prove session isolation.
6. Display the text or JSON journal to show rule ID, phase transition, outcome
   and elapsed time.
7. Run `faultcanvas stats examples/payment/faultcanvas.json POST /payments` to
   show deterministic response counts and p50/p95 latency summaries. Run
   `faultcanvas redact examples/payment/faultcanvas.json "token=demo"` to show
   that sensitive free-form details are replaced before reporting.

The key judging point is that this is not an in-process mock: the client talks
to a real HTTP listener while FaultCanvas applies a stateful fault policy.
