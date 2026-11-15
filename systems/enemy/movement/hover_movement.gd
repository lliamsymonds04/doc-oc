class_name HoverMovement
extends EnemyMovement

## Downward probe the hoverer holds its altitude over; long enough to find the
## floor from any hover height.
const PROBE_REACH := 50.0
## Cap on the vertical speed, so a spawn below the target can't rocket.
const MAX_SPEED := 10.0

## Last floor found; kept when the probe misses, so a pit or the arena edge
## can't strand the enemy.
var _floor_y := 0.0
## Phase clock for the bob, so it starts at the bottom of the swing.
var _bob_time := 0.0


## Flies to hover_height over the floor instead of falling.
func apply_vertical(dt: float) -> void:
	var from := enemy.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * PROBE_REACH, 1)
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_floor_y = (hit["position"] as Vector3).y

	var config := enemy.config
	_bob_time += dt
	var bob := sin(_bob_time * config.hover_bob_speed) * config.hover_bob_height
	var err := _floor_y + config.hover_height + bob - enemy.global_position.y
	var want := clampf(err * config.hover_stiffness, -MAX_SPEED, MAX_SPEED)
	enemy.velocity.y = lerpf(enemy.velocity.y, want, 1.0 - exp(-config.hover_stiffness * dt))
