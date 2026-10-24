"""Procedural keyframe authoring for the survivor rig (Blender-only).

Clips are authored as Actions and pushed to named NLA tracks so the glTF
exporter (``export_animation_mode='NLA_TRACKS'``) writes one glTF animation
per track, named after the track. Godot imports names ending in ``-loop`` as
looping animations.

Bone-space conventions for this rig (roll 0 everywhere):
- Limb bones point straight down in rest (-Z world). Their local +X is world
  +X and local +Z is world +Y (the character's BACK), so a NEGATIVE rotation
  about local X swings the limb FORWARD (toward -Y / glTF +Z).
- Torso/neck/head bones point up (+Z world). Their local +Z is world -Y
  (FORWARD), so a POSITIVE rotation about local X leans FORWARD.
- Rotation about a bone's local Z abducts a down-pointing limb sideways.
"""

from __future__ import annotations

import math
from typing import Callable, Dict, Tuple

TAU = math.tau
Euler3 = Tuple[float, float, float]


def _deg(x: float) -> float:
    return math.radians(x)


# Pose helpers return {bone: (rx, ry, rz)} radians plus optional hips offset.
def _limb_forward(angle_deg: float) -> Euler3:
    return (-_deg(angle_deg), 0.0, 0.0)


def _torso_forward(angle_deg: float) -> Euler3:
    return (_deg(angle_deg), 0.0, 0.0)


def _abduct(angle_deg: float, side: str) -> Euler3:
    sign = 1.0 if side == "L" else -1.0
    return (0.0, 0.0, -_deg(angle_deg) * sign)


def _add(a: Euler3, b: Euler3) -> Euler3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _crouch_base() -> Dict[str, Euler3]:
    pose: Dict[str, Euler3] = {}
    for side in ("L", "R"):
        pose[f"thigh_{side}"] = _limb_forward(70.0)
        pose[f"shin_{side}"] = _limb_forward(-95.0)
        pose[f"foot_{side}"] = _limb_forward(10.0)
        pose[f"upper_arm_{side}"] = _add(_limb_forward(20.0), _abduct(8.0, side))
        pose[f"forearm_{side}"] = _limb_forward(35.0)
    pose["hips"] = _torso_forward(10.0)
    pose["spine"] = _torso_forward(12.0)
    pose["chest"] = _torso_forward(10.0)
    pose["neck"] = _torso_forward(-12.0)
    pose["head"] = _torso_forward(-14.0)
    return pose


CROUCH_HIPS_DROP = 0.36  # meters, along the hips bone's local -Y (down)


def _idle(t: float) -> Tuple[Dict[str, Euler3], Tuple[float, float, float]]:
    breathe = math.sin(t * TAU)
    pose = {
        "chest": _torso_forward(1.5 * breathe),
        "spine": _torso_forward(0.8 * breathe),
        "head": (_deg(1.0 * math.sin(t * TAU + 1.0)), _deg(2.0 * math.sin(t * TAU * 0.5)), 0.0),
    }
    for side in ("L", "R"):
        pose[f"upper_arm_{side}"] = _add(_limb_forward(2.0 * breathe), _abduct(4.0, side))
        pose[f"forearm_{side}"] = _limb_forward(6.0 + 1.5 * breathe)
    return pose, (0.0, -0.004 * (1.0 - breathe), 0.0)


def _walk(t: float, amplitude: float = 1.0, crouch: bool = False):
    phase = t * TAU
    pose = _crouch_base() if crouch else {}
    swing = (32.0 if not crouch else 14.0) * amplitude
    arm_swing = (26.0 if not crouch else 10.0) * amplitude
    for side, sign in (("L", 1.0), ("R", -1.0)):
        leg = math.sin(phase) * sign
        thigh = swing * leg
        # Knee bends only while the leg travels back-to-front (lift phase).
        lift = max(0.0, -math.sin(phase + 0.9) * sign)
        shin = -(50.0 if not crouch else 25.0) * lift * amplitude
        base_thigh = pose.get(f"thigh_{side}", (0.0, 0.0, 0.0))
        base_shin = pose.get(f"shin_{side}", (0.0, 0.0, 0.0))
        pose[f"thigh_{side}"] = _add(base_thigh, _limb_forward(thigh))
        pose[f"shin_{side}"] = _add(base_shin, _limb_forward(shin))
        pose[f"foot_{side}"] = _add(pose.get(f"foot_{side}", (0.0, 0.0, 0.0)), _limb_forward(8.0 * lift))
        arm = -math.sin(phase) * sign * arm_swing
        base_arm = pose.get(f"upper_arm_{side}", (0.0, 0.0, 0.0))
        pose[f"upper_arm_{side}"] = _add(base_arm, _add(_limb_forward(arm), _abduct(5.0, side)))
        base_fore = pose.get(f"forearm_{side}", (0.0, 0.0, 0.0))
        pose[f"forearm_{side}"] = _add(base_fore, _limb_forward(14.0 + 10.0 * max(0.0, math.sin(phase) * sign)))
    lean = 4.0 if not crouch else 0.0
    twist = _deg(4.0 * math.sin(phase))
    pose["chest"] = _add(pose.get("chest", (0.0, 0.0, 0.0)), (_deg(lean), twist, 0.0))
    pose["hips"] = _add(pose.get("hips", (0.0, 0.0, 0.0)), (0.0, -twist * 0.6, 0.0))
    bob = 0.025 * abs(math.sin(phase))
    drop = -CROUCH_HIPS_DROP if crouch else 0.0
    return pose, (0.0, drop + bob, 0.0)


def _crouch_idle(t: float):
    pose = _crouch_base()
    breathe = math.sin(t * TAU)
    pose["chest"] = _add(pose["chest"], _torso_forward(1.5 * breathe))
    return pose, (0.0, -CROUCH_HIPS_DROP - 0.003 * (1.0 - breathe), 0.0)


def _work(t: float):
    phase = t * TAU
    pose = {
        "spine": _torso_forward(14.0),
        "chest": _torso_forward(16.0 + 2.0 * math.sin(phase)),
        "neck": _torso_forward(8.0),
        "head": _torso_forward(14.0),
    }
    for side in ("L", "R"):
        pose[f"upper_arm_{side}"] = _add(_limb_forward(48.0 + 6.0 * math.sin(phase)), _abduct(6.0, side))
        pose[f"forearm_{side}"] = _limb_forward(38.0 + 12.0 * math.sin(phase + (0.0 if side == "R" else 0.7)))
        pose[f"hand_{side}"] = _limb_forward(6.0 * math.sin(phase * 2.0))
    return pose, (0.0, -0.02, 0.0)


def _melee(t: float):
    # Windup (0-0.35), swing (0.35-0.6), recover (0.6-1.0) with the right arm.
    if t < 0.35:
        k = t / 0.35
        arm = -40.0 * k
        abduct = 70.0 * k
        twist = -18.0 * k
        fore = 60.0 * k
    elif t < 0.6:
        k = (t - 0.35) / 0.25
        arm = -40.0 + 125.0 * k
        abduct = 70.0 - 40.0 * k
        twist = -18.0 + 40.0 * k
        fore = 60.0 - 45.0 * k
    else:
        k = (t - 0.6) / 0.4
        arm = 85.0 * (1.0 - k)
        abduct = 30.0 * (1.0 - k)
        twist = 22.0 * (1.0 - k)
        fore = 15.0 * (1.0 - k)
    pose = {
        "upper_arm_R": _add(_limb_forward(arm), _abduct(abduct, "R")),
        "forearm_R": _limb_forward(fore),
        "upper_arm_L": _add(_limb_forward(18.0), _abduct(12.0, "L")),
        "forearm_L": _limb_forward(45.0),
        "chest": (_deg(8.0), _deg(twist), 0.0),
        "hips": (0.0, _deg(-twist * 0.5), 0.0),
        "thigh_L": _limb_forward(12.0),
        "thigh_R": _limb_forward(-10.0),
        "shin_L": _limb_forward(-16.0),
    }
    return pose, (0.0, -0.03, 0.0)


def _aim(t: float):
    k = min(1.0, t / 0.4)
    pose = {
        "upper_arm_R": _add(_limb_forward(88.0 * k), _abduct(2.0, "R")),
        "forearm_R": _limb_forward(2.0 * k),
        "hand_R": _limb_forward(-6.0 * k),
        "upper_arm_L": _add(_limb_forward(70.0 * k), _abduct(-16.0, "L")),
        "forearm_L": _limb_forward(40.0 * k),
        "chest": (_deg(4.0 * k), _deg(-12.0 * k), 0.0),
        "head": (0.0, _deg(10.0 * k), 0.0),
        "thigh_L": _limb_forward(10.0 * k),
        "thigh_R": _limb_forward(-8.0 * k),
    }
    return pose, (0.0, -0.02 * k, 0.0)


def _downed(t: float):
    k = min(1.0, t / 0.6)
    ease = 1.0 - (1.0 - k) ** 2
    pose = {
        # Fall onto the back: the hips rotate -90 deg about local X (lean back)
        # and drop to the floor; children follow.
        "hips": (-_deg(88.0 * ease), _deg(6.0 * ease), 0.0),
        "spine": _torso_forward(6.0 * ease),
        "chest": _torso_forward(4.0 * ease),
        "neck": _torso_forward(-6.0 * ease),
        "head": _torso_forward(-10.0 * ease),
        "upper_arm_L": _add(_limb_forward(-10.0 * ease), _abduct(40.0 * ease, "L")),
        "upper_arm_R": _add(_limb_forward(-6.0 * ease), _abduct(55.0 * ease, "R")),
        "forearm_L": _limb_forward(30.0 * ease),
        "forearm_R": _limb_forward(50.0 * ease),
        "thigh_L": _add(_limb_forward(8.0 * ease), _abduct(10.0 * ease, "L")),
        "thigh_R": _add(_limb_forward(-4.0 * ease), _abduct(14.0 * ease, "R")),
        "shin_L": _limb_forward(-25.0 * ease),
    }
    return pose, (0.0, -0.80 * ease, 0.0)


CLIP_FUNCTIONS: Dict[str, Callable[[float], Tuple[Dict[str, Euler3], Tuple[float, float, float]]]] = {
    "idle-loop": _idle,
    "walk-loop": lambda t: _walk(t),
    "crouch_idle-loop": _crouch_idle,
    "crouch_walk-loop": lambda t: _walk(t, amplitude=1.0, crouch=True),
    "work-loop": _work,
    "melee_swing": _melee,
    "aim_ranged": _aim,
    "downed": _downed,
}


def author_animations(bpy, armature, spec) -> None:
    missing = set(spec.ANIMATION_NAMES) - set(CLIP_FUNCTIONS)
    if missing:
        raise RuntimeError(f"no pose function for clips {sorted(missing)}")

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    for pbone in armature.pose.bones:
        pbone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")

    if armature.animation_data is None:
        armature.animation_data_create()
    anim = armature.animation_data

    for clip_name in spec.ANIMATION_NAMES:
        frames = int(spec.ANIMATION_CLIPS[clip_name]["frames"])
        loop = bool(spec.ANIMATION_CLIPS[clip_name]["loop"])
        pose_fn = CLIP_FUNCTIONS[clip_name]
        action = bpy.data.actions.new(clip_name)
        action.use_fake_user = True
        anim.action = action
        for frame in range(0, frames + 1):
            # For loops the last frame equals the first (t wraps); non-loops hold.
            t = (frame / frames) if loop else min(1.0, frame / max(1, frames))
            if loop and frame == frames:
                t = 0.0
            pose, hips_offset = pose_fn(t)
            for pbone in armature.pose.bones:
                rot = pose.get(pbone.name, (0.0, 0.0, 0.0))
                pbone.rotation_euler = rot
                pbone.keyframe_insert("rotation_euler", frame=frame + 1)
                if pbone.name == "hips":
                    pbone.location = hips_offset
                    pbone.keyframe_insert("location", frame=frame + 1)
        for fcurve in action.fcurves:
            for keyframe in fcurve.keyframe_points:
                keyframe.interpolation = "LINEAR" if not loop else "BEZIER"
        track = anim.nla_tracks.new()
        track.name = clip_name
        strip = track.strips.new(clip_name, 1, action)
        strip.name = clip_name
        strip.action_frame_start = 1
        strip.action_frame_end = frames + 1
        strip.frame_end = frames + 1
        track.mute = False
        anim.action = None

    # Reset the rest pose so the export (export_rest_position_armature) and
    # any later preview render start from a clean T-less A-pose.
    for pbone in armature.pose.bones:
        pbone.rotation_euler = (0.0, 0.0, 0.0)
        pbone.location = (0.0, 0.0, 0.0)
    bpy.context.scene.frame_set(1)
