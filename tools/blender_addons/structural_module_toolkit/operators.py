"""Button operators for the Structural Module Toolkit.

These operators deliberately provide the UI contract and status plumbing first;
actual contract IO, GLB import/export, helper generation, and validation are
implemented by later toolkit tasks.
"""

from __future__ import annotations

import bpy


def _set_status(context, message: str) -> None:
    """Update the panel status when the toolkit scene property is available."""
    scene = getattr(context, "scene", None)
    if scene is not None and hasattr(scene, "structural_status"):
        scene.structural_status = message


def _module_summary(context) -> str:
    scene = getattr(context, "scene", None)
    if scene is None:
        return "<no scene>"
    module_id = getattr(scene, "structural_module_id", "<unset>")
    family = getattr(scene, "structural_module_family", "<unset>")
    grid_x = getattr(scene, "structural_grid_size_x", "<unset>")
    grid_y = getattr(scene, "structural_grid_size_y", "<unset>")
    return f"module_id={module_id!r}, family={family!r}, grid={grid_x}x{grid_y}"


class STRUCTURAL_OT_load_contract(bpy.types.Operator):
    """Load or create the selected module contract JSON."""

    bl_idname = "structural.load_contract"
    bl_label = "Load Contract"
    bl_description = "Load or create the selected structural module contract JSON"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        message = "Load Contract stub executed"
        print(f"[Structural Module Toolkit] {message}: {_module_summary(context)}")
        _set_status(context, "Contract ready (stub)")
        self.report({"INFO"}, message)
        return {"FINISHED"}


class STRUCTURAL_OT_import_glb(bpy.types.Operator):
    """Import the selected runtime GLB into the current scene."""

    bl_idname = "structural.import_glb"
    bl_label = "Import GLB"
    bl_description = "Import the selected runtime structural module GLB"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        message = "Import GLB stub executed"
        print(f"[Structural Module Toolkit] {message}: {_module_summary(context)}")
        _set_status(context, "GLB imported (stub)")
        self.report({"INFO"}, message)
        return {"FINISHED"}


class STRUCTURAL_OT_generate_helpers(bpy.types.Operator):
    """Generate socket empties and a collision proxy for the current module."""

    bl_idname = "structural.generate_helpers"
    bl_label = "Generate Helpers"
    bl_description = "Add socket empties and a collision proxy for the current module"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        message = "Generate Helpers stub executed"
        print(f"[Structural Module Toolkit] {message}: {_module_summary(context)}")
        _set_status(context, "Helpers generated (stub)")
        self.report({"INFO"}, message)
        return {"FINISHED"}


class STRUCTURAL_OT_export_glb(bpy.types.Operator):
    """Export the current module GLB to the configured staging directory."""

    bl_idname = "structural.export_glb"
    bl_label = "Export GLB"
    bl_description = "Export the current structural module GLB to the staging directory"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        message = "Export GLB stub executed"
        print(f"[Structural Module Toolkit] {message}: {_module_summary(context)}")
        _set_status(context, "GLB exported (stub)")
        self.report({"INFO"}, message)
        return {"FINISHED"}


class STRUCTURAL_OT_validate(bpy.types.Operator):
    """Run the structural module inspector on the current scene."""

    bl_idname = "structural.validate"
    bl_label = "Validate"
    bl_description = "Run the structural module inspector on the current scene"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        message = "Validate stub executed"
        print(f"[Structural Module Toolkit] {message}: {_module_summary(context)}")
        _set_status(context, "Validation complete (stub)")
        self.report({"INFO"}, message)
        return {"FINISHED"}


CLASSES = (
    STRUCTURAL_OT_load_contract,
    STRUCTURAL_OT_import_glb,
    STRUCTURAL_OT_generate_helpers,
    STRUCTURAL_OT_export_glb,
    STRUCTURAL_OT_validate,
)
