# FaultCanvas Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a runnable MoonBit HTTP fault proxy with deterministic stateful rules, a CLI, tests, CI, documentation, and Mooncakes metadata.

**Architecture:** Keep request matching, scenario transitions, fault planning, and reporting pure and backend-independent. A native adapter built on the official async library owns sockets and upstream HTTP I/O; the CLI wires configuration to the core runtime.

**Tech Stack:** MoonBit, moonbitlang/async, JSON configuration, GitHub Actions, Mooncakes.

---

### Task 1: Module scaffold and domain model

**Files:** `moon.mod.json`, `core/moon.pkg`, `core/model.mbt`, `core/model_test.mbt`

1. Initialize module `zkc-long/faultcanvas`.
2. Write tests for normalized requests, responses, actions, and validation limits.
3. Implement the minimal domain model.
4. Run `moon check` and `moon test`.
5. Commit the independently usable model.

### Task 2: Deterministic matcher

**Files:** `matcher/moon.pkg`, `matcher/matcher.mbt`, `matcher/matcher_test.mbt`

1. Test method, path, query, header, body and priority matching.
2. Implement matcher diagnostics and deterministic tie breaking.
3. Verify all tests and commit.

### Task 3: Stateful scenarios

**Files:** `scenario/moon.pkg`, `scenario/scenario.mbt`, `scenario/scenario_test.mbt`

1. Test hit counters, phases and guarded transitions.
2. Implement an in-memory state store with explicit reset.
3. Verify deterministic sequences and commit.

### Task 4: Fault action planner

**Files:** `fault/moon.pkg`, `fault/fault.mbt`, `fault/fault_test.mbt`

1. Test delay, abort, truncate, corrupt and status override validation.
2. Convert configured actions into an ordered execution plan.
3. Verify invalid combinations are rejected and commit.

### Task 5: Configuration codec

**Files:** `config/moon.pkg`, `config/config.mbt`, `config/config_test.mbt`, `examples/payment/faultcanvas.json`

1. Test versioned JSON decoding and semantic errors.
2. Implement defaults and validation.
3. Add a complete payment-service scenario and commit.

### Task 6: Runtime and reporting

**Files:** `runtime/moon.pkg`, `runtime/runtime.mbt`, `runtime/runtime_test.mbt`, `report/moon.pkg`, `report/report.mbt`

1. Test request-to-decision execution and journal entries.
2. Implement bounded event storage and redaction.
3. Produce stable text and JSON reports.
4. Verify and commit.

### Task 7: Native HTTP proxy

**Files:** `native/moon.pkg`, `native/server.mbt`, `native/server_test.mbt`

1. Add official async dependency.
2. Test with a loopback fake upstream.
3. Implement listener, passthrough, stub, delay and safe failure responses.
4. Verify body/time/event limits and commit.

### Task 8: CLI

**Files:** `cmd/faultcanvas/moon.pkg`, `cmd/faultcanvas/main.mbt`

1. Implement `check`, `serve`, `simulate` and `report`.
2. Use stable exit codes and machine-readable JSON.
3. Run smoke tests and commit.

### Task 9: Project quality and examples

**Files:** `README.md`, `README.mbt.md`, `docs/CONFIGURATION.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`

1. Document installation, boundaries, examples and competitor differences.
2. Add a 3–5 minute payment retry demo.
3. Verify every copied command and commit.

### Task 10: CI, release and publication readiness

**Files:** `.github/workflows/ci.yml`, `LICENSE`, `THIRD_PARTY.md`, `.gitignore`

1. Add format, check, build, test and demo gates.
2. Run the complete local gate.
3. Verify Mooncakes metadata and package docs.
4. Commit, create the public GitHub repository under `zkc-long`, push, and publish after authentication succeeds.

