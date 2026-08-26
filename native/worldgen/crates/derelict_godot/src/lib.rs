//! GDExtension bridge: exposes `derelict_core` generation to Godot.
//!
//! All generation logic lives in `derelict_core`; this crate only marshals
//! data. Worker threads touch only plain `Send` Rust data — Godot objects
//! are constructed exclusively on the main thread during `poll_async`.

use godot::prelude::*;

mod async_gen;
mod convert;
mod generator;
mod service;

#[cfg(test)]
#[path = "../build_support.rs"]
mod build_support_tests;
#[cfg(test)]
mod generator_tests;
#[cfg(test)]
mod service_tests;

struct DerelictExtension;

#[gdextension]
unsafe impl ExtensionLibrary for DerelictExtension {}
