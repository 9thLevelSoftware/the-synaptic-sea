# Equip-from-Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player equip an equippable that lives in a ship cargo hold or cart via a single right-click *Equip* or a drag onto an equipment slot — auto-transferring one unit into player inventory and equipping it atomically, with transfer-rollback on failure.

**Architecture:** All logic lives in `inventory_panel.gd` (which owns `_player_inv`, `_container`, `_equip`). Extract the selection-independent core of `equip_selected()` into `_equip_in_inventory(item_id)`, add `equip_from_container(item_id)` (move 1 unit hold→player, equip, roll the transfer back on equip failure), and reach it from two triggers: the right-click *Equip* on a container row and a drag of a container row onto an equipment slot. The resolver `InventorySelectionModel.context_actions` re-enables `equip` for container rows.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **No coordinator change, no persistence change.** Only `inventory_selection_model.gd` and `inventory_panel.gd` change in production; world-4 save format untouched. `_after_mutation()` already emits `transfer_completed` (the coordinator recomputes encumbrance + suit→oxygen).
- **Atomic with rollback.** On any failure (transfer rejected, can't equip, displaced occupant has no carry room) BOTH inventories end byte-identical to entry. Both steps are synchronous (no `await`).
- **Displaced occupant goes to the player's carry inventory**, not back to the hold — identical to existing equip semantics.
- **Keep the `context_actions` signature unchanged.** `row_is_container` stays a parameter (retained as pane context / forward-compat, as it originally was when named `dest_is_container`); the change is only that equip is no longer gated on it. Do NOT remove the param (7 call sites, positional-shift risk). If a reviewer flags it as unused, that is the human's call — do not remove it without asking.
- **Both edited smokes use `assert()` (existing style) — match it.** A failed `assert` does NOT abort a `--script` SceneTree run (it prints `Assertion failed: …` and execution continues to the PASS marker). So a smoke's RED state shows an `Assertion failed:`/runtime-error line and (for a missing method) no PASS marker; GREEN shows the PASS marker and no `Assertion failed:`/`SCRIPT ERROR` line.
- **Marker contracts:** `inventory_selection_model_smoke` keeps `INVENTORY SELECTION MODEL SMOKE PASS …`; `inventory_widget_smoke` extends its marker to `INVENTORY WIDGET SMOKE PASS section_a=true section_b=true section_c=true` (the bundle greps the `INVENTORY WIDGET SMOKE PASS` prefix, so this still matches). Both smokes are already bundle-registered → the bundle total stays **commands=119** (no new smoke).
- **Never stage/commit** `project.godot`, `.godot/`, `*.uid`, `addons/`. Selective `git add <explicit paths>` only.
- **Full bundle** must end `SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true`; stash `project.godot` before the run, pop after.
- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`. Branch: `equip-from-container`.

---

## File Structure

| File | Change |
|---|---|
| `scripts/systems/inventory_selection_model.gd` (modify) | `context_actions`: drop the `and not row_is_container` gate so container equippables offer `equip`; update docstring. |
| `scripts/ui/inventory_panel.gd` (modify) | Extract `_equip_in_inventory`; refactor `equip_selected`; add `equip_from_container`; wire the right-click + drag triggers. |
| `scripts/validation/inventory_selection_model_smoke.gd` (modify) | Flip the container-row assertion (now offers `equip`). |
| `scripts/validation/inventory_widget_smoke.gd` (modify) | Add Section C: right-click + drag + rollback. |
| `docs/game/adr/0026-equip-from-container.md` (new) | Record the feature. |
| `docs/game/09_system_roadmap.md` (modify) | System 6: move equip-from-container from *Remaining:* to built. |
| `docs/game/adr/0023-inventory-widget-layer.md` (modify) | One-line pointer: Amendment's deferred enhancement shipped as ADR-0026. |

Reference single-smoke run (bash):
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd 2>&1
```

---

### Task 1: Equip-from-container path (resolver + panel + both smokes)

**Files:**
- Modify: `scripts/systems/inventory_selection_model.gd` (`context_actions`, ~lines 77–95)
- Modify: `scripts/ui/inventory_panel.gd` (`equip_selected` ~146–167; `_on_context_id` ~324–337; `zone_can_accept` ~242–256; `zone_drop` ~258–273)
- Modify: `scripts/validation/inventory_selection_model_smoke.gd` (~lines 49–52)
- Modify: `scripts/validation/inventory_widget_smoke.gd` (`_init` + new `_run_section_c`)

**Interfaces:**
- Consumes: `CargoTransfer.move_item(src, dst, item_id: String, qty: int) -> int` (preloaded as `CargoTransferScript` in the panel); `EquipmentState.can_equip/equip`; `ItemDefsScript.equip_slot(_defs, item_id)`; `InventoryState`/`ShipInventory` `get_quantity/add_item/remove_item`.
- Produces (panel public methods used by the smokes): `equip_from_container(item_id: String) -> bool`; unchanged `equip_selected() -> bool`, `zone_can_accept(target, data) -> bool`, `zone_drop(target, data) -> void`, `_on_context_id(id, pane, index)`, `get_pane_ids(pane)`, `_ACT_EQUIP`.

**Note (anchors):** line numbers are from the current files; if they have drifted, locate by the function name and the quoted surrounding lines.

- [ ] **Step 1: Flip the selection-model smoke assertion (RED)**

In `scripts/validation/inventory_selection_model_smoke.gd`, replace lines ~49–52:

```gdscript
	# ...but suppressed for a CONTAINER row — equip_selected reads the SELF pane only, so offering
	# it there would no-op or equip the wrong item (PR #21 Codex P2).
	var container_row_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, true, true, false)
	assert(not ("equip" in Array(container_row_actions)), "container-pane equippable does NOT offer equip")
```

with:

```gdscript
	# ...and now ALSO offered for a CONTAINER row — equip-from-container auto-transfers one unit
	# into the player inventory and equips it atomically (ADR-0026, supersedes the ADR-0023 Amendment).
	var container_row_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, true, true, false)
	assert("equip" in Array(container_row_actions), "container-pane equippable offers equip (equip-from-container)")
```

- [ ] **Step 2: Run the selection-model smoke (verify RED)**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd 2>&1
```
Expected: an `Assertion failed: container-pane equippable offers equip …` line (the current `context_actions` still suppresses equip for container rows). The PASS marker may still print after it (assert does not abort) — the RED signal is the `Assertion failed:` line.

- [ ] **Step 3: Re-enable equip for container rows in the resolver (GREEN for the model smoke)**

In `scripts/systems/inventory_selection_model.gd`, change the transfer-mode equip gate (the only line referencing `row_is_container`):

```gdscript
		if equippable and not row_is_container:
			actions.append("equip")
```

to:

```gdscript
		if equippable:
			actions.append("equip")
```

And replace the method docstring (the `## Resolve the right-click menu action set …` block above the signature) with:

```gdscript
## Resolve the right-click menu action set for one row. `row_is_container` is true when the
## right-clicked row lives in the container pane; it is retained as pane context (as it was when
## first introduced as `dest_is_container`, forward-compat) but no longer gates equip. Equippable
## rows offer "equip" in BOTH panes: a SELF row equips directly; a CONTAINER row triggers
## equip-from-container — auto-transfer one unit into the player inventory, then equip atomically
## (ADR-0026).
```

Run the smoke again; expected: `INVENTORY SELECTION MODEL SMOKE PASS ids=2` and NO `Assertion failed:` line.

- [ ] **Step 4: Add Section C to the widget smoke (RED)**

In `scripts/validation/inventory_widget_smoke.gd`, change `_init()` to call the new section and extend the marker:

```gdscript
func _init() -> void:
	await _run_section_a()
	await _run_section_b()
	await _run_section_c()
	print("INVENTORY WIDGET SMOKE PASS section_a=true section_b=true section_c=true")
	quit()
```

Append this function (after `_run_section_b`):

```gdscript
func _run_section_c() -> void:
	# --- equip-from-container (ADR-0026): right-click Equip + drag-to-slot + rollback ---
	# Right-click "Equip" on a container row -> transfer one unit + equip.
	var inv = InventoryStateScript.new()
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("eva_backpack", 1)        # equippable (back), in the container only
	var equip = EquipmentStateScript.create()
	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)
	var ci := panel.get_pane_ids("container").find("eva_backpack")
	assert(ci >= 0, "eva_backpack present in the container pane")
	panel._on_context_id(panel._ACT_EQUIP, "container", ci)
	assert(equip.get_equipped("back") == "eva_backpack", "right-click equip-from-container equipped the backpack")
	assert(hold.get_quantity("eva_backpack") == 0, "container lost the equipped unit")
	assert(inv.get_quantity("eva_backpack") == 0, "equipped unit is worn, not left in carry")
	panel.queue_free()

	# Drag a container row onto its equipment slot -> equip-from-container.
	var inv2 = InventoryStateScript.new()
	var hold2 = ShipInventoryScript.create(1000.0)
	hold2.add_item("eva_backpack", 1)
	var equip2 = EquipmentStateScript.create()
	var panel2 = InventoryPanelScript.new()
	root.add_child(panel2)
	await process_frame
	panel2.open_transfer(inv2, hold2, "HOLD", equip2)
	var pay := {"from_pane": "container", "ids": ["eva_backpack"]}
	assert(panel2.zone_can_accept("slot:back", pay) == true, "back slot accepts a container backpack (equip-from-container)")
	panel2.zone_drop("slot:back", pay)
	assert(equip2.get_equipped("back") == "eva_backpack", "drag-from-container equipped the backpack")
	assert(hold2.get_quantity("eva_backpack") == 0, "container lost the dragged-equipped unit")
	panel2.queue_free()

	# Rollback: transfer succeeds but the displaced occupant has no carry room -> nothing moves.
	var inv3 = InventoryStateScript.new()
	inv3.add_item("eva_backpack", 1)            # carry already full of eva_backpack (max_stack 1)
	var hold3 = ShipInventoryScript.create(1000.0)
	hold3.add_item("field_pack", 1)             # a second back-slot item, in the container
	var equip3 = EquipmentStateScript.create()
	equip3.equip("eva_backpack")                # back slot occupied
	var panel3 = InventoryPanelScript.new()
	root.add_child(panel3)
	await process_frame
	panel3.open_transfer(inv3, hold3, "HOLD", equip3)
	assert(panel3.equip_from_container("field_pack") == false, "equip-from-container fails when the displaced occupant cannot return")
	assert(equip3.get_equipped("back") == "eva_backpack", "worn slot unchanged after rollback")
	assert(hold3.get_quantity("field_pack") == 1, "container unit restored after rollback")
	assert(inv3.get_quantity("field_pack") == 0, "transferred unit rolled back out of carry")
	assert(inv3.get_quantity("eva_backpack") == 1, "carry untouched after rollback")
	panel3.queue_free()
```

- [ ] **Step 5: Run the widget smoke (verify RED)**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd 2>&1
```
Expected: FAIL — `panel3.equip_from_container(...)` is a nonexistent method, producing a `SCRIPT ERROR`/`Invalid call. Nonexistent function 'equip_from_container'` line, and the `INVENTORY WIDGET SMOKE PASS` marker is ABSENT (and/or `Assertion failed:` lines for the right-click/drag cases).

- [ ] **Step 6: Implement the panel — extract `_equip_in_inventory` + refactor `equip_selected`**

In `scripts/ui/inventory_panel.gd`, replace the whole `equip_selected()` function (the `## Equips the single selected …` docstring through its closing `return true`) with:

```gdscript
## Equips the single selected carry-list item into its slot. The item leaves the carry
## list (worn != carried); any displaced occupant returns to the carry list.
func equip_selected() -> bool:
	if _player_inv == null or _equip == null:
		return false
	var sel: Array = _sel_self.get_selected_ids()
	if sel.size() != 1:
		return false
	if _equip_in_inventory(String(sel[0])):
		_after_mutation()
		return true
	return false

## Atomic equip of an item that is ALREADY in the player carry list. Returns true on success;
## on any failure (absent / can't equip / no carry room for a displaced occupant) it leaves the
## player inventory and equipment byte-identical to entry. Shared by equip_selected() and
## equip_from_container(). Does NOT call _after_mutation — the caller does, once.
func _equip_in_inventory(item_id: String) -> bool:
	if _player_inv == null or _equip == null:
		return false
	if _player_inv.get_quantity(item_id) <= 0 or not _equip.can_equip(item_id):
		return false
	var res: Dictionary = _equip.equip(item_id)
	if not bool(res.get("ok", false)):
		return false
	var displaced: String = str(res.get("displaced", ""))
	if displaced != "":
		if int(_player_inv.add_item(displaced, 1)) < 1:
			# No carry room for the displaced item — abort atomically so nothing is lost.
			# item_id was NOT removed from inventory yet; restore the slot to displaced.
			_equip.equip(displaced)
			return false
	_player_inv.remove_item(item_id, 1)
	return true

## Equip-from-container (ADR-0026): auto-transfer one unit of an equippable from the container
## (hold/cart) into the player inventory, then equip it atomically. On equip failure the transfer
## is rolled back, leaving BOTH inventories byte-identical to entry. Returns true on success.
func equip_from_container(item_id: String) -> bool:
	if _container == null or _player_inv == null or _equip == null:
		return false
	if ItemDefsScript.equip_slot(_defs, item_id).is_empty():
		return false
	if int(_container.get_quantity(item_id)) <= 0:
		return false
	if int(CargoTransferScript.move_item(_container, _player_inv, item_id, 1)) < 1:
		return false   # transfer failed (e.g. player stack full) — nothing changed
	if _equip_in_inventory(item_id):
		_after_mutation()
		return true
	# Equip failed after the transfer — roll the unit back into the container.
	CargoTransferScript.move_item(_player_inv, _container, item_id, 1)
	return false
```

- [ ] **Step 7: Implement the panel — wire the right-click trigger**

In `_on_context_id`, replace the `_ACT_EQUIP` branch (the `elif id == _ACT_EQUIP:` block, including its two-line SELF-only comment) with:

```gdscript
	elif id == _ACT_EQUIP:
		if pane == "container":
			# Equip-from-container: transfer one unit into the player inventory, then equip (ADR-0026).
			var ids: Array = _ids_for_pane("container")
			if index >= 0 and index < ids.size():
				equip_from_container(String(ids[index]))
		else:
			_model_for_pane(pane).select_single(index)
			equip_selected()
```

- [ ] **Step 8: Implement the panel — wire the drag-to-slot trigger**

In `zone_can_accept`, in the `if target.begins_with("slot:"):` branch, replace the guard line:

```gdscript
		if from_pane != "self":
			return false   # equip only from your own inventory
```

with:

```gdscript
		if from_pane != "self" and from_pane != "container":
			return false   # equip only from your own inventory or a container (equip-from-container)
```

In `zone_drop`, replace the whole `if target.begins_with("slot:"):` branch with:

```gdscript
	if target.begins_with("slot:"):
		if from_pane != "self" and from_pane != "container":
			return
		var slot: String = target.substr(5)
		for id in ((data as Dictionary).get("ids", []) as Array):
			if _equip != null and ItemDefsScript.equip_slot(_defs, String(id)) == slot:
				if from_pane == "container":
					equip_from_container(String(id))
				else:
					_sel_self.select_single(_ids_for_pane("self").find(String(id)))
					equip_selected()
				return
		return
```

- [ ] **Step 9: Run both smokes (verify GREEN)**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd 2>&1
```
Expected: `INVENTORY SELECTION MODEL SMOKE PASS ids=2` and `INVENTORY WIDGET SMOKE PASS section_a=true section_b=true section_c=true`, with no `Assertion failed:` / `SCRIPT ERROR` lines beyond the allowlisted baseline noise (`Capture not registered: 'gdaimcp'`, `ObjectDB instances leaked at exit`, and the single-run project.godot-drift trio `Unrecognized UID` / `Resource file not found: res://` / `Failed to instantiate an autoload 'MCPRuntime'`).

- [ ] **Step 10: Commit**

```bash
git add scripts/systems/inventory_selection_model.gd scripts/ui/inventory_panel.gd scripts/validation/inventory_selection_model_smoke.gd scripts/validation/inventory_widget_smoke.gd
git commit -m "feat(inventory): equip-from-container (right-click + drag, atomic transfer-then-equip)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Docs — ADR-0026, roadmap, ADR-0023 pointer, full bundle

**Files:**
- Create: `docs/game/adr/0026-equip-from-container.md`
- Modify: `docs/game/09_system_roadmap.md` (System 6 row)
- Modify: `docs/game/adr/0023-inventory-widget-layer.md` (Amendment section)

**Interfaces:** none (documentation + bundle verification only).

- [ ] **Step 1: Write ADR-0026**

Create `docs/game/adr/0026-equip-from-container.md`:

```markdown
# ADR-0026: Equip-from-Container

Date: 2026-06-24
Status: Accepted
Phase: 7 (Integration & Polish)

## Context

ADR-0023's Amendment shipped equipment as player-inventory-scoped: container
(ship-hold / cart) rows did not offer *Equip*, and equipment slots rejected
container-pane drops, so equipping a salvaged item meant a manual
transfer-then-equip. The Amendment recorded equip-from-container as the
accepted, deferred end-state.

## Decision

A single `InventoryPanel.equip_from_container(item_id)` performs a
Project-Zomboid-style atomic transfer-then-equip: `CargoTransfer.move_item`
moves one unit from the container into the player inventory, then the item is
equipped via the shared `_equip_in_inventory(item_id)` core (extracted from
`equip_selected()`); if the equip fails, the transfer is rolled back so BOTH
inventories end byte-identical to entry. The displaced worn item goes to the
player's carry inventory (reusing the existing equip semantics).

Two triggers reach it: the right-click *Equip* on a container row
(`context_actions` now offers `equip` for container equippables;
`_on_context_id` routes the container pane through `equip_from_container`), and
a drag of a container row onto an equipment slot (`zone_can_accept` /
`zone_drop` accept a `from_pane == "container"` payload). This supersedes the
ADR-0023 Amendment's interim "container rows don't offer Equip."

## Consequences

- No coordinator or persistence change; `_after_mutation()` already fires the
  coordinator's `transfer_completed` encumbrance + suit→oxygen recompute.
- Failure paths (transfer rejected, can't equip, displaced occupant has no
  carry room) all leave both inventories unchanged.
- Covered by `inventory_selection_model_smoke` (container row now offers equip)
  and `inventory_widget_smoke` Section C (right-click, drag, and the
  displaced-no-room rollback); regression bundle stays commands=119.

## Deferred

- Equipping more than one unit / auto-selecting the "best" item.
- A cart-both-hands gate on the panel equip path (it has none today).
```

- [ ] **Step 2: Update the system roadmap**

In `docs/game/09_system_roadmap.md`, in the System 6 row: (a) append to the built-list (right after the `… — ADR-0025 ✅` clause, before `. *Remaining:*`):

```
; equip-from-container (right-click Equip + drag-to-slot, atomic transfer-then-equip with rollback) — ADR-0026 ✅
```

(b) In the same cell's `*Remaining:*` list, delete the equip-from-container clause exactly:

```
equip-from-container (auto-transfer-one-unit-then-equip, PZ-style — accepted enhancement; equip is currently player-inventory-scoped, so right-clicking a container row does not offer Equip — ADR-0023 Amendment), 
```

(remove that clause and its trailing comma+space, leaving the list starting at `item-icon generation, …`).

- [ ] **Step 3: Point the ADR-0023 Amendment at ADR-0026**

In `docs/game/adr/0023-inventory-widget-layer.md`, at the end of the Amendment section (after the implementation-sketch paragraph), add:

```markdown

**Shipped (2026-06-24):** the deferred equip-from-container enhancement is now implemented per
this sketch — see ADR-0026. Container equippable rows offer *Equip* again, and equipment slots
accept container-pane drags.
```

- [ ] **Step 4: Run the full regression bundle (stash the project.godot drift first)**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
export GODOT ROOT
git stash push -- project.godot
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' docs/game/06_validation_plan.md)
status=$?
git stash pop
echo "bundle exit=$status"
```
Expected final line: `SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true`. (If `git stash push` reports "No local changes to save," skip the `git stash pop`.) If the bundle does not end with that exact line, STOP and report BLOCKED with the failing output — do not edit unrelated smokes.

- [ ] **Step 5: Commit**

```bash
git add docs/game/adr/0026-equip-from-container.md docs/game/09_system_roadmap.md docs/game/adr/0023-inventory-widget-layer.md
git commit -m "docs(inventory): ADR-0026 equip-from-container + roadmap + ADR-0023 pointer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Plan Self-Review

- **Spec coverage:** resolver re-enable (T1 S3); `_equip_in_inventory` extraction + `equip_selected` refactor (T1 S6); `equip_from_container` with rollback (T1 S6); right-click trigger (T1 S7); drag trigger (T1 S8); selection-model assertion flip (T1 S1–S3); widget smoke right-click/drag/rollback (T1 S4–S5,S9); ADR-0026 + roadmap + Amendment pointer (T2); bundle 119 (T2 S4). All spec sections map to a step.
- **Type consistency:** `equip_from_container(item_id: String) -> bool`, `_equip_in_inventory(item_id: String) -> bool` consistent across panel + smoke; `CargoTransferScript.move_item(...)`, `ItemDefsScript.equip_slot(_defs, …)`, `_container`/`_player_inv`/`_equip` match the panel's existing members; the widget marker `section_c=true` matches the `_init` print.
- **Placeholder scan:** none; every code step carries full code; every run step carries the exact command + expected marker.
- **Known soft spot:** line-number anchors are from the current files; if drifted, locate by function name and the quoted surrounding lines. `row_is_container` is intentionally retained as an un-branched parameter (Global Constraints) — not a defect to "fix" by deletion without asking.
