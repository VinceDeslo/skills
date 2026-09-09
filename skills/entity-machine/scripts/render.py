#!/usr/bin/env python3
import html
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ACTORS = ("user", "agent", "process", "external")
KEY_PATTERN = re.compile(r"^T\d+$")
LOCATION_PATTERN = re.compile(r"^[^\s:]+(:\d+(-\d+)?(,\s*\d+(-\d+)?)*)?$")

NODE_HEIGHT = 38
NODE_MIN_WIDTH = 96
NODE_CHAR_WIDTH = 7.5
NODE_PADDING = 30
ROW_PITCH = 130
COL_GAP = 120
CANVAS_PADDING = 40
PILL_CHAR_WIDTH = 6.6
PILL_HEIGHT = 20
BEND_STEP = 60
ANY_STATE = "*"


def fail(errors):
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    sys.exit(1)


def validate(spec):
    errors = []
    for field in ("entity", "summary", "states", "machines"):
        if field not in spec:
            errors.append(f"missing top-level field '{field}'")
    if errors:
        return errors

    state_ids = []
    initial_count = 0
    for index, state in enumerate(spec["states"]):
        for field in ("id", "meaning"):
            if not state.get(field):
                errors.append(f"states[{index}] missing '{field}'")
        state_ids.append(state.get("id"))
        initial_count += 1 if state.get("initial") else 0
    if len(set(state_ids)) != len(state_ids):
        errors.append("duplicate state ids")
    if initial_count == 0:
        errors.append("no state is marked initial")
    known_states = set(state_ids)

    actors = spec.get("actors", {})
    for actor in actors:
        if actor not in ACTORS:
            errors.append(f"unknown actor '{actor}', allowed: {', '.join(ACTORS)}")

    all_keys = []
    covered_states = set()
    for machine_index, machine in enumerate(spec["machines"]):
        label = f"machines[{machine_index}]"
        for field in ("title", "summary", "layout", "edges"):
            if field not in machine:
                errors.append(f"{label} missing '{field}'")
        if "layout" not in machine or "edges" not in machine:
            continue
        layout = machine["layout"]
        for state_id, cell in layout.items():
            if state_id != ANY_STATE and state_id not in known_states:
                errors.append(f"{label}.layout places unknown state '{state_id}'")
            if not (isinstance(cell, list) and len(cell) == 2 and all(isinstance(v, int) for v in cell)):
                errors.append(f"{label}.layout['{state_id}'] must be [col, row] integers")
        cells = [tuple(c) for c in layout.values() if isinstance(c, list)]
        if len(set(cells)) != len(cells):
            errors.append(f"{label}.layout has two states in the same cell")
        if not machine["edges"]:
            errors.append(f"{label} has no edges")
        for edge_index, edge in enumerate(machine["edges"]):
            edge_label = f"{label}.edges[{edge_index}]"
            key = edge.get("key", "")
            if not KEY_PATTERN.match(str(key)):
                errors.append(f"{edge_label} key '{key}' must look like T7")
            all_keys.append(key)
            sources = edge.get("from")
            sources = [sources] if isinstance(sources, str) else sources
            if not sources:
                errors.append(f"{edge_label} ({key}) missing 'from'")
                sources = []
            target = edge.get("to")
            if not target:
                errors.append(f"{edge_label} ({key}) missing 'to'")
            for state_id in list(sources) + ([target] if target else []):
                if state_id not in layout:
                    errors.append(f"{edge_label} ({key}) uses '{state_id}' which is not in this machine's layout")
                if state_id != ANY_STATE:
                    covered_states.add(state_id)
            if edge.get("actor") not in ACTORS:
                errors.append(f"{edge_label} ({key}) actor must be one of {', '.join(ACTORS)}")
            if edge.get("actor") and edge["actor"] not in actors:
                errors.append(f"{edge_label} ({key}) uses actor '{edge['actor']}' missing from top-level 'actors'")
            for field in ("trigger", "event"):
                if not edge.get(field):
                    errors.append(f"{edge_label} ({key}) missing '{field}'")
            locations = edge.get("locations") or []
            if not locations:
                errors.append(f"{edge_label} ({key}) has no locations; every edge must cite code")
            for location in locations:
                if not LOCATION_PATTERN.match(location):
                    errors.append(f"{edge_label} ({key}) location '{location}' must be path or path:line[-line]")
            if "bend" in edge and not isinstance(edge["bend"], (int, float)):
                errors.append(f"{edge_label} ({key}) bend must be a number")
            if "labelAt" in edge and not (0.15 <= float(edge["labelAt"]) <= 0.85):
                errors.append(f"{edge_label} ({key}) labelAt must be between 0.15 and 0.85")

    if len(set(all_keys)) != len(all_keys):
        errors.append("edge keys must be unique across all machines")
    numbers = sorted(int(k[1:]) for k in all_keys if KEY_PATTERN.match(str(k)))
    if numbers and numbers != list(range(1, len(numbers) + 1)):
        errors.append(f"edge keys must run T1..T{len(numbers)} without gaps, got {', '.join('T%d' % n for n in numbers)}")
    orphans = known_states - covered_states
    if orphans:
        errors.append(f"states never used by any edge: {', '.join(sorted(orphans))}; add an edge or drop the state with a caveat")
    return errors


def escape(text):
    return html.escape(str(text), quote=True)


def rich(text):
    if text is None or text == "":
        return "–"
    parts = str(text).split("`")
    out = []
    for index, part in enumerate(parts):
        piece = escape(part)
        out.append(f"<code>{piece}</code>" if index % 2 else piece)
    return "".join(out)


def node_width(state_id):
    text = "any state" if state_id == ANY_STATE else state_id
    return max(NODE_MIN_WIDTH, int(len(text) * NODE_CHAR_WIDTH) + NODE_PADDING)


def rect_anchor(node, toward):
    cx, cy, w, h = node["cx"], node["cy"], node["w"], node["h"]
    dx, dy = toward[0] - cx, toward[1] - cy
    if abs(dx) < 1e-6 and abs(dy) < 1e-6:
        return cx, cy - h / 2
    scale_x = (w / 2 + 2) / abs(dx) if dx else math.inf
    scale_y = (h / 2 + 2) / abs(dy) if dy else math.inf
    scale = min(scale_x, scale_y)
    return cx + dx * scale, cy + dy * scale


def quad_point(a, c, b, t):
    mt = 1 - t
    return (mt * mt * a[0] + 2 * mt * t * c[0] + t * t * b[0], mt * mt * a[1] + 2 * mt * t * c[1] + t * t * b[1])


def build_segments(machine):
    segments = []
    for edge in machine["edges"]:
        sources = edge["from"]
        sources = [sources] if isinstance(sources, str) else sources
        for source in sources:
            segments.append({"edge": edge, "from": source, "to": edge["to"]})
    groups = {}
    for segment in segments:
        if segment["from"] == segment["to"]:
            continue
        pair = tuple(sorted((segment["from"], segment["to"])))
        groups.setdefault(pair, []).append(segment)
    for pair, group in groups.items():
        forward = [s for s in group if (s["from"], s["to"]) == pair]
        backward = [s for s in group if (s["from"], s["to"]) != pair]
        if forward and backward:
            for index, segment in enumerate(forward):
                segment["offset"] = BEND_STEP * (index + 1)
            for index, segment in enumerate(backward):
                segment["offset"] = -BEND_STEP * (index + 1)
        else:
            for index, segment in enumerate(group):
                magnitude = BEND_STEP * ((index + 1) // 2)
                segment["offset"] = magnitude if index % 2 else -magnitude
        for segment in group:
            segment["pair"] = pair
    for segment in segments:
        bend = segment["edge"].get("bend")
        if bend is not None:
            segment["offset"] = float(bend)
    return segments


def rects_overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def segment_hits_rect(start, control, end, rect):
    for step in range(1, 20):
        x, y = quad_point(start, control, end, step / 20)
        if rect[0] < x < rect[2] and rect[1] < y < rect[3]:
            return True
    return False


def layout_warnings(machine, nodes, pills, routes):
    warnings = []
    node_rects = {
        state_id: (n["cx"] - n["w"] / 2, n["cy"] - n["h"] / 2, n["cx"] + n["w"] / 2, n["cy"] + n["h"] / 2)
        for state_id, n in nodes.items()
    }
    for key, pill in pills:
        for state_id, rect in node_rects.items():
            if rects_overlap(pill, rect):
                warnings.append(f"{machine['title']}: label {key} overlaps state '{state_id}'; set \"bend\" or \"labelAt\" on that edge or move the state")
    for (key, source, target), (start, control, end) in routes:
        for state_id, rect in node_rects.items():
            if state_id in (source, target):
                continue
            if segment_hits_rect(start, control, end, rect):
                warnings.append(f"{machine['title']}: edge {key} ({source} → {target}) passes through state '{state_id}'; set \"bend\" on that edge or move the state")
    seen = {}
    for key_a, pill_a in pills:
        for key_b, pill_b in pills:
            if key_a >= key_b or (key_a, key_b) in seen:
                continue
            seen[(key_a, key_b)] = True
            if rects_overlap(pill_a, pill_b):
                warnings.append(f"{machine['title']}: labels {key_a} and {key_b} overlap; set \"labelAt\" on one of them")
    return warnings


def render_machine_svg(machine, states_by_id, machine_index):
    layout = machine["layout"]
    widths = [node_width(s) for s in layout]
    col_pitch = max(widths) + COL_GAP
    nodes = {}
    for state_id, (col, row) in layout.items():
        w = node_width(state_id)
        nodes[state_id] = {
            "id": state_id,
            "w": w,
            "h": NODE_HEIGHT,
            "cx": CANVAS_PADDING + col * col_pitch + col_pitch / 2,
            "cy": CANVAS_PADDING + row * ROW_PITCH + ROW_PITCH / 2,
        }

    segments = build_segments(machine)
    points = []
    pills = []
    routes = []
    edge_markup = []
    for segment in segments:
        edge = segment["edge"]
        key = edge["key"]
        actor = edge["actor"]
        flag = edge.get("flag")
        classes = f"seg {actor}" + (" flagged" if flag else "")
        marker = f"arrow-{'flag' if flag else actor}"
        a_node, b_node = nodes[segment["from"]], nodes[segment["to"]]
        label_at = float(edge.get("labelAt", 0.5))
        if segment["from"] == segment["to"]:
            top = a_node["cy"] - a_node["h"] / 2
            start = (a_node["cx"] - 18, top)
            end = (a_node["cx"] + 18, top)
            c1 = (a_node["cx"] - 55, top - 70)
            c2 = (a_node["cx"] + 55, top - 70)
            path = f"M{start[0]:.1f} {start[1]:.1f} C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {end[0]:.1f} {end[1]:.1f}"
            label_point = (a_node["cx"], top - 52)
            points += [c1, c2]
        else:
            pair = segment["pair"]
            p_node, q_node = nodes[pair[0]], nodes[pair[1]]
            dx, dy = q_node["cx"] - p_node["cx"], q_node["cy"] - p_node["cy"]
            length = math.hypot(dx, dy) or 1
            normal = (-dy / length, dx / length)
            mid = ((a_node["cx"] + b_node["cx"]) / 2, (a_node["cy"] + b_node["cy"]) / 2)
            offset = segment.get("offset", 0)
            control = (mid[0] + normal[0] * offset, mid[1] + normal[1] * offset)
            start = rect_anchor(a_node, control if offset else (b_node["cx"], b_node["cy"]))
            end = rect_anchor(b_node, control if offset else (a_node["cx"], a_node["cy"]))
            path = f"M{start[0]:.1f} {start[1]:.1f} Q{control[0]:.1f} {control[1]:.1f} {end[0]:.1f} {end[1]:.1f}"
            label_point = quad_point(start, control, end, label_at)
            points.append(control)
            routes.append(((key, segment["from"], segment["to"]), (start, control, end)))
        label_text = key + (f" · {flag}" if flag else "")
        pill_w = int(len(label_text) * PILL_CHAR_WIDTH) + 14
        pill_x, pill_y = label_point[0] - pill_w / 2, label_point[1] - PILL_HEIGHT / 2
        points += [(pill_x, pill_y), (pill_x + pill_w, pill_y + PILL_HEIGHT)]
        pills.append((key, (pill_x, pill_y, pill_x + pill_w, pill_y + PILL_HEIGHT)))
        edge_markup.append(
            f'<g class="{classes}" data-edge="{escape(key)}" tabindex="0" role="link" aria-label="{escape(key)} {escape(segment["from"])} to {escape(segment["to"])}">'
            f'<path class="hit" d="{path}"/>'
            f'<path class="line" d="{path}" marker-end="url(#{marker}-{machine_index})"/>'
            f'<rect class="pill" x="{pill_x:.1f}" y="{pill_y:.1f}" width="{pill_w}" height="{PILL_HEIGHT}" rx="4"/>'
            f'<text class="pill-text" x="{label_point[0]:.1f}" y="{label_point[1] + 4:.1f}" text-anchor="middle">{escape(label_text)}</text>'
            "</g>"
        )

    node_markup = []
    for state_id, node in nodes.items():
        state = states_by_id.get(state_id, {})
        x, y = node["cx"] - node["w"] / 2, node["cy"] - node["h"] / 2
        points += [(x, y), (x + node["w"], y + node["h"])]
        if state_id == ANY_STATE:
            node_markup.append(
                f'<g class="node any"><rect x="{x:.1f}" y="{y:.1f}" width="{node["w"]}" height="{node["h"]}" rx="19"/>'
                f'<text x="{node["cx"]:.1f}" y="{node["cy"] + 4.5:.1f}" text-anchor="middle">any state</text></g>'
            )
            continue
        classes = "node" + (" initial" if state.get("initial") else "") + (" terminal" if state.get("terminal") else "")
        extra = ""
        if state.get("terminal"):
            extra = f'<rect class="inner" x="{x + 3:.1f}" y="{y + 3:.1f}" width="{node["w"] - 6}" height="{node["h"] - 6}" rx="6"/>'
        if state.get("initial"):
            sx = x - 34
            points.append((sx - 6, node["cy"]))
            extra += (
                f'<circle class="start" cx="{sx:.1f}" cy="{node["cy"]:.1f}" r="5"/>'
                f'<path class="start-arrow" d="M{sx + 5:.1f} {node["cy"]:.1f} L{x - 3:.1f} {node["cy"]:.1f}" marker-end="url(#arrow-start-{machine_index})"/>'
            )
        node_markup.append(
            f'<g class="{classes}" data-state="{escape(state_id)}">'
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{node["w"]}" height="{node["h"]}" rx="8"/>{extra}'
            f'<text x="{node["cx"]:.1f}" y="{node["cy"] + 4.5:.1f}" text-anchor="middle">{escape(state_id)}</text></g>'
        )

    min_x = min(p[0] for p in points) - 24
    min_y = min(p[1] for p in points) - 24
    max_x = max(p[0] for p in points) + 24
    max_y = max(p[1] for p in points) + 24
    width, height = max_x - min_x, max_y - min_y
    markers = "".join(
        f'<marker id="arrow-{name}-{machine_index}" class="marker {name}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z"/></marker>'
        for name in ACTORS + ("flag", "start")
    )
    markup = (
        f'<svg class="machine-svg" viewBox="{min_x:.0f} {min_y:.0f} {width:.0f} {height:.0f}" width="100%" '
        f'style="max-height:{min(height, 900):.0f}px" role="img" aria-label="{escape(machine["title"])} state machine">'
        f"<defs>{markers}</defs>{''.join(edge_markup)}{''.join(node_markup)}</svg>"
    )
    return markup, layout_warnings(machine, nodes, pills, routes)


def render_legend(machine, actors):
    used_actors = sorted({e["actor"] for e in machine["edges"]}, key=ACTORS.index)
    items = []
    for actor in used_actors:
        items.append(
            f'<span class="legend-item"><svg width="34" height="10" aria-hidden="true"><line class="seg {actor}" x1="1" y1="5" x2="33" y2="5"/></svg>'
            f'<b>{escape(actor.capitalize())}</b>: {rich(actors.get(actor, ""))}</span>'
        )
    flags = sorted({e["flag"] for e in machine["edges"] if e.get("flag")})
    for flag in flags:
        items.append(
            f'<span class="legend-item"><svg width="34" height="10" aria-hidden="true"><line class="seg flagged" x1="1" y1="5" x2="33" y2="5"/></svg>'
            f'<b class="flag-label">{escape(flag)}</b></span>'
        )
    return f'<div class="legend">{"".join(items)}</div>'


def format_transition(edge):
    sources = edge["from"]
    sources = [sources] if isinstance(sources, str) else sources
    source_text = ", ".join("any state" if s == ANY_STATE else s for s in sources)
    return f'<span class="state">{escape(source_text)}</span> → <span class="state">{escape(edge["to"])}</span>'


def render_table(machine):
    rows = []
    for edge in machine["edges"]:
        flag = edge.get("flag")
        flag_markup = f' <span class="flag-badge">{escape(flag)}</span>' if flag else ""
        locations = " · ".join(f"<code>{escape(loc)}</code>" for loc in edge.get("locations", []))
        note = f'<div class="note">{rich(edge["note"])}</div>' if edge.get("note") else ""
        rows.append(
            f'<tr data-edge="{escape(edge["key"])}" id="edge-{escape(edge["key"])}" class="{"flagged" if flag else ""}">'
            f'<td class="key"><span class="key-pill">{escape(edge["key"])}</span></td>'
            f'<td><span class="actor {edge["actor"]}">{escape(edge["actor"])}</span></td>'
            f'<td class="transition">{format_transition(edge)}{flag_markup}</td>'
            f'<td>{rich(edge["trigger"])}{note}</td>'
            f'<td>{rich(edge.get("guard"))}</td>'
            f'<td>{rich(edge["event"])}</td>'
            f'<td class="path">{locations}</td></tr>'
        )
    return (
        '<div class="table-wrap"><table><thead><tr><th>Edge</th><th>Actor</th><th>Transition</th>'
        "<th>Trigger</th><th>Guard</th><th>Event</th><th>Location</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table></div>"
    )


def render_states(spec):
    rows = []
    for state in spec["states"]:
        kinds = []
        if state.get("initial"):
            kinds.append('<span class="kind initial">initial</span>')
        if state.get("terminal"):
            kinds.append('<span class="kind terminal">terminal</span>')
        declared = f'<code>{escape(state["declared"])}</code>' if state.get("declared") else "–"
        rows.append(
            f'<tr><td class="state-cell"><span class="state">{escape(state["id"])}</span> {"".join(kinds)}</td>'
            f'<td>{rich(state["meaning"])}</td><td class="path">{declared}</td></tr>'
        )
    return (
        '<div class="table-wrap"><table class="states"><thead><tr><th>State</th><th>Represents</th><th>Declared</th></tr></thead>'
        f"<tbody>{''.join(rows)}</tbody></table></div>"
    )


def render_stats(spec):
    edges = [e for m in spec["machines"] for e in m["edges"]]
    flagged = [e for e in edges if e.get("flag")]
    locations = {loc for e in edges for loc in e.get("locations", [])}
    stats = [
        ("States", str(len(spec["states"]))),
        ("Edges", str(len(edges))),
        ("Diagrams", str(len(spec["machines"]))),
        ("Writers cited", str(len(locations))),
        ("Flagged edges", str(len(flagged))),
    ]
    return "".join(f'<div class="stat"><div class="k">{k}</div><div class="v">{v}</div></div>' for k, v in stats)


def render_machines(spec):
    states_by_id = {s["id"]: s for s in spec["states"]}
    actors = spec.get("actors", {})
    sections = []
    warnings = []
    for index, machine in enumerate(spec["machines"]):
        note = f'<p class="machine-note">{rich(machine["note"])}</p>' if machine.get("note") else ""
        svg, machine_warnings = render_machine_svg(machine, states_by_id, index)
        warnings += machine_warnings
        sections.append(
            f'<section class="machine" id="machine-{index}">'
            f'<h2 class="section">{escape(machine["title"])} <span class="count">{len(machine["edges"])} edges</span></h2>'
            f'<p class="machine-summary">{rich(machine["summary"])}</p>'
            f'<figure class="card diagram">{render_legend(machine, actors)}{svg}{note}</figure>'
            f'<div class="card">{render_table(machine)}</div></section>'
        )
    return "".join(sections), warnings


def render_method(spec):
    method = spec.get("method")
    caveats = spec.get("caveats") or []
    if not method and not caveats:
        return ""
    caveat_markup = "".join(f"<li>{rich(c)}</li>" for c in caveats)
    caveat_block = f'<span class="label">Caveats</span><ul>{caveat_markup}</ul>' if caveats else ""
    method_block = f'<span class="label">How the edges were found</span><p>{rich(method)}</p>' if method else ""
    return (
        '<details class="card fold"><summary>Methodology</summary>'
        f'<div class="body">{method_block}{caveat_block}</div></details>'
    )


def render_meta(spec):
    items = []
    if spec.get("repo"):
        items.append(f'<span>repo <code>{escape(spec["repo"])}</code></span>')
    if spec.get("definition"):
        items.append(f'<span>defined at <code>{escape(spec["definition"])}</code></span>')
    if spec.get("commit"):
        items.append(f'<span>at <code>{escape(spec["commit"])}</code></span>')
    items.append(f'<span>generated {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}</span>')
    return "".join(items)


def render(spec, template):
    machines_markup, warnings = render_machines(spec)
    replacements = {
        "{{ENTITY}}": escape(spec["entity"]),
        "{{SUMMARY}}": rich(spec["summary"]),
        "{{META}}": render_meta(spec),
        "{{STATS}}": render_stats(spec),
        "{{STATES}}": render_states(spec),
        "{{MACHINES}}": machines_markup,
        "{{METHOD}}": render_method(spec),
    }
    output = template
    for token, value in replacements.items():
        output = output.replace(token, value)
    leftover = re.findall(r"\{\{[A-Z_]+\}\}", output)
    if leftover:
        fail([f"unfilled template token {token}" for token in sorted(set(leftover))])
    return output, warnings


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print("usage: render.py <spec.json> [--check] [--template <path>] [--out <path>]", file=sys.stderr)
        return 2
    spec_path = Path(argv[1])
    spec = json.loads(spec_path.read_text())
    errors = validate(spec)
    if errors:
        fail(errors)
    template_path = Path(argv[argv.index("--template") + 1]) if "--template" in argv else Path(__file__).resolve().parent.parent / "assets" / "machine-template.html"
    template = template_path.read_text()
    output, warnings = render(spec, template)
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if "--check" in argv:
        edges = sum(len(m["edges"]) for m in spec["machines"])
        print(f"ok: {len(spec['states'])} states, {edges} edges, {len(spec['machines'])} machines, {len(warnings)} layout warnings")
        return 0
    if "--out" in argv:
        out_path = Path(argv[argv.index("--out") + 1])
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output)
        print(out_path)
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
