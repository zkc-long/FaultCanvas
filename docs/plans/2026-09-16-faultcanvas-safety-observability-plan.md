# FaultCanvas Safety and Observability Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand FaultCanvas with integrated safety policy and operational observability while keeping deterministic core behavior and taking the project above 3000 meaningful lines.

**Architecture:** Add a pure `policy` package for limits, header classification, redaction and response filtering. Add a pure `observe` package for bounded event querying and latency/error summaries. Extend configuration and report serialization, then wire policy checks and summaries into the native adapter and CLI. No policy code will depend on sockets; no observer will retain raw secrets.

**Tech Stack:** MoonBit, MoonBit core JSON, `moonbitlang/async` native adapter, existing `core/config/runtime/report` packages.

---

### Task 1: Safety policy domain

**Files:** `policy/moon.pkg`, `policy/policy.mbt`, `policy/policy_test.mbt`

Implement default limits, loopback validation, case-insensitive sensitive-header classification, redaction, request body/header validation, response-body truncation and safe response-header filtering. Test defaults, custom limits, redaction and rejection paths.

### Task 2: Configuration integration

**Files:** `config/config.mbt`, `config/config_test.mbt`, `examples/payment/faultcanvas.json`

Add optional `limits` and `security` objects with safe defaults. Reject invalid values atomically and expose the resulting `Policy` on `Config`. Extend the payment example.

### Task 3: Observability summary

**Files:** `observe/moon.pkg`, `observe/observe.mbt`, `observe/observe_test.mbt`

Implement event predicates, bounded selection, status/error counters, total/average/max latency and deterministic percentile buckets. Keep the API independent of report storage internals.

### Task 4: Report and native integration

**Files:** `report/report.mbt`, `report/report_test.mbt`, `runtime/runtime.mbt`, `native/server.mbt`

Add redacted event views and summary JSON. Enforce policy before decision execution, cap upstream response bodies, filter response headers, and record policy failures as 400/502 outcomes.

### Task 5: CLI, documentation and verification

**Files:** `cmd/main/main.mbt`, `README.md`, `docs/CONFIGURATION.md`, `docs/DEMO.md`, `.github/workflows/ci.yml`

Add `stats`/`redact` simulation commands, document policy and observability, extend the demo, run portable/native checks and confirm total tracked source exceeds 3000 lines.

### Task 6: Commits and remote validation

Commit each task independently, push to `zkc-long/FaultCanvas`, and verify GitHub Actions portable tests, native loopback tests and package listing.
