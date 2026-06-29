# System Inventory & Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a code-verified inventory of every runtime system/subsystem — graded on whether the simulation closes its loops, with a derived completion % — rendered from one JSON source into a diffable markdown doc and a self-contained interactive HTML system map.

**Architecture:** A single `system_inventory.json` is the only maintained file. A Python generator (`tools/build_system_inventory.py`) validates it, computes completion %, and renders both `SYSTEM_INVENTORY.md` and `system_map.html`. The generator's `--check` mode is registered as a validation smoke so the data/docs/map/code can't silently drift. Tooling is built first (TDD against fixtures), then the data is populated by a deep code-verified pass batched by domain.

**Tech Stack:** Python 3 (stdlib only — no new deps), vanilla HTML/CSS/JS (no CDN, no build step), Godot 4.6.2 GDScript (the code being inventoried, read-only here).

## Global Constraints

- Source of truth is `docs/game/inventory/system_inventory.json`; `SYSTEM_INVENTORY.md` and `system_map.html` are **generated, never hand-edited** (each carries a "generated — do not edit" banner).
- `system_map.html` must be **self-contained**: JSON embedded at build time, no external/CDN requests, opens offline by double-click.
- Python: **stdlib only**, Python 3. No pip installs.
- Completion % is **computed by the generator, never hand-typed**.
- Hollow-output cap: while a system's output is not live, its completion is **capped at 50%**.
- Completion weights (exact): Model 15, Reachable 15, Driven 15, Coupled 35 (input 17.5 + output 17.5), Content 20.
- Content score: `none`→0, `partial`→0.5, `sufficient`→1.0.
- A `simulation`-kind system with `confidence: "?"` is a **hard failure** of `--check` (inventory not done).
- Every coupling/driven claim carries a cited location (`file.gd:line` or `file.gd:func`).
- Validation contract is the **marker line**, never the exit code alone (project convention).
- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`; project root `C:/Users/dasbl/Documents/The Synaptic Sea` (not needed for the Python tool, listed for the code-reading pass).

---

## File Structure

| Path | Responsibility |
|---|---|
| `docs/game/inventory/system_inventory.json` | The data (source of truth). Grows through the domain pass. |
| `tools/build_system_inventory.py` | Generator + validator: load → validate → compute completion → render MD + HTML. CLI: default = build, `--check` = validate + staleness. |
| `tools/test_build_system_inventory.py` | Unit tests (stdlib `assert`s, marker print) for the pure functions: completion math, hollow cap, parent rollup, validation. |
| `tools/fixtures/inventory_min.json` | Tiny 3-system fixture used by the tests. |
| `docs/game/inventory/SYSTEM_INVENTORY.md` | Generated: per-domain catalog + loop closure + integration matrix tables. |
| `docs/game/inventory/system_map.html` | Generated: card-grid view + matrix tab + detail panel. |
| `docs/game/06_validation_plan.md` | Register the `--check` smoke (modify). |
| `STATUS.md`, `CLAUDE.md`, `docs/game/system_completion_audit.md` | Repointed/folded at the end (modify). |

The generator is one file (matches existing `tools/check_export_pipeline.py` single-script style); it stays organized by pure functions (compute/validate) + render functions (md/html) + a `main()`.

---

## Data model (authoritative for this plan)

This refines the spec's schema with explicit `live` booleans so completion and the hollow cap are deterministic (the spec showed `coupling` as a single value; the generator **derives** `coupling` from the two booleans so there is one source of truth).

```jsonc
// a system (or nested subsystem) entry
{
  "id": "vitals_state",
  "file": "scripts/systems/vitals_state.gd",
  "name": "Player Vitals",
  "domain": "survival",
  "kind": "simulation",                 // simulation | ui | infra | tooling
  "model_exists": true,
  "smoke": "scripts/validation/vitals_state_smoke.gd",
  "reachable": true,
  "driven": true,
  "driven_at": "playable_generated_ship.gd:4213",
  "input":  { "live": true,  "desc": "temp/radiation/status/moving", "at": "playable_generated_ship.gd:4206-4212" },
  "output": { "live": true,  "desc": "death + HUD + sanity feed",    "at": "playable_generated_ship.gd:4213" },
  "confidence": "V",                    // V | P | ?
  "loops": ["survival_vitals"],
  "integrations": [ { "to": "hallucination_director", "via": "sanity feed", "at": "playable_generated_ship.gd:4213", "health": "healthy" } ],
  "content": "partial",                 // none | partial | sufficient
  "content_note": "vitals tuning exists",
  "functional": null,                   // only for kind infra/tooling: true|false
  "gaps": [],
  "subsystems": []
}
```

`coupling` is NOT stored — the generator computes it: both live → `closed`; one live → `half`; neither → `hollow`; `kind` infra/tooling → `na`.

---

### Task 1: Generator scaffold + completion math (pure functions, TDD)

**Files:**
- Create: `tools/build_system_inventory.py`
- Create: `tools/test_build_system_inventory.py`
- Create: `tools/fixtures/inventory_min.json`

**Interfaces:**
- Produces: `derive_coupling(system) -> str`, `leaf_completion(system) -> int|None`, `system_completion(system) -> int|None`, `WEIGHTS` dict.

- [ ] **Step 1: Write the fixture**

Create `tools/fixtures/inventory_min.json`:

```json
{
  "systems": [
    { "id": "alpha", "file": "tools/build_system_inventory.py", "name": "Alpha", "domain": "survival",
      "kind": "simulation", "model_exists": true, "smoke": null, "reachable": true, "driven": true,
      "driven_at": "x:1", "input": {"live": true, "desc": "i", "at": "x:1"},
      "output": {"live": true, "desc": "o", "at": "x:1"}, "confidence": "V", "loops": ["l1"],
      "integrations": [{"to": "beta", "via": "v", "at": "x:1", "health": "healthy"}],
      "content": "sufficient", "content_note": "", "functional": null, "gaps": [], "subsystems": [] },
    { "id": "beta", "file": "tools/build_system_inventory.py", "name": "Beta", "domain": "ship_systems",
      "kind": "simulation", "model_exists": true, "smoke": null, "reachable": true, "driven": true,
      "driven_at": "x:2", "input": {"live": true, "desc": "i", "at": "x:2"},
      "output": {"live": false, "desc": "HUD only", "at": "x:2"}, "confidence": "V", "loops": ["l1"],
      "integrations": [], "content": "partial", "content_note": "", "functional": null, "gaps": [], "subsystems": [] },
    { "id": "infra1", "file": "tools/build_system_inventory.py", "name": "Infra", "domain": "infra",
      "kind": "infra", "model_exists": true, "smoke": null, "reachable": false, "driven": false,
      "driven_at": null, "input": {"live": false, "desc": "", "at": null},
      "output": {"live": false, "desc": "", "at": null}, "confidence": "V", "loops": [],
      "integrations": [], "content": "none", "content_note": "", "functional": true, "gaps": [], "subsystems": [] }
  ],
  "loops": [ { "id": "l1", "name": "L1", "closes": "partial",
    "steps": [{"system": "alpha", "role": "core"}, {"system": "beta", "role": "sink"}], "break_points": [] } ]
}
```

- [ ] **Step 2: Write the failing test**

Create `tools/test_build_system_inventory.py`:

```python
import build_system_inventory as b

def t(name, cond):
    assert cond, f"FAIL: {name}"

# closed-loop + sufficient content = 100
closed = {"kind":"simulation","model_exists":True,"reachable":True,"driven":True,
          "input":{"live":True},"output":{"live":True},"content":"sufficient","subsystems":[]}
t("closed=100", b.leaf_completion(closed) == 100)
t("closed coupling", b.derive_coupling(closed) == "closed")

# hollow (no input, no output) + partial -> raw 55, capped to 50
hollow = {"kind":"simulation","model_exists":True,"reachable":True,"driven":True,
          "input":{"live":False},"output":{"live":False},"content":"partial","subsystems":[]}
t("hollow capped 50", b.leaf_completion(hollow) == 50)
t("hollow coupling", b.derive_coupling(hollow) == "hollow")

# half, input live only + partial -> raw 72.5 -> output dead -> capped 50
half_in = {"kind":"simulation","model_exists":True,"reachable":True,"driven":True,
           "input":{"live":True},"output":{"live":False},"content":"partial","subsystems":[]}
t("half-in capped 50", b.leaf_completion(half_in) == 50)
t("half coupling", b.derive_coupling(half_in) == "half")

# half, output live only + none content -> 15+15+15+17.5 = 62.5 -> no cap -> 63
half_out = {"kind":"simulation","model_exists":True,"reachable":True,"driven":True,
            "input":{"live":False},"output":{"live":True},"content":"none","subsystems":[]}
t("half-out 63", b.leaf_completion(half_out) == 63)

# infra excluded from completion
infra = {"kind":"infra","input":{"live":False},"output":{"live":False},"subsystems":[]}
t("infra none", b.leaf_completion(infra) is None)
t("infra coupling na", b.derive_coupling(infra) == "na")

# parent rollup = mean of subsystem completions
parent = {"kind":"simulation","subsystems":[closed, half_out]}  # mean(100,63)=81.5 -> 82
t("parent rollup", b.system_completion(parent) == 82)

print("BUILD INVENTORY SELFTEST PASS")
```

(Later tasks append more asserts above this print — the marker carries no count so it stays valid.)

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "C:/Users/dasbl/Documents/The Synaptic Sea" && python tools/test_build_system_inventory.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'build_system_inventory'` (or AttributeError).

- [ ] **Step 4: Implement the pure functions**

Create `tools/build_system_inventory.py`:

```python
#!/usr/bin/env python3
"""Generate the Synaptic Sea system inventory: validate JSON, compute completion,
render SYSTEM_INVENTORY.md + system_map.html. Stdlib only."""
import json, sys, os

WEIGHTS = {"model": 15, "reachable": 15, "driven": 15, "coupled": 35, "content": 20}
_CONTENT = {"none": 0.0, "partial": 0.5, "sufficient": 1.0}

def derive_coupling(s):
    if s.get("kind") in ("infra", "tooling"):
        return "na"
    i = bool(s.get("input", {}).get("live"))
    o = bool(s.get("output", {}).get("live"))
    if i and o: return "closed"
    if not i and not o: return "hollow"
    return "half"

def leaf_completion(s):
    if derive_coupling(s) == "na":
        return None
    i = bool(s.get("input", {}).get("live"))
    o = bool(s.get("output", {}).get("live"))
    score = 0.0
    score += WEIGHTS["model"]     if s.get("model_exists") else 0
    score += WEIGHTS["reachable"] if s.get("reachable") else 0
    score += WEIGHTS["driven"]    if s.get("driven") else 0
    score += (17.5 if i else 0) + (17.5 if o else 0)
    score += WEIGHTS["content"] * _CONTENT[s.get("content", "none")]
    if not o:                      # hollow-output cap
        score = min(score, 50)
    return round(score)

def system_completion(s):
    subs = s.get("subsystems") or []
    if subs:
        vals = [system_completion(x) for x in subs]
        vals = [v for v in vals if v is not None]
        return round(sum(vals) / len(vals)) if vals else None
    return leaf_completion(s)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "C:/Users/dasbl/Documents/The Synaptic Sea" && python tools/test_build_system_inventory.py`
Expected: PASS — prints `BUILD INVENTORY SELFTEST PASS`.

- [ ] **Step 6: Commit**

```bash
git add tools/build_system_inventory.py tools/test_build_system_inventory.py tools/fixtures/inventory_min.json
git commit -m "feat(inventory): completion math + coupling derivation (TDD)"
```

---

### Task 2: Validator (`validate`) — TDD

**Files:**
- Modify: `tools/build_system_inventory.py`
- Modify: `tools/test_build_system_inventory.py`

**Interfaces:**
- Consumes: `derive_coupling`.
- Produces: `iter_systems(data) -> generator`, `validate(data, root) -> list[str]` (returns list of error strings; empty = valid).

- [ ] **Step 1: Add failing tests** (append to `tools/test_build_system_inventory.py`, before the final print)

```python
# validate: dangling integration target
bad_ref = {"systems":[{"id":"a","file":"tools/build_system_inventory.py","kind":"simulation",
  "confidence":"V","input":{"live":True},"output":{"live":True},
  "integrations":[{"to":"ghost"}],"subsystems":[]}], "loops":[]}
errs = b.validate(bad_ref, ".")
t("dangling ref caught", any("ghost" in e for e in errs))

# validate: simulation system with confidence '?'
unsure = {"systems":[{"id":"a","file":"tools/build_system_inventory.py","kind":"simulation",
  "confidence":"?","input":{"live":True},"output":{"live":True},"integrations":[],"subsystems":[]}], "loops":[]}
t("confidence ? caught", any("confidence" in e for e in b.validate(unsure, ".")))

# validate: missing file
missing = {"systems":[{"id":"a","file":"scripts/systems/DOES_NOT_EXIST.gd","kind":"simulation",
  "confidence":"V","input":{"live":True},"output":{"live":True},"integrations":[],"subsystems":[]}], "loops":[]}
t("missing file caught", any("DOES_NOT_EXIST" in e for e in b.validate(missing, ".")))

# validate: clean fixture passes
with open("tools/fixtures/inventory_min.json") as f:
    clean = json.load(f)
t("clean fixture valid", b.validate(clean, ".") == [])
```

First add `import json` to the **top** of `tools/test_build_system_inventory.py` (next to `import build_system_inventory as b`) — these new tests need it.

- [ ] **Step 2: Run to verify failure**

Run: `python tools/test_build_system_inventory.py`
Expected: FAIL — `AttributeError: module ... has no attribute 'validate'`.

- [ ] **Step 3: Implement** (append to `tools/build_system_inventory.py`)

```python
def iter_systems(data):
    def walk(s):
        yield s
        for sub in (s.get("subsystems") or []):
            yield from walk(sub)
    for top in data.get("systems", []):
        yield from walk(top)

def validate(data, root):
    errs = []
    ids = {s["id"] for s in iter_systems(data)}
    for s in iter_systems(data):
        path = s.get("file")
        if path and not os.path.isfile(os.path.join(root, path)):
            errs.append(f"missing file for '{s['id']}': {path}")
        if s.get("kind") == "simulation" and s.get("confidence") == "?":
            errs.append(f"simulation system '{s['id']}' still confidence '?'")
        for edge in (s.get("integrations") or []):
            if edge.get("to") not in ids:
                errs.append(f"'{s['id']}' integration -> unknown id '{edge.get('to')}'")
    for loop in data.get("loops", []):
        for step in loop.get("steps", []):
            if step.get("system") not in ids:
                errs.append(f"loop '{loop['id']}' step -> unknown id '{step.get('system')}'")
    return errs
```

- [ ] **Step 4: Run to verify pass**

Run: `python tools/test_build_system_inventory.py`
Expected: PASS — `BUILD INVENTORY SELFTEST PASS` (the new asserts run before the print; add them above it).

- [ ] **Step 5: Commit**

```bash
git add tools/build_system_inventory.py tools/test_build_system_inventory.py
git commit -m "feat(inventory): JSON validator (dangling refs, unverified sims, missing files)"
```

---

### Task 3: Markdown renderer — TDD

**Files:**
- Modify: `tools/build_system_inventory.py`
- Modify: `tools/test_build_system_inventory.py`

**Interfaces:**
- Consumes: `iter_systems`, `system_completion`, `derive_coupling`.
- Produces: `render_markdown(data) -> str`.

- [ ] **Step 1: Add failing test** (before final print)

```python
md = b.render_markdown(clean)
t("md has banner", "GENERATED" in md.upper())
t("md lists alpha", "Alpha" in md and "100%" in md)
t("md shows beta cap", "Beta" in md and "50%" in md)        # half-in capped
t("md matrix has edge", "alpha" in md and "beta" in md)
```

- [ ] **Step 2: Run to verify failure**

Run: `python tools/test_build_system_inventory.py`
Expected: FAIL — no attribute `render_markdown`.

- [ ] **Step 3: Implement** (append to `build_system_inventory.py`)

```python
_DOT = {"closed": "🟢", "half": "🟡", "hollow": "🔴", "na": "⚪"}

def render_markdown(data):
    out = ["<!-- GENERATED by tools/build_system_inventory.py — DO NOT EDIT. "
           "Edit docs/game/inventory/system_inventory.json and re-run. -->",
           "# System Inventory\n"]
    by_domain = {}
    for s in data.get("systems", []):
        by_domain.setdefault(s.get("domain", "?"), []).append(s)
    for domain in sorted(by_domain):
        out.append(f"## {domain}\n")
        out.append("| System | Coupling | Completion | Conf | Driven at |")
        out.append("|---|---|---|---|---|")
        for s in by_domain[domain]:
            pct = system_completion(s)
            pct_s = "—" if pct is None else f"{pct}%"
            out.append(f"| {s.get('name', s['id'])} | {_DOT[derive_coupling(s)]} | "
                       f"{pct_s} | [{s.get('confidence','?')}] | {s.get('driven_at') or '—'} |")
        out.append("")
    # integration matrix
    ids = [s["id"] for s in iter_systems(data)]
    edges = {(s["id"], e["to"]): e.get("health", "?")
             for s in iter_systems(data) for e in (s.get("integrations") or [])}
    out.append("## Integration matrix (row → col)\n")
    out.append("| from \\ to | " + " | ".join(ids) + " |")
    out.append("|" + "---|" * (len(ids) + 1))
    for r in ids:
        cells = [{"healthy": "🟢", "weak": "🟡", "broken": "🔴"}.get(edges.get((r, c)), "")
                 for c in ids]
        out.append(f"| {r} | " + " | ".join(cells) + " |")
    return "\n".join(out) + "\n"
```

- [ ] **Step 4: Run to verify pass**

Run: `python tools/test_build_system_inventory.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/build_system_inventory.py tools/test_build_system_inventory.py
git commit -m "feat(inventory): markdown renderer (catalog + integration matrix)"
```

---

### Task 4: HTML map renderer + CLI — TDD

**Files:**
- Modify: `tools/build_system_inventory.py`
- Modify: `tools/test_build_system_inventory.py`

**Interfaces:**
- Consumes: `system_completion`, `derive_coupling`, `render_markdown`, `validate`.
- Produces: `render_html(data) -> str`; `main(argv) -> int`.

- [ ] **Step 1: Add failing test** (before final print)

```python
html = b.render_html(clean)
t("html self-contained", "<!DOCTYPE html" in html and "http://" not in html.replace("http://www.w3.org",""))
t("html embeds data", '"alpha"' in html or "alpha" in html)
t("html has card view", "card" in html.lower())
t("html has matrix tab", "matrix" in html.lower())
```

- [ ] **Step 2: Run to verify failure**

Run: `python tools/test_build_system_inventory.py`
Expected: FAIL — no attribute `render_html`.

- [ ] **Step 3: Implement** `render_html` and `main` (append to `build_system_inventory.py`)

The HTML is a single self-contained file: it embeds the inventory as a JSON `<script>` block plus precomputed completion/coupling, then renders the card grid + matrix tab + detail panel in vanilla JS. Build the enriched payload in Python (so the JS doesn't re-implement the math), embed it, and keep CSS/JS inline.

```python
def _enriched(data):
    rows = []
    for s in data.get("systems", []):
        rows.append({**s, "_pct": system_completion(s), "_coupling": derive_coupling(s)})
    return {"systems": rows, "loops": data.get("loops", []),
            "edges": [{"from": s["id"], **e}
                      for s in iter_systems(data) for e in (s.get("integrations") or [])]}

def render_html(data):
    payload = json.dumps(_enriched(data))
    # NOTE: no CDN. All CSS/JS inline. Card grid default; matrix tab; click -> detail.
    return """<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Synaptic Sea — System Map</title><style>
body{background:#0f1420;color:#d7dee8;font-family:system-ui,sans-serif;margin:0;padding:16px}
.tab{cursor:pointer;padding:6px 12px;border:1px solid #2a3340;border-radius:6px;display:inline-block;margin-right:6px}
.tab.on{background:#1f2937}
.domain{font-size:12px;letter-spacing:.6px;color:#8fb;margin:14px 0 6px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}
.card{background:#1a212e;border:1px solid #2a3340;border-radius:8px;padding:9px;cursor:pointer}
.bar{height:5px;background:#222c38;border-radius:3px;margin:7px 0 4px}
.dot{width:9px;height:9px;border-radius:50%;display:inline-block;float:right}
table{border-collapse:collapse;font-size:10px}td{width:16px;height:16px;border:1px solid #0f1420}
#detail{position:fixed;right:0;top:0;width:300px;height:100%;background:#141a24;border-left:1px solid #2a3340;padding:14px;overflow:auto;display:none}
</style></head><body>
<h2>Synaptic Sea — System Map</h2>
<span class="tab on" onclick="show('cards')">Systems</span>
<span class="tab" onclick="show('matrix')">Integrations</span>
<div id="cards"></div><div id="matrix" style="display:none"></div>
<div id="detail"></div>
<script>const DATA=""" + payload + """;
const C={closed:'#3fb27f',half:'#e0a93b',hollow:'#d8584e',na:'#55606e'};
function show(w){for(const id of ['cards','matrix'])document.getElementById(id).style.display=id==w?'block':'none';
 document.querySelectorAll('.tab').forEach((t,i)=>t.className='tab'+((i==0)==(w=='cards')?' on':''));}
function detail(s){const d=document.getElementById('detail');d.style.display='block';
 d.innerHTML=`<b>${s.name||s.id}</b> <span style="color:${C[s._coupling]}">${s._coupling} ${s._pct==null?'—':s._pct+'%'}</span>
 <div style="opacity:.6;font-size:11px">${s.file}</div>
 <div style="font-size:11px;margin-top:8px">model ${s.model_exists?'✓':'✗'} · reachable ${s.reachable?'✓':'✗'} · driven ${s.driven?'✓':'✗'}
 <br>in ${s.input&&s.input.live?'✓':'✗'} out ${s.output&&s.output.live?'✓':'✗'} · content ${s.content}
 <br>driven_at ${s.driven_at||'—'} · conf [${s.confidence}]</div>`;}
function cards(){const by={};DATA.systems.forEach(s=>(by[s.domain]=by[s.domain]||[]).push(s));
 let h='';for(const dom of Object.keys(by).sort()){h+=`<div class="domain">${dom.toUpperCase()}</div><div class="grid">`;
 for(const s of by[dom]){h+=`<div class="card" onclick='detail(${JSON.stringify(s)})'>
 <b style="font-size:12px">${s.name||s.id}</b><span class="dot" style="background:${C[s._coupling]}"></span>
 <div class="bar"><div style="width:${s._pct||0}%;height:5px;background:${C[s._coupling]};border-radius:3px"></div></div>
 <div style="font-size:10px;opacity:.6">${s._pct==null?'infra':s._pct+'%'}</div></div>`;}h+='</div>';}
 document.getElementById('cards').innerHTML=h;}
function matrix(){const ids=DATA.systems.map(s=>s.id);const e={};DATA.edges.forEach(x=>e[x.from+'|'+x.to]=x.health);
 let h='<table><tr><td></td>'+ids.map(i=>`<td style="writing-mode:vertical-rl;height:auto">${i}</td>`).join('')+'</tr>';
 for(const r of ids){h+=`<tr><td style="width:auto">${r}</td>`+ids.map(c=>{const v=e[r+'|'+c];
 return `<td style="background:${v=='healthy'?C.closed:v=='weak'?C.half:v=='broken'?C.hollow:'#1a212e'}"></td>`;}).join('')+'</tr>';}
 document.getElementById('matrix').innerHTML=h+'</table>';}
cards();matrix();
</script></body></html>"""

def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, "docs/game/inventory/system_inventory.json")
    with open(src, encoding="utf-8") as f:
        data = json.load(f)
    errs = validate(data, root)
    n = sum(1 for _ in iter_systems(data))
    verified = sum(1 for s in iter_systems(data) if s.get("confidence") == "V")
    md = render_markdown(data)
    html = render_html(data)
    md_path = os.path.join(root, "docs/game/inventory/SYSTEM_INVENTORY.md")
    html_path = os.path.join(root, "docs/game/inventory/system_map.html")
    if "--check" in argv:
        stale = []
        for p, content in ((md_path, md), (html_path, html)):
            cur = open(p, encoding="utf-8").read() if os.path.isfile(p) else None
            if cur != content:
                stale.append(os.path.basename(p))
        if errs or stale:
            for e in errs: print("ERROR:", e)
            if stale: print("ERROR: stale generated files:", ", ".join(stale))
            return 1
        print(f"SYSTEM INVENTORY CHECK PASS systems={n} verified={verified}")
        return 0
    open(md_path, "w", encoding="utf-8").write(md)
    open(html_path, "w", encoding="utf-8").write(html)
    print(f"SYSTEM INVENTORY BUILD PASS systems={n} verified={verified}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run unit tests to verify pass**

Run: `python tools/test_build_system_inventory.py`
Expected: PASS — `BUILD INVENTORY SELFTEST PASS`.

- [ ] **Step 5: Commit**

```bash
git add tools/build_system_inventory.py tools/test_build_system_inventory.py
git commit -m "feat(inventory): self-contained HTML map (cards + matrix + detail) and CLI"
```

---

### Task 5: Seed the real inventory file + first build + register smoke

**Files:**
- Create: `docs/game/inventory/system_inventory.json` (seed: 1–2 real, fully-traced survival systems)
- Create (generated): `docs/game/inventory/SYSTEM_INVENTORY.md`, `docs/game/inventory/system_map.html`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes: the generator CLI.

- [ ] **Step 1: Author a minimal real seed**

Create `docs/game/inventory/system_inventory.json` with the `vitals_state` and `radiation_state` entries (verify the cited lines against `scripts/procgen/playable_generated_ship.gd` and `scripts/systems/vitals_state.gd` first — open them and confirm the `tick`/drain lines; the audit's `4213`/`4209` are starting hypotheses, not gospel). Use the data-model shape from the top of this plan. Wrap them in `{"systems":[...], "loops":[{ "id":"survival_vitals", ...}]}`.

- [ ] **Step 2: Build and verify the marker**

Run: `cd "C:/Users/dasbl/Documents/The Synaptic Sea" && python tools/build_system_inventory.py`
Expected: prints `SYSTEM INVENTORY BUILD PASS systems=2 verified=2` and creates the `.md` + `.html`.

- [ ] **Step 3: Eyeball the map**

Open `docs/game/inventory/system_map.html` in a browser. Confirm: two cards under SURVIVAL, completion bars render, clicking a card shows the detail panel, the Integrations tab shows the grid. (Manual check; no marker.)

- [ ] **Step 4: Verify `--check` passes on fresh output**

Run: `python tools/build_system_inventory.py --check`
Expected: `SYSTEM INVENTORY CHECK PASS systems=2 verified=2`.

- [ ] **Step 5: Register the smoke in the validation plan**

In `docs/game/06_validation_plan.md`, add a command entry (follow the existing Python-tool entry style used for `check_export_pipeline.py`) running `python tools/build_system_inventory.py --check` and expecting the marker `SYSTEM INVENTORY CHECK PASS`. Note it is a host-side Python check (not a Godot smoke), like the export pipeline check.

- [ ] **Step 6: Commit**

```bash
git add docs/game/inventory/ docs/game/06_validation_plan.md
git commit -m "feat(inventory): seed real survival systems, first render, register --check smoke"
```

---

## Domain Pass Procedure (applies to Tasks 6–17)

For each domain task below, repeat this exact procedure. This is the deep code-verified pass — the heart of the inventory.

1. **Enumerate** every `.gd` in the domain's listed directories (use Glob; do not hand-list from memory). These are the systems you must cover.
2. **For each script**, open it and the coordinator `scripts/procgen/playable_generated_ship.gd` (and the named sub-coordinator if any), and determine:
   - `model_exists` + `smoke` — does a `*_state_smoke.gd` / matching smoke exist?
   - `reachable` — is it constructed in the live scene? (search the coordinator / sub-coordinator for `preload`/`new()` of it)
   - `driven` + `driven_at` — is `tick()`/a mutator called each frame or on real events? Cite `file.gd:line`.
   - `input.live` + `input.at` — is there a **live source** feeding it? Cite the line.
   - `output.live` + `output.at` — is its output **consumed by live gameplay** (not just `get_status_lines()`/HUD)? Cite the line.
   - `integrations[]` — structured edges to other system `id`s, each with `health` (healthy/weak/broken).
   - `content` — judge `none`/`partial`/`sufficient` from the backing `data/` files, conservatively; add `content_note`.
   - `confidence` — `V` only if you traced the exact lines; else `P`; never leave `?` on a `simulation` system.
   - `subsystems[]` — nest child entries for true subcomponents (e.g. `audio_manager` → its tickees).
3. **Add/refine** the entries in `system_inventory.json` (and any loop entries for the domain's player loop).
4. **Build**: `python tools/build_system_inventory.py` → expect `SYSTEM INVENTORY BUILD PASS`.
5. **Check**: `python tools/build_system_inventory.py --check` → expect `SYSTEM INVENTORY CHECK PASS`.
6. **Done when**: every script in the domain's directories appears as an entry (no omissions), `--check` passes, and no `simulation` entry is `confidence:"?"`.
7. **Commit**: `git add docs/game/inventory/ && git commit -m "feat(inventory): <domain> domain code-verified pass"`.

> The existing `docs/game/system_completion_audit.md` has cited line ranges per lane — use them as **starting hypotheses to re-confirm against the code**, never copy blindly (it is a partial pass and may be stale).

---

### Task 6: Survival domain pass

- [ ] Run the Domain Pass Procedure for **survival**.
  - Directories/scripts: `scripts/systems/vitals_state.gd`, `radiation_state.gd`, `body_temperature_state.gd`, `status_effects_state.gd`, `sanity_state.gd`, `hallucination_director.gd`, `hallucination_manager.gd`, plus any other `*_state.gd` whose domain is survival/vitals.
  - Coordinator hypothesis lines (re-verify): vitals tick ~4213, radiation ~4209/4227, temp ~4206/4230, status ~4212, sanity block after `sanity_state.tick`.
  - Loop: `survival_vitals`.

---

### Task 7: Food / cooking / spoilage domain pass

- [ ] Run the Domain Pass Procedure for **food**.
  - Scripts: `food_state.gd`, `consumable_state.gd` (food/drink branch), `hydroponics_state.gd`, `synthesizer_state.gd`, `water_recycler_state.gd`, `spoilage_state.gd`, `cooking_state.gd` (note: retained only inside `SynthesizerState`).
  - Coordinator hypothesis lines: food/cook ~3273–3360, water-recycler read ~1340.
  - Loop: `food`. Expect `hydroponics`/`synthesizer` hollow, `spoilage`/`water_recycler` half.

---

### Task 8: Ship systems & sustenance domain pass

- [ ] Run the Domain Pass Procedure for **ship_systems**.
  - Scripts: `ship_systems_manager.gd` (+ `ship_system.gd`, `ship_subcomponent.gd` as subsystems), `power_grid_state.gd`, `propulsion_expanded_state.gd`, `life_support_expanded_state.gd`, `hull_integrity_state.gd`, `fire_suppression_state.gd`, `extinguisher_state.gd`, `sustenance_state.gd`, `crafting_state.gd`, `station_state.gd`, `material_state.gd`, `field_crafting_state.gd`, `deconstruction_resolver.gd`, `quality_tier_resolver.gd`, `junk_yield_resolver.gd`. (`shield_state` was deleted — confirm absent.)
  - Coordinator hypothesis lines: power ~1327, propulsion ~1331/1716, crafting ~1353, life-support ~1342, fire context build + tick, sustenance ~1364/4064.
  - Loop: `ship_systems` (+ `fire`). Expect `sustenance` hollow, `hull_integrity` half (sink live, sources #1–3 dead).

---

### Task 9: Combat / threat AI domain pass

- [ ] Run the Domain Pass Procedure for **combat**.
  - Scripts: `threat_manager.gd` (+ subsystems `detection_state.gd`, `damage_pipeline.gd`, `armor_resolver.gd`, `threat_ai_state.gd`), `threat_placeholder_renderer.gd`, encounter/threat archetype scripts.
  - Coordinator hypothesis lines: `tick_threats` ~3357, detection ~3350, `attack_with_weapon` ~3338, `configure_for_layout`/`_fallback_markers_from_layout` ~221 in `threat_manager.gd`.
  - Loop: `combat`.

---

### Task 10: Loot ecosystem domain pass

- [ ] Run the Domain Pass Procedure for **loot**.
  - Scripts: `loot_container.gd` (tool), `loot_roller.gd`, `loot_distribution.gd`, `rarity_tier.gd`, `unique_item_state.gd`, `item_defs`-related.
  - Coordinator hypothesis lines: `_build_loot_containers` ~2378, `_on_loot_container_searched` grant ~2792.
  - Loop: `loot`. Note biome `loot_quality_modifier` not yet applied (gap).

---

### Task 11: Consumables / medicine / stimulants / ammo domain pass

- [ ] Run the Domain Pass Procedure for **consumables**.
  - Scripts: `consumable_state.gd`, `effect_dispatcher.gd`, `medicine_state.gd`, `stimulant_state.gd`, `addiction_state.gd`, `ammo_state.gd`.
  - Coordinator hypothesis lines: `_consumable_pipeline_context` ~3361, stimulant/addiction tick ~4199.
  - Loop: reuse `survival_vitals` / add `consumables`.

---

### Task 12: Progression / meta / hub domain pass

- [ ] Run the Domain Pass Procedure for **progression**.
  - Scripts: `player_progression_state.gd`, `training_event_bus.gd`, `meta_progression_state.gd`, `hub_upgrade_state.gd`, `skill_tree_state.gd`, `class_definition.gd`.
  - Coordinator hypothesis lines: `emit("repair_full_system")` ~3890, `apply_meta_payout` ~5535, hub-upgrade apply ~1256–1271.
  - Loop: `progression`. Flag `skill_tree` node-effect as `P` until traced.

---

### Task 13: Procgen / world variety domain pass

- [ ] Run the Domain Pass Procedure for **procgen**.
  - Directory: `scripts/procgen/` (the pipeline stages from CLAUDE.md: `template_selector`, `room_assigner`, `cell_layout_engine`, `wall_door_resolver`, `layout_serializer`, `generated_ship_loader`, `ship_layout_generator`, `gameplay_slice_builder`, `ship_generator`, `encounter_injector`, `room_variant_selector`, `biome_profile`, `difficulty_profile`, `kit_catalog`, `structural_placer`, `seed_determinism_contract`). The coordinator `playable_generated_ship.gd` itself is the hub — list it as a `kind:"infra"` coordinator node or omit per judgment.
  - Coordinator hypothesis: `configure_run_context` before travel; biome/difficulty resolution.
  - Loop: `travel`.

---

### Task 14: Audio domain pass

- [ ] Run the Domain Pass Procedure for **audio**.
  - Scripts: `audio_manager.gd` (+ subsystems `ambient_zone_state.gd`, `sfx_event_router.gd`, `dynamic_music_state.gd`, `meta_event_state.gd`, `spatial_audio_resolver.gd`).
  - Coordinator hypothesis: `audio_manager.tick` ~4250. **Open question to resolve this pass:** are SFX/music triggers fired by real events (combat/damage/loot) or idle ambience? Trace the emitters; set `output.live` accordingly. Do not leave `?` — trace it.

---

### Task 15: Save / load / persistence domain pass

- [ ] Run the Domain Pass Procedure for **save**.
  - Scripts: `save_load_service.gd`, `save_slot_state.gd`, `save_index_state.gd`, `autosave_policy.gd`, `save_migration_service.gd`, `permadeath_resolver.gd`, `cloud_manifest_state.gd`, `run_snapshot.gd`, `world_snapshot.gd`.
  - Coordinator hypothesis: autosave tick ~5475.
  - These are functional infra — grade `kind` carefully (`save` is a real loop; cloud is `infra` known-future).

---

### Task 16: UI / HUD / accessibility domain pass

- [ ] Run the Domain Pass Procedure for **ui**.
  - Directory: `scripts/ui/` (all panels, `menu_coordinator.gd`, `menu_state.gd`, `settings_state.gd`, `tutorial_state.gd`, `map_fog_state.gd`, `controller_glyph_state.gd`, `tooltip_presenter.gd`, the 10 meta screens, hotbar/panels), plus `scripts/player/`, `scripts/camera/`, `scripts/interaction/`, `scripts/placement/`.
  - UI is the *sink* by nature: `output.live` is typically true (it renders); `input.live` is "is the system behind it real?" — note where a panel faithfully renders an upstream hollow (e.g. ship-systems panel rendering hollow sustenance).

---

### Task 17: Infra / release / tooling domain pass

- [ ] Run the Domain Pass Procedure for **infra**.
  - Scripts (kind `infra`/`tooling`, coupling `na`, set `functional`): `automated_playtest_rubric.gd`, `balance_ledger.gd`, `crash_report_bundle.gd`, `dependency_validator.gd`, `integration_matrix.gd`, `product_audit_report.gd`, `seed_determinism_contract.gd`, `build_metadata_state.gd`, `localization_catalog.gd`, `demo_scope_gate.gd`, `release_readiness_ledger.gd`, plus `scripts/export/` if surfaced.
  - These carry `functional: true/false` and `_pct = null`; they prove completeness without polluting the simulation math.

---

### Task 18: Completeness count check + final full build

**Files:**
- Modify: `tools/build_system_inventory.py` (add a `--coverage` mode)
- Modify: `tools/test_build_system_inventory.py`

**Interfaces:**
- Produces: `coverage(data, root, dirs) -> list[str]` (scripts on disk not present in the inventory).

- [ ] **Step 1: Add failing test** (before final print)

```python
cov = b.coverage({"systems":[{"id":"x","file":"tools/build_system_inventory.py","subsystems":[]}],"loops":[]},
                 ".", ["tools"])
t("coverage finds gap", any("test_build_system_inventory.py" in c for c in cov))
```

- [ ] **Step 2: Run to verify failure**

Run: `python tools/test_build_system_inventory.py`
Expected: FAIL — no attribute `coverage`.

- [ ] **Step 3: Implement** (append to `build_system_inventory.py`, and wire `--coverage` into `main`)

```python
def coverage(data, root, dirs):
    have = {s.get("file") for s in iter_systems(data)}
    missing = []
    for d in dirs:
        for dirpath, _, files in os.walk(os.path.join(root, d)):
            for fn in files:
                if fn.endswith(".gd"):
                    rel = os.path.relpath(os.path.join(dirpath, fn), root).replace("\\", "/")
                    if rel not in have:
                        missing.append(rel)
    return sorted(missing)
```

In `main`, before the `--check` block, add:

```python
    RUNTIME_DIRS = ["scripts/systems", "scripts/procgen", "scripts/tools", "scripts/ui",
                    "scripts/player", "scripts/camera", "scripts/interaction", "scripts/placement"]
    if "--coverage" in argv:
        missing = coverage(data, root, RUNTIME_DIRS)
        if missing:
            for m in missing: print("ERROR: not in inventory:", m)
            return 1
        print(f"SYSTEM INVENTORY COVERAGE PASS scripts={n}")
        return 0
```

- [ ] **Step 4: Run unit test to verify pass**

Run: `python tools/test_build_system_inventory.py`
Expected: PASS.

- [ ] **Step 5: Run real coverage — must be empty**

Run: `python tools/build_system_inventory.py --coverage`
Expected: `SYSTEM INVENTORY COVERAGE PASS scripts=<N>`. If it lists missing scripts, go back and add them (a domain pass missed them).

- [ ] **Step 6: Final build + check**

Run: `python tools/build_system_inventory.py && python tools/build_system_inventory.py --check`
Expected: `SYSTEM INVENTORY BUILD PASS ...` then `SYSTEM INVENTORY CHECK PASS ...`.

- [ ] **Step 7: Commit**

```bash
git add tools/ docs/game/inventory/
git commit -m "feat(inventory): coverage check proves every runtime script is inventoried"
```

---

### Task 19: Promote to canonical — repoint docs

**Files:**
- Modify: `STATUS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/game/system_completion_audit.md`

- [ ] **Step 1: Repoint `/STATUS.md`** — change the "Canonical status docs" table so the top entry is `docs/game/inventory/SYSTEM_INVENTORY.md` (+ `system_map.html`), with `system_completion_audit.md` listed as "superseded — see inventory." Update the "What's left" pointer to the inventory.

- [ ] **Step 2: Repoint project `CLAUDE.md`** — change the "Project status source of truth" line to lead with `docs/game/inventory/` (the generated inventory + map), keeping `STATUS.md` as the entry point.

- [ ] **Step 3: Fold + mark the audit** — add a banner to `docs/game/system_completion_audit.md`: "SUPERSEDED 2026-06-28 by `docs/game/inventory/` (code-verified, generated). Kept for narrative history." Do **not** delete (audit trail).

- [ ] **Step 4: Final regression sanity** — run the `--check` smoke once more and confirm the marker.

Run: `python tools/build_system_inventory.py --check`
Expected: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>`.

- [ ] **Step 5: Commit**

```bash
git add STATUS.md CLAUDE.md docs/game/system_completion_audit.md
git commit -m "docs(inventory): promote code-verified inventory to canonical; supersede audit"
```

---

## Notes for the executor

- **The bulk of the effort is Tasks 6–17** (the code-verified pass). Tasks 1–5 build the instrument; do them first and exactly (TDD). Do not start the data pass until `--check` works.
- **`?` blocks "done."** A `simulation` system left at `confidence:"?"` fails `--check` by design — that is the anti-drift guarantee. Trace it or downgrade honestly to `P` with a `content_note` explaining what's unverified, but prefer `V`.
- **Cite real lines.** Open the coordinator and confirm; the audit's numbers are hypotheses.
- This plan is the **inventory only**. The vision reset and roadmap are separate spec→plan cycles, started after the inventory's `--check` and `--coverage` both pass.
```
