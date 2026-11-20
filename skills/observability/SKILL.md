---
name: observability
description: Search Grafana metrics (Prometheus/Mimir, PromQL) and logs (Loki, LogQL) with the gcx CLI against a user-chosen gcx context, passed on every call as `gcx --context <ctx>`. Use when asked to look up, search, query, or investigate metrics, logs, errors, latency, or service health in Grafana, or when the user says "observability".
compatibility: Requires the gcx CLI (Grafana) with at least one configured context that has Prometheus and/or Loki datasources.
---

# observability

Search metrics and logs in Grafana with `gcx`. Every command targets one gcx context that the user picks.

## When to use

The user asks to find, query, or investigate metrics or logs (errors, latency, traffic, a service's health, an incident), or says "observability".

## Inputs

- `ctx` — the gcx context name. Required. Take it from the user's message (e.g. `/observability prod ...`).
- The question — what to find (service, signal, time range).

## Directives

- **Read-only. NEVER write.** Run only commands that read data: `list`, `get`, `query`, `labels`, `series`, `search`, `metadata`, `list-names`, `query-patterns`, `health`, `--help`, `config list-contexts`, `config view`.
- NEVER run commands that create, update, delete, apply, push, import, silence, acknowledge, or change config (e.g. `create`, `update`, `delete`, `apply`, `push`, `edit`, `set`, `unset`, `use-context`, `login`, `setup`, `api` with a non-GET method).
- If the user asks for a write, stop and tell them to run it themselves.

## Instructions

1. **Resolve the context.** If the user did not give `ctx`, run `gcx config list-contexts` and ask which one to use. Never fall back silently to the current context. Never run `gcx config use-context`.

2. **Pass `--context <ctx>` on every gcx call.** No exceptions, including discovery commands. Add `--agent` for JSON output.

3. **Find datasources.** Run `gcx --context <ctx> datasources list`. Note the Prometheus and Loki UIDs. Pass `-d <uid>` unless the context sets a default datasource.

4. **Discover before querying.** Do not guess metric or label names:

   ```bash
   gcx --context <ctx> metrics list-names -d <prom-uid>
   gcx --context <ctx> metrics labels -d <prom-uid>
   gcx --context <ctx> metrics series -d <prom-uid> '<selector>'
   gcx --context <ctx> logs labels -d <loki-uid>
   gcx --context <ctx> logs labels -d <loki-uid> --label <name>
   ```

5. **Query metrics** (PromQL). Always bound the time range:

   ```bash
   gcx --context <ctx> metrics query -d <prom-uid> '<promql>' --since 1h --step 1m
   ```

6. **Query logs** (LogQL). Start narrow with stream selectors, then add line filters:

   ```bash
   gcx --context <ctx> logs query -d <loki-uid> '{app="foo"} |= "error"' --since 1h
   gcx --context <ctx> logs query-patterns -d <loki-uid> '{app="foo"}' --since 1h
   gcx --context <ctx> logs metrics -d <loki-uid> 'sum by (level) (count_over_time({app="foo"}[5m]))' --since 6h
   ```

7. **Report** concisely: the context used, the queries run, key findings (numbers, top errors, time of change). Add `--share-link` to the decisive query and include the Grafana Explore URL.

## Edge cases

- **Unknown flags or subcommands:** run `gcx <command> --help`. For deeper incident workflows, `gcx agent skills get debug-with-grafana -otext`.
- **Empty results:** verify label values with discovery commands and widen `--since` before concluding there is no data.
- **Large log output:** keep the default `--limit` (50); prefer `query-patterns` or `logs metrics` aggregations over raising the limit.
- **Unsure if a command writes:** check `gcx <command> --help`; if still unclear, do not run it.
