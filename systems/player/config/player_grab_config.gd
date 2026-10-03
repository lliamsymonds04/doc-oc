class_name PlayerGrabConfig
extends Resource

@export_group("Hold")
@export var HOLD_OFFSET := Vector3(0.6, 1.2, -0.8)
@export var HOLD_DRAG_SENS_X := 0.3  # mouse pixels -> world meters
@export var HOLD_DRAG_SENS_Y := 1  # mouse Y pixels -> body height
@export var HOLD_WHEEL_SENS := 0.5  # notches -> world meters of depth
@export var MAX_HOLD_DRAG := 2.4  # hold position can move this far from its default, relative to the player

@export_group("Servo")
@export var MAX_GRAB_SPIN := 15.0  # rad/s cap for the rotation servo
@export var ROTATION_SERVO_GAIN := 6.0  # 1/s; maps orientation error angle to angular velocity

@export_group("Throw")
@export var THROW_RELEASE_VELOCITY_Y := 20.0  # base arc for the weakest throw
@export var THROW_Y_Z_DROPOFF := 0.35  # arc lost per m/s of z throw speed
@export var THROW_RELEASE_VELOCITY_Y_MIN := 1.0  # arc floor so max-speed throws stay flat, not downward
@export var RELEASE_MOUSE_SAMPLE := 0.5  # EMA weight per physics tick for the mouse-up speed tracker
@export var RELEASE_MOUSE_UP_THRESHOLD := 15.0  # smoothed up-pixels/tick that counts as a flick at release
@export var RELEASE_THROW_SENS := 0.4  # up-pixels -> forward release velocity
@export var RELEASE_THROW_MAX_SPEED := 25.0  # speed cap for the hardest flicks, m/s
