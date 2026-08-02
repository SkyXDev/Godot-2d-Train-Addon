extends Node2D

@export var path: Path2D
@export var camera_target: Node2D
# Wheel Marker references (Updated 'Backbogie' capitalization to match your tree)
@onready var fb_front_marker: Marker2D = $FrontBogie/FrontBogieSprite/FrontWheel
@onready var fb_rear_marker: Marker2D = $FrontBogie/FrontBogieSprite/BackWheel

@onready var bb_front_marker: Marker2D = $Backbogie/BackBogieSprite/FrontWheel
@onready var bb_rear_marker: Marker2D = $Backbogie/BackBogieSprite/BackWheel

@export var spawn_offset: float = 600.0

# Rigidity settings (fixed Euclidean distances in pixels)
var wheel_base_distance: float = 138.0  # Distance between 2 wheels on a bogie
@export var bogie_pivot_distance: float = 358.0 # Distance between front & back bogies
@export var speed: float = 200.0
@export var speed_controller: HSlider
@onready var fb_front_wheel: PathFollow2D = $FrontBogie_FrontWheel
@onready var fb_rear_wheel: PathFollow2D = $FrontBogie_RearWheel
@onready var bb_front_wheel: PathFollow2D = $BackBogie_FrontWheel
@onready var bb_rear_wheel: PathFollow2D = $BackBogie_RearWheel

@onready var front_bogie: Node2D = $FrontBogie
@onready var back_bogie: Node2D = $Backbogie
@onready var wagon: Node2D = $Wagon
var wagon_velocity := Vector2.ZERO
var wagon_angular_velocity := 0.0
@export var wagon_stiffness := 95
@export var wagon_damping := 10
@export var wagon_rotation_stiffness := 90
@export var wagon_rotation_damping := 10
@export var max_wagon_slack := 30

var lead_progress: float = spawn_offset

func _ready() -> void:
	wagon.global_position = (
	front_bogie.global_position +
	back_bogie.global_position
) * 0.5
	if path:
		# Reparent PathFollow nodes to Path2D automatically at runtime
		fb_front_wheel.reparent(path)
		fb_rear_wheel.reparent(path)
		bb_front_wheel.reparent(path)
		bb_rear_wheel.reparent(path)

func _process(delta: float) -> void:
	if speed_controller:
		speed = speed_controller.value
	if not path or not path.curve:
		return
		
	var curve: Curve2D = path.curve
	var max_len: float = curve.get_baked_length()
	if max_len <= 0.0:
		return

	# 1. Drive lead wheel
	lead_progress = fmod(lead_progress + speed * delta, max_len)
	fb_front_wheel.progress = lead_progress

	# 2. Position Front Bogie Wheels
	var fb_rear_prog = get_progress_at_exact_distance(curve, lead_progress, wheel_base_distance, max_len)
	fb_rear_wheel.progress = fb_rear_prog

	# Align Front Bogie
	var f_f_pos = fb_front_wheel.global_position
	var f_r_pos = fb_rear_wheel.global_position
	var f_midpoint = (f_f_pos + f_r_pos) / 2.0
	var f_angle = (f_f_pos - f_r_pos).angle()
	
	front_bogie.global_rotation = f_angle
	
	# Lift Front Bogie UP so wheel markers rest directly ON the path
	var f_avg_wheel_y = (fb_front_marker.position.y + fb_rear_marker.position.y) / 2.0
	front_bogie.global_position = f_midpoint - Vector2.UP.rotated(f_angle) * f_avg_wheel_y +Vector2(0,-100)

	# 3. Position Back Bogie Front Wheel based on Pivot Distance
	var fb_center_prog = (lead_progress + fb_rear_prog) / 2.0
	var bb_center_target_prog = get_progress_at_exact_distance(curve, fb_center_prog, bogie_pivot_distance, max_len)
	
	# Offset back bogie wheels evenly around the back bogie center
	var half_wheelbase = wheel_base_distance / 2.0
	bb_front_wheel.progress = fmod(bb_center_target_prog + half_wheelbase, max_len)
	var bb_rear_prog = get_progress_at_exact_distance(curve, bb_front_wheel.progress, wheel_base_distance, max_len)
	bb_rear_wheel.progress = bb_rear_prog

	# Align Back Bogie
	var b_f_pos = bb_front_wheel.global_position
	var b_r_pos = bb_rear_wheel.global_position
	var b_midpoint = (b_f_pos + b_r_pos) / 2.0
	var b_angle = (b_f_pos - b_r_pos).angle()
	
	back_bogie.global_rotation = b_angle
	
	# Lift Back Bogie UP so wheel markers rest directly ON the path
	var b_avg_wheel_y = (bb_front_marker.position.y + bb_rear_marker.position.y) / 2.0
	back_bogie.global_position = b_midpoint - Vector2.UP.rotated(b_angle) * b_avg_wheel_y +Vector2(0,-90)

	# 4. Snap Wagon body to bridge the two Bogie centers
	var fg_pos = front_bogie.global_position
	var bg_pos = back_bogie.global_position
	
	var target_position = (fg_pos + bg_pos) * 0.5
	var target_rotation = (fg_pos - bg_pos).angle()

	# POSITION SPRING
	#var force = (target_position - wagon.global_position) * wagon_stiffness

	#wagon_velocity += force * delta
	#wagon_velocity *= exp(-wagon_damping * delta)

	#wagon.global_position += wagon_velocity * delta
	var offset = wagon.global_position - target_position

	# Prevent the wagon from getting too far away
	if offset.length() > max_wagon_slack:
		offset = offset.normalized() * max_wagon_slack
		wagon.global_position = target_position + offset

	var force = (target_position - wagon.global_position) * wagon_stiffness

	wagon_velocity += force * delta
	wagon_velocity *= exp(-wagon_damping * delta)

	wagon.global_position += wagon_velocity * delta
	camera_target.global_position = wagon.global_position
	# ROTATION SPRING
	var angle_error = wrapf(
		target_rotation - wagon.global_rotation,
		-PI,
		PI
	)

	wagon_angular_velocity += angle_error * wagon_rotation_stiffness * delta
	wagon_angular_velocity *= exp(-wagon_rotation_damping * delta)

	wagon.global_rotation += wagon_angular_velocity * delta


# SAFE linear search backwards along curve (max 150 iterations guard rail)
func get_progress_at_exact_distance(curve: Curve2D, start_prog: float, target_dist: float, path_len: float) -> float:
	var target_pos = curve.sample_baked(start_prog)
	var curr_prog = start_prog
	var step_size = 2.0 # Checks every 2 pixels along path
	var iterations = 0
	var max_iterations = 150 # Absolute safety limit to prevent freeze
	
	while iterations < max_iterations:
		curr_prog -= step_size
		
		# Wrap around path if looping
		if curr_prog < 0.0:
			curr_prog += path_len
			
		var sample_pos = curve.sample_baked(curr_prog)
		if sample_pos.distance_to(target_pos) >= target_dist:
			return curr_prog
			
		iterations += 1
		
	# Fallback if loop hit safety guard
	return fmod(start_prog - target_dist + path_len, path_len)
