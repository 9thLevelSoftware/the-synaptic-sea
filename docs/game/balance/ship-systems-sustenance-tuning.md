# Ship systems sustenance tuning notes

Date: 2026-06-25
Task: `t_290ec958`

## Initial tuning envelope
- Power grid supply: 100 units total.
- Baseline demand bands:
  - life_support: 22
  - propulsion: 30
  - shields: 18
  - stations: 12
  - lights: 8
  - sustenance: 10
- Minimum operational ratio: 50% of demand.
- Life-support offline oxygen drain: 4%/s baseline, multiplied by breach count pressure.
- Life-support online oxygen recovery: 2%/s baseline.
- Fire suppression baseline: 100 suppressant units, 25 intensity-units/s nominal clearing.

## Follow-up tuning questions
- Whether propulsion should remain binary at 50% power threshold or scale travel range by partial thrust.
- Whether hull breaches should be synchronized with existing OxygenState zone ids instead of compartment-only bookkeeping.
- Whether station and light blackouts need dedicated scene-side consequences beyond tracker/status output.
