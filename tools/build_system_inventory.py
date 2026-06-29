#!/usr/bin/env python3
"""Generate the Synaptic Sea system inventory: validate JSON, compute completion,
render SYSTEM_INVENTORY.md + system_map.html. Stdlib only."""
import json, sys, os, math

WEIGHTS = {"model": 15, "reachable": 15, "driven": 15, "coupled": 35, "content": 20}
_CONTENT = {"none": 0.0, "partial": 0.5, "sufficient": 1.0}

def _round(x):
    # round-half-up (Python's built-in round() is banker's rounding; the spec's
    # worked examples — 62.5 -> 63, 81.5 -> 82 — assume half-up).
    return int(math.floor(x + 0.5))

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
    return _round(score)

def system_completion(s):
    subs = s.get("subsystems") or []
    if subs:
        vals = [system_completion(x) for x in subs]
        vals = [v for v in vals if v is not None]
        return _round(sum(vals) / len(vals)) if vals else None
    return leaf_completion(s)
