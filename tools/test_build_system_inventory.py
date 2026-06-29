import json
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
