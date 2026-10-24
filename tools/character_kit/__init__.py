"""Procedural Blender character kit tooling for The Synaptic Sea.

Host Python may import ``character_kit_spec`` and ``validate_character_glb``
without Blender. ``build_survivor_kit`` and ``render_character_previews`` are
Blender-only entry points and import ``bpy`` lazily at runtime.
"""
