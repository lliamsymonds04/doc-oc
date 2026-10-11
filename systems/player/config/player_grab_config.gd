class_name PlayerGrabConfig
extends Resource

@export_group("Audio")
@export var grab_attempted_sound: AudioStream = preload("res://assets/audio/throw_robot_punch.ogg")
@export var grab_sound: AudioStream = preload("res://assets/audio/grab.ogg")

@export_group("Mode Switch")
@export var mode_switch_fov_kick: float = -0.5

@export_group("Grab")
@export var grab_debounce: float = 0.5
@export var grab_cast_range: float = 15.0
@export var grab_fov_kick: float = 1.0  # FOV widen when a grab punch launches

@export_group("Hold")
@export var hold_offset := Vector3(0.6, 1.2, -0.8)
@export var hold_drag_sens_x := 0.3  # mouse pixels -> world meters
@export var hold_drag_sens_y := 1  # mouse Y pixels -> body height
@export var hold_wheel_sens := 0.5  # notches -> world meters of depth
@export var max_hold_drag := 2.4  # max move from the default hold, relative to the player
@export var magnet_gain := 15.0  # chase speed in m/s per meter of hold error

@export_group("Servo")
@export var max_grab_spin := 15.0  # rad/s cap for the rotation servo
@export var rotation_servo_gain := 6.0  # 1/s; maps orientation error angle to angular velocity

@export_group("Throw")
@export var throw_release_velocity_y := 20.0  # base arc for the weakest throw
@export var throw_y_z_dropoff := 0.35  # arc lost per m/s of z throw speed
@export var throw_release_velocity_y_min := 1.0  # arc floor so fast throws stay flat, not downward
@export var release_mouse_sample := 0.5  # EMA weight per physics tick for mouse-up speed
@export var release_mouse_up_threshold := 15.0  # up-pixels/tick counting as a flick at release
@export var release_throw_sens := 0.4  # up-pixels -> forward release velocity
@export var release_throw_max_speed := 25.0  # speed cap for the hardest flicks, m/s
@export var release_spin_sens := 0.2  # rad/s per m/s of release speed; sign flips tumble direction
@export_range(0, 10, 0.5) var charge_fov_kick := 4.0  # FOV widen at full charge; + = widen
@export var fov_charge_decay_per_tick := 0.3  # m/s of charge drained per idle physics tick

@export_group("Carry Weight")
@export var carry_weight_mass_ref := 10.0  # mass at which the magnet slowdown saturates
@export var carry_magnet_min := 0.35  # magnet multiplier at or above carry_weight_mass_ref
