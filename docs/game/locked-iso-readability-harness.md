# Locked-Isometric Readability Proof Harness

This harness renders the fixed orthographic/isometric camera against four synthetic wrapper scenes so reviewers can verify readability with an actual preview image, not just validator output.

## Canonical camera

- Scene: `res://scenes/validation/locked_iso_readability_harness.tscn`
- Camera node: `ValidationCamera`
- Transform: `Transform3D(0.707107, -0.408248, 0.57735, 0, 0.816497, 0.57735, -0.707107, -0.408248, 0.57735, 16, 14, 16)`
- Projection: orthographic
- Orthographic size: `18.0`
- Fixed test resolution: `1600x900`

The angle is the canonical locked-isometric view used by the project bootstrap scene: a 35.264° down tilt with a 45° compass-facing bias.

## Sample placement layout

The harness places four wrapper instances in a symmetric grid around the origin:

- structural: upper-left quadrant
- gameplay prop: upper-right quadrant
- dressing: lower-left quadrant
- character: lower-right quadrant

Each sample uses a simple primitive preview mesh so the preview image shows readable silhouette differences even without imported production art.

## Validation preview output

Primary preview file:

`/Users/christopherwilloughby/the-synapse-sea-of-stars/artifacts/validation-previews/locked-iso-readability.png`

## Screenshot / preview command

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2   --windowed   --resolution 1600x900   --path /Users/christopherwilloughby/the-synapse-sea-of-stars   --scene res://scenes/validation/locked_iso_readability_harness.tscn   --write-movie /Users/christopherwilloughby/the-synapse-sea-of-stars/artifacts/validation-previews/locked-iso-readability.png   --quit-after 1
```

On this machine, Godot's movie-maker output writes a numbered frame sequence. Copy the first frame (for example `locked-iso-readability00000000.png`) to the canonical preview path above so the validation preview has a stable filename. If the screenshot command is unavailable on a given machine, use the same scene and the checklist below.

## Manual playtest checklist

1. Open `res://scenes/validation/locked_iso_readability_harness.tscn`.
2. Confirm the camera stays locked to the orthographic/isometric angle.
3. Confirm all four wrapper silhouettes remain readable in the same framing.
4. Confirm the preview is legible at `1600x900` without changing lighting or art direction.
5. Save a screenshot to the output path above and label it as a validation preview.
