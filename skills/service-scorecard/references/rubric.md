# Scorecard rubric

23 facets. Each is graded **A–F** and carries a weight used in the overall grade.

Points: **A=5, B=4, C=3, D=2, E=1, F=0**. Overall = `Σ(weight × points) / Σ(weight)`, N/A facets excluded from both sums. Letter thresholds: `≥4.5 A`, `≥3.5 B`, `≥2.5 C`, `≥1.5 D`, `≥0.5 E`, else `F`.

Weights encode the objective — maintenance and discoverability:

| Weight | Facets |
| --- | --- |
| **3** | logic duplication, layering depth, domain boundary clarity, naming consistency, repo navigability, maintenance effort |
| **2** | documentation rot, dead code, API completeness, API security, event contract quality, storage simplicity, service coupling, config & secrets, dependency health, test coverage & quality, local dev experience |
| **1** | API versioning, data model & migrations, deployment complexity, observability, error handling, performance shape |

Grade the middle bands by interpolating between the A and C anchors, and between C and F. B is "A with a named gap". D is "F with something working". E is "barely functional, actively costs the team".

Facets appear below in canonical order — use it for the report's summary grid.

---

## 1. Logic duplication — weight 3

**Measures:** the same decision or transformation implemented more than once.

**Signals:** near-identical function bodies across packages; validation repeated in handler and service; copy-pasted error mapping; parallel switch statements over the same enum; two clients for one downstream; helper functions redefined per package. Search for repeated distinctive string literals, repeated magic numbers, and sibling files with near-equal line counts.

**A:** shared logic lives in one obvious place and is reused; the few repetitions are deliberate and local (a test fixture, a hot path unrolled on purpose).
**C:** a handful of real duplications, each cheap to unify; nothing yet drifting.
**F:** the same rule exists in three-plus places and the copies already disagree — a fix in one does not fix the others.

**N/A:** never.

## 2. Layering depth — weight 3

**Measures:** how many hops a request takes from entrypoint to effect, and whether each hop earns its place.

**Signals:** count the distinct layers a single simple read traverses. Look for pass-through layers that only rename types (`dto → model → entity`), interfaces with exactly one implementation and one caller, and mappers whose whole job is field-for-field copying.

**A:** every layer changes the shape of the problem, not just the shape of the struct; a trivial endpoint touches 2–3 files and the reason for each is obvious.
**C:** one redundant layer or one mapper tier that could collapse; navigable but padded.
**F:** five-plus hops for a simple read, most of them pass-through; nobody can say what a layer is for without reading all of it.

**N/A:** never.

## 3. Domain boundary clarity — weight 3

**Measures:** whether the package/module layout maps to the domain or only to technical roles, and whether the boundaries hold.

**Signals:** top-level directories named for concepts (`billing/`, `ingest/`) versus roles (`services/`, `utils/`, `helpers/`, `common/`). Import direction — do domain packages import infrastructure, or the reverse? Grep for a `shared`/`common`/`util` package and measure how much of the codebase depends on it. Cross-domain reach-in: does `billing` import `ingest`'s internals?

**A:** directories name domain concepts, dependencies point inward, and a feature change lands mostly inside one directory.
**C:** technical layering at the top with domain packages beneath, or one leaky boundary; a feature change touches two or three directories predictably.
**F:** a `utils`/`common` grab bag everything depends on, no domain visible in the tree, and every change is a shotgun edit.

**N/A:** services under roughly 15 source files — say so rather than punishing smallness.

## 4. Naming consistency — weight 3

**Measures:** whether functions, methods, types, and files follow one predictable vocabulary.

**Signals:** competing verbs for one operation (`Get`/`Fetch`/`Load`/`Retrieve` in one package); competing suffixes for one role (`Service`/`Manager`/`Handler`/`Helper` doing identical work); abbreviations used inconsistently (`cfg` beside `config`, `usr` beside `user`); file names that do not match the type they hold; casing drift across sibling files; plural/singular churn on the same concept.

**A:** one verb per operation, one suffix per role, file names predict contents; a reader guesses the right name before finding it.
**C:** a dominant convention plus a legacy pocket that breaks it.
**F:** no convention survives across two files; finding code requires full-text search because nothing can be guessed.

**N/A:** never.

## 5. Repo navigability — weight 3

**Measures:** how fast a newcomer finds where things live and how to run them.

**Signals:** README — does it state what the service does, how to run it, and where the entrypoint is? Whether it is still *true* is facet 6; here, grade presence, structure, and findability. Presence of `docs/`, ADRs, runbooks. Obviousness of the entrypoint from the root listing. Root clutter (stray scripts, dead configs). Whether directory names need explanation.

**A:** README answers what/run/where in the first screen; entrypoint is obvious from `ls`; non-obvious decisions are recorded in ADRs or comments at the decision site.
**C:** README covers the basics but the tree needs explaining; a newcomer needs one conversation to get oriented.
**F:** no README or a generator stub, entrypoint unguessable, root full of undocumented scripts.

**N/A:** never.

## 6. Documentation rot — weight 2

**Measures:** whether the documentation that exists is still true. Facet 5 asks whether a newcomer can find their way; this facet asks whether what they find will mislead them. Confidently wrong documentation is worse than none, because it is believed.

**Signals:** verify rather than skim — every claim below is checkable.

- *Commands that no longer run.* Extract every command from the README and `docs/` and check the referenced binaries, scripts, and make targets exist. A `make dev` in the README with no `dev` target in the `Makefile` is a finding.
- *Paths that no longer exist.* Extract file and directory references from the docs and test each one. Broken relative links between markdown files count too.
- *Config drift.* Documented environment variables and `.env.example` keys against the keys the code actually reads — in both directions. Missing keys break a clean clone; documented-but-unread keys are ghosts a reader will try to set.
- *Contract drift.* Documented endpoints, events, or CLI flags against the ones actually registered.
- *Age against churn.* Compare the last commit date of the docs with that of the code they describe. Docs untouched for a year while their subject churns weekly are stale by default — check them first.
- *Superseded decisions.* ADRs marked accepted but contradicted by the current code; architecture diagrams describing a component that was replaced or removed.
- *Comments that lie.* Comments and docstrings describing behaviour the function no longer has — the ones on the largest and most-churned files are the likeliest offenders.
- *Contradiction.* The same thing documented in two places (README, `docs/`, a wiki link, code comments) with different answers, and no signal which is authoritative.
- *Abandoned artefacts.* A CHANGELOG that stopped mid-history, onboarding docs naming decommissioned services or tools, generated docs (OpenAPI, godoc, typedoc) committed once and never regenerated.

Useful checks, adapted to the repo:

```bash
git log -1 --format=%ad --date=short -- README.md docs/
git log -1 --format=%ad --date=short -- src/ internal/ app/
grep -rhoE '\]\(([^)h][^)]*)\)' README.md docs/ 2>/dev/null | tr -d '])(' | while read -r f; do [ -e "$f" ] || echo "broken link: $f"; done
grep -oE '^[A-Z_]+' .env.example 2>/dev/null | sort > /tmp/doc_env
git grep -hoE '(getenv|Getenv|env\.|process\.env\.)[("]?[A-Z_]+' | grep -oE '[A-Z_]{3,}' | sort -u > /tmp/code_env
comm -3 /tmp/doc_env /tmp/code_env
```

**A:** documentation is generated from or verified against the code (a CI check, a doc test, a lint on links), the documented setup works on a clean clone, and doc commits track the code changes that affect them.
**C:** the core instructions still work, but the edges have drifted — a stale path or two, a lapsed changelog, one diagram behind the current design. A newcomer succeeds with one correction.
**F:** the documented setup fails on a clean clone, documented config or endpoints do not exist, and the architecture described was replaced — the docs actively cost a newcomer more time than they save.

**N/A:** the repo contains no prose documentation at all. That absence is already graded in facet 5; say so in the report rather than grading this facet F for the same fault twice.

## 7. Dead code & unused surface — weight 2

**Measures:** code that ships but is never reached, and surface never removed.

**Signals:** exported symbols with no callers; commented-out blocks; `v1` handlers superseded by `v2` but still registered; feature flags permanently on or off with both branches retained; unused config keys; unreferenced files. Run the language's own detector when available (`go vet`/`staticcheck`, `ts-prune`/`knip`, `vulture`, `cargo +nightly udeps`) and note that you did.

**A:** no unreferenced exports, no commented-out blocks, retired flags and endpoints deleted rather than parked.
**C:** a few unused helpers and one stale flag; harmless but misleading.
**F:** whole directories nobody can confirm are live; readers must trace call graphs to know if code matters.

**N/A:** never.

## 8. API completeness — weight 2

**Measures:** whether the external contract is fully expressed, documented, and consistent.

**Signals:** OpenAPI/protobuf/GraphQL schema present and matching the implemented routes; every route's request and response validated and typed; error responses uniform (one envelope, documented codes) rather than per-handler; pagination/filtering/sorting present where collections are returned; correct status codes; documented content types. Asynchronous contracts are graded separately in facet 11 — keep this facet to the synchronous surface.

**A:** a schema exists, is generated from or verified against the code, covers every route including errors, and conventions are uniform across handlers.
**C:** routes documented but drifting from the code, or error shapes inconsistent between handlers.
**F:** no contract document, ad-hoc responses per endpoint, callers must read handler source to integrate.

**N/A:** no synchronous external contract — an event-only service grades facet 11 instead.

## 9. API security — weight 2

**Measures:** authentication and authorization on the request path.

**Signals:** where authn is applied — a middleware/interceptor covering the router, or per-handler and easy to omit? Grep every route registration and check which ones bypass the auth chain. Authorization distinct from authentication (is the caller allowed *this* resource, not just known?). Token validation done properly (signature, expiry, audience) versus decoded and trusted. Secrets in code or config. Input validation at the boundary. Rate limiting. TLS assumptions. Broker-side authn and payload authentication belong to facet 11.

**A:** authn enforced centrally with an explicit, short, reviewed allowlist of public routes; authz checked per resource; tokens fully validated; no secrets in the repo.
**C:** central authn but authz scattered through handlers, or a couple of routes whose exemption is undocumented.
**F:** per-handler auth that some handlers skip, tokens trusted without verification, or credentials committed to the repo.

**N/A:** service has no callable surface at all — rare; prefer grading.

## 10. API versioning & backward compatibility — weight 1

**Measures:** whether the contract can change without breaking callers.

**Signals:** a versioning strategy at all (path, header, schema-level); deprecation markers with dates or removal plans; additive-only change discipline visible in git history; contract or consumer-driven tests; whether removed fields were ever removed. Event schema evolution belongs to facet 11.

**A:** an explicit, documented strategy; deprecations dated and tracked; contract tests guard breaking changes.
**C:** versioned but by convention only; breaking changes are caught by review, not by tooling.
**F:** no version marker, fields removed or retyped in place, callers discover breaks in production.

**N/A:** no synchronous external contract, or a single known internal caller shipped in lockstep — state which.

## 11. Event contract quality — weight 2

**Measures:** whether the service's asynchronous contract — the events, commands, and messages it publishes or consumes — is explicit, discoverable, and safe to evolve. This is the async counterpart to facets 8–10; grade it with the same severity.

**Signals:**

- *Definition.* Payload schemas checked in (protobuf, Avro, JSON Schema, AsyncAPI) versus untyped maps or structs declared inline at the publish site. Is there one directory or registry where every event type lives, or must a reader grep the codebase to learn what this service emits?
- *Naming.* Events named as past-tense facts (`InvoiceIssued`) versus commands or CRUD echoes (`UpdateInvoice`, `invoice_changed`). Topic, queue, and subject names defined as constants in one place versus string literals scattered across publishers and consumers.
- *Envelope.* Message ID, type, schema version, timestamp, and correlation/causation IDs present, or a bare payload with no metadata.
- *Evolution.* A version marker and a stated compatibility rule (backward, forward, full); additive-only discipline visible in git history; a registry or CI check that rejects a breaking schema change; consumers tolerant of unknown fields.
- *Delivery semantics.* Documented at-least-once / at-most-once / exactly-once expectations; idempotency or deduplication on the consumer; ordering and partition-key assumptions stated rather than assumed; whether a redelivered message is safe.
- *Failure path.* Retry policy, dead-letter queue wired and monitored, poison-message handling, a documented replay or reprocessing path, ack/offset committed after successful work rather than on receipt.
- *Ownership.* Who produces each event and who consumes it, recorded somewhere a newcomer can find. Producer and consumer of the same event agreeing on the shape — check both sides when both live in this repo.
- *Payload shape.* Events carrying the data a consumer needs versus bare IDs that force a synchronous call back (which converts an async decoupling into a hidden sync dependency — cross-reference facet 19).

**A:** every published and consumed message has a checked-in schema in one discoverable place, past-tense fact naming, a versioned envelope with correlation IDs, an enforced compatibility rule, idempotent consumers, and a wired DLQ with a documented replay path.
**C:** schemas exist for the main events but live beside the publishers rather than in one place; versioning is by convention; retries and a DLQ exist but replay is manual; ordering and idempotency assumptions are implicit.
**F:** payloads built inline as untyped maps, topic names as scattered string literals, no version marker, no DLQ, consumers not idempotent — nobody can say what this service emits without reading every publish site, and no change is safe.

**N/A:** the service neither publishes nor consumes asynchronous messages. Using a queue purely as internal state — no external producer or consumer — is N/A here and belongs to facet 12.

## 12. Storage simplicity — weight 2

**Measures:** how much a reader must hold in their head to understand where state lives.

**Signals:** number of distinct stores (SQL, document, cache, blob, queue-as-state) and whether each earns its place; access patterns concentrated in a repository layer or scattered into handlers; ORM and raw SQL mixed in the same paths; N+1 shapes; transaction boundaries clear or implicit; caching layered without an invalidation story; the same entity persisted in two stores.

**A:** one primary store, access through one clear seam, transaction boundaries explicit, any second store has a stated reason.
**C:** two stores with a defensible split, some query logic leaking into handlers.
**F:** three-plus overlapping stores, duplicated entities, queries everywhere, no one seam to change.

**N/A:** stateless service.

## 13. Data model & migrations — weight 1

**Measures:** discipline around schema change.

**Signals:** migrations checked in, versioned, ordered, and applied by a tool rather than by hand; reversibility (down migrations or a documented forward-fix policy); whether the model in code matches the latest migration; destructive migrations without a backfill; ad-hoc `ALTER` statements in scripts or runbooks; seed data for local development.

**A:** every schema change is a checked-in, ordered, tool-applied migration; the code model provably matches; destructive changes are staged.
**C:** migrations exist and are checked in, but reversibility is inconsistent or some drift is visible.
**F:** no migration tooling, or schema changed by hand in each environment.

**N/A:** no schema-bearing store.

## 14. Deployment complexity — weight 1

**Measures:** how much machinery stands between a merge and a running instance. Lower is better; this facet grades *simplicity*.

**Signals:** count the artifacts — Dockerfile stages, Kubernetes manifests, Helm charts and their values files, Terraform modules, CI deploy stages, environment overlays. Look for duplication across environment configs, hand-maintained YAML that could be templated, manual steps in a runbook, and how many places a new env var must be added.

**A:** one image, one templated deployment definition, environments differing only by values; a new config value is added in one place; deploy is one automated step.
**C:** several manifests with some copy-paste across environments; deployment understandable in an afternoon.
**F:** dozens of divergent manifests, unclear which are live, manual steps, and a new env var must be added in five files.

**N/A:** no deployment definition in the repo — note where it lives instead.

## 15. Observability — weight 1

**Measures:** whether a failure in production can be diagnosed from telemetry alone.

**Signals:** structured logging with consistent levels and correlation/request IDs versus bare `print`/`fmt.Println`; metrics on the paths that matter (request rate, error rate, latency, queue depth, downstream calls) rather than only a default exporter; tracing with context propagated across service boundaries; health and readiness endpoints; whether errors carry enough context to identify the failing request; dashboards or alert definitions checked in.

**A:** structured logs with correlation IDs, RED-style metrics on entry points and downstream calls, traces propagated end to end, health checks present.
**C:** two of the three pillars present, or all three present but inconsistently applied across handlers.
**F:** unstructured prints, no metrics, no request correlation — diagnosis means reproducing locally.

**N/A:** never.

## 16. Config & secrets management — weight 2

**Measures:** how configuration enters the process, and whether secrets stay out of the repo.

**Signals:** config read in one place and passed down, versus `os.Getenv` scattered through the code; required values validated at startup with a clear failure, versus discovered at first use; defaults sane and documented; `.env.example` or equivalent present and current; committed secrets (grep for key-shaped literals, `.pem`, `.p12`, credentials in compose files or CI config); secret injection mechanism at deploy time.

**A:** one typed config struct loaded and validated at startup, documented defaults, no secrets in the repo, injection documented.
**C:** mostly centralized with a few direct env reads; example file slightly stale.
**F:** env vars read at point of use throughout, no validation, and credentials committed.

**N/A:** never.

## 17. Error handling & resilience — weight 1

**Measures:** what happens when something downstream fails.

**Signals:** swallowed errors (`catch {}`, `_ = err`, bare `except: pass`); `panic`/`unwrap`/`!` on recoverable paths; timeouts and deadlines on every outbound call, or defaults left unbounded; retries with backoff and idempotency versus tight retry loops or none; context/cancellation propagated; error wrapping that preserves cause and adds location; a boundary that converts internal errors to safe external responses without leaking internals.

**A:** errors wrapped with context and handled at one boundary, every outbound call bounded by a timeout, retries deliberate and idempotent.
**C:** consistent error handling in the main paths, gaps at the edges — a few unbounded calls or swallowed errors.
**F:** errors dropped or panicked on, no timeouts, internal detail leaking to callers.

**N/A:** never.

## 18. Performance & resource shape — weight 1

**Measures:** obvious structural performance hazards, not micro-optimization.

**Signals:** N+1 queries; unbounded reads (`SELECT` with no limit, loading a whole table or file into memory); missing pagination on collection endpoints; work done per request that could be cached or precomputed; unbounded goroutines/threads/promises; missing connection pooling; large synchronous work on the request path that belongs in a queue.

**A:** queries bounded and paginated, no N+1 shapes, expensive work moved off the request path, pools configured.
**C:** one or two unbounded paths on low-traffic endpoints; nothing yet load-bearing.
**F:** N+1s on the hot path, unbounded loads, no pagination — the service is one traffic increase from failing.

**N/A:** never, but say plainly when the assessment is structural rather than measured.

## 19. Service coupling — weight 2

**Measures:** how tightly this service is bound to others.

**Signals:** count distinct outbound service dependencies; synchronous versus asynchronous calls; fan-out inside a single request; shared database with another service (the strongest coupling there is); shared library carrying domain types across service boundaries; whether downstream failure degrades gracefully or fails the request; circular call patterns.

**A:** few dependencies, each behind a named client, failures degrade gracefully, no shared database or shared domain types.
**C:** several synchronous dependencies with clear clients; one request fan-out that hurts availability.
**F:** shared database or shared domain library with other services, deep synchronous chains, no isolation from downstream failure.

**N/A:** genuinely standalone service with no outbound dependencies.

## 20. Dependency health — weight 2

**Measures:** the cost carried by third-party code.

**Signals:** direct dependency count against the service's size; lockfile present and committed; versions pinned or floating; abandoned or archived packages; two libraries doing the same job (two HTTP clients, two loggers, two JSON codecs); a heavyweight framework used for a fraction of its surface; known-vulnerable versions if a scanner is available; how far behind the current majors the tree sits.

**A:** a small, pinned, current dependency set with one library per job and a committed lockfile.
**C:** current enough, one redundant pair or one dependency a major behind.
**F:** many overlapping or abandoned dependencies, no lockfile, versions years stale.

**N/A:** never.

## 21. Test coverage & quality — weight 2

**Measures:** whether tests let someone change the code with confidence.

**Signals:** test files against source files, and whether the critical paths are among the tested ones; the balance of unit, integration, and contract tests; assertions that check behaviour versus tests that only exercise code; skipped, commented-out, or sleep-based tests; fixture and helper duplication; whether tests run without external services, and how fast; a coverage report if one exists — cite the number, do not invent one.

**A:** critical paths covered at the level that matters, tests fast and deterministic, failures name the broken behaviour.
**C:** meaningful coverage of the core with edges untested, or a suite that needs external services to run.
**F:** no tests, or tests that assert nothing and pass regardless.

**N/A:** never — absence is an F.

## 22. Local dev experience — weight 2

**Measures:** time from clone to a running, exercisable service.

**Signals:** a single documented command (`make dev`, `docker compose up`, `npm run dev`) versus a multi-step README; dependencies stubbed or containerized versus requiring cloud access or VPN; seed data; hot reload; whether the documented steps actually match the files present; a devcontainer or Nix/asdf/mise pin for toolchain versions.

**A:** clone, one command, working service with seeded data and no external credentials.
**C:** a handful of documented steps that work, or one dependency needing real credentials.
**F:** no documented path; getting it running is tribal knowledge.

**N/A:** never.

## 23. Maintenance effort — weight 3

This facet is the synthesis; grade it last, after all others.

**Measures:** the ongoing human cost of keeping this service alive.

**Signals:** `TODO`/`FIXME`/`HACK` density; churn hotspots (`git log --format= --name-only | sort | uniq -c | sort -rn | head -20`) — files changed constantly are where the cost is; commit history shape (revert frequency, hotfix patterns); the largest files and functions; workarounds pinned to specific dependency versions; anything requiring manual periodic action (cert rotation, hand-run scripts, data cleanup); bus-factor signals from `git shortlog -sn`.

**A:** low churn concentration, few markers, no manual recurring toil, changes stay local.
**C:** a couple of hotspots and a known workaround or two; predictable but not free.
**F:** high churn on huge files, dense markers, recurring manual toil, and every change risks a regression elsewhere.

**N/A:** never.
