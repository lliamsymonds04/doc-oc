---
name: godot-vfx
description: Build and debug Godot VFX in this project — particle impacts, projectile trails, charge-up tells, surface-oriented bursts. Use when adding or fixing visual effects, GPUParticles3D scenes, VFX materials, or when an effect renders in the editor but not in game.
---

# Godot VFX in doc-oc

## Asset source

The Kenney VFX pack lives **outside** the project at:

```
/home/lliam/gamedev/assets/vfx/kenny_vfx/
```

512×512 RGBA PNGs. Godot cannot import from outside `res://`, so copy only the
textures you need into `assets/textures/`, then run `godot --headless --import`
(commit the generated `.import` files).

Already imported in this project: `circle_05_a`, `smoke_03_a`, `trace_02_a`,
`trace_07_a`.

| Need | Texture |
|---|---|
| fireball core, fire burst | `fire_01_a`, `fire_02_a` |
| flame sprites for trails | `flame_01_a` … `flame_06_a` |
| upward flame jet, muzzle burst | `muzzle_01_a` … `muzzle_05_a` |
| charge glow, soft ring | `light_01_a`, `light_02_a`, `circle_05_a` |
| hard rings (shockwave) | `circle_01_a` … `circle_04_a` |
| sparks / lightning | `spark_01_a` … `spark_07_a` |
| streaks (fast trails) | `trace_01_a` … `trace_07_a` |
| smoke puffs | `smoke_01_a` … `smoke_10_a` |
| ground crack / scorch | `scorch_01_a` … `scorch_03_a`, `ground_crack.png` |
| star / twirl / magic | `star_01_a`, `twirl_01_a`, `magic_01_a` |

## House patterns

### One-shot burst (impact, explosion)

- Root `Node3D` with `assets/vfx/oneshot_vfx.gd` (`OneShotVFX`), or
  `assets/vfx/impact_vfx.gd` (`ImpactVFX`) when it must sit on a surface.
- `ImpactVFX.play(pos, normal)` orients the burst off the surface normal and
  calls `restart_emitters()`.
- Emitters: `emitting = false`, `one_shot = true`, `explosiveness = 1.0`,
  `fixed_fps = 0`.
- Call `play()` **after** `add_child()`, and parent to
  `get_tree().current_scene` so the burst outlives the projectile/enemy that
  spawned it.

Emitter draw material (`material_override` on the `GPUParticles3D`):

```
transparency = 1
blend_mode = 1                  # additive: fire, sparks. Omit for smoke.
shading_mode = 0                # unshaded
billboard_mode = 3              # BILLBOARD_PARTICLES
vertex_color_use_as_albedo = true
albedo_texture = <texture>
```

Draw pass is a `QuadMesh`. Tint per-effect with `ParticleProcessMaterial.color`
and fade with an `alpha_curve` / `scale_curve` (`Curve` + `CurveTexture`
sub-resources; `_data` holds 5 values per point:
`Vector2(x, y), left, right, left_mode, right_mode`).

### Projectile trail

- Emitter is a child of the projectile with `local_coords = false`, so
  particles stay in world space behind it.
- Emission must start **after** positioning. Keep `emitting = false` in the
  scene and in the launch function: set the transform, call
  `reset_physics_interpolation()`, then `emitting = true` and `restart()`.
  Otherwise the scene emits at the origin for its first frame.

### Charge-up tell

- Root `Node3D` with `start(duration)` / `stop()`. A billboard glow quad scaled
  by a tween, plus converging embers (`emission_shape` = sphere surface with
  negative `radial_accel`).
- Parent it to the thing that owns the muzzle so it inherits the transform.
- `start()` must call `reset_physics_interpolation()` on the tell and its
  emitters, then `restart()` the emitter. Without that the first burst reuses
  the transform from the previous shot and visibly slides into place.

## Hard rules (learned the hard way)

1. **Basis handedness.** `Basis(x, y, z)` requires `z = x.cross(y)`. Building
   `z = normal.cross(right)` yields determinant `-1`, flips triangle winding,
   and back-face culling hides every particle in the scene. Assert
   `basis.determinant() == 1.0` when orienting VFX to a surface.
2. **Physics interpolation is on** (`project.godot`:
   `common/physics_interpolation=true`). Every teleported, re-shown, or reused
   effect needs `reset_physics_interpolation()` before `restart()`.
3. **`restart()` clears the previous burst.** Use it on reused emitters, not
   just on first play.
4. **Never emit before the transform is final.** Spawning a scene at the origin
   and moving it in the same frame leaves particles behind at `(0, 0, 0)`.
5. Reuse existing helpers before writing new ones: `Trail.create()`
   (`assets/vfx/trail.gd`), `RingEffect` (`assets/vfx/ring_effect.gd`),
   `CrackDecal`, `OneShotVFX`, `ImpactVFX`. Note `VelocityTrail.attach()` only
   accepts `RigidBody3D`.

## Verify without the editor

1. `godot --headless --import` — imports new textures.
2. `godot --headless --fixed-fps 60 --quit-after N` — catches script/scene
   errors and prints gameplay logs.
3. Visual check with the real renderer (headless cannot show culling or
   material bugs):
   ```bash
   godot --write-movie /tmp/vfx.avi --fixed-fps 30 --quit-after 90
   ffmpeg -i /tmp/vfx.avi -vf fps=15 /tmp/frames/f_%03d.png
   ```
   Then montage/inspect the frames. A temporary scene in `res://` is fine for
   isolation; delete it afterwards.
4. `gdformat <files>` then `gdlint <files>`.

## Worked example

`systems/enemy/projectile/fireball.{gd,tscn}`, `assets/vfx/fire_tell.{gd,tscn}`,
`assets/vfx/fireball_impact.tscn`, driven by
`systems/enemy/attack/enemy_fireball_attack.gd`.
