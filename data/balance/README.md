# Balance tuning (`data/balance/`)

Externalized gameplay numbers for the Synaptic Sea.

## Convention

- `TuningCatalog` (`scripts/systems/tuning_catalog.gd`) loads `*.json` files in this directory.
- Nested JSON objects are flattened to dotted keys (`fire.spread_rate` → key `"fire.spread_rate"`).
- Code keeps **const fallback defaults**; catalog overrides when a key is present.
- **Do not** mass-migrate the coordinator in one PR. Each feature package moves its own numbers when touched (pre-polish plan PKG-A4).

## Example

```json
{
  "vitals": {
    "stamina_drain_rate": 2.0
  },
  "fire": {
    "module_damage_per_second": 0.5
  }
}
```

## Shell file

`shell.json` is intentionally minimal — it proves the load path for smokes without claiming balance ownership of live systems.
