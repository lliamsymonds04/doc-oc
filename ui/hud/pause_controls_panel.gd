class_name PauseControlsPanel
extends PanelContainer

signal back_pressed

const FONT: FontFile = preload("res://assets/Anton-Regular.ttf")

const LEFT_SECTIONS := [
	{
		"title": "MOVEMENT",
		"entries":
		[
			["SHIFT", "Sprint (all four limbs)"],
			["Q / CTRL", "Raise / lower hover height"],
			["SPACE (TAP)", "Dash (ram enemies to tackle)"],
			["SPACE (HOLD)", "Charged high jump"],
			["SPACE (AIR, AIM DOWN)", "Ground slam"],
			["SPACE (ON WALL)", "Wall jump (move into walls to climb)"],
		],
	},
]

const RIGHT_SECTIONS := [
	{
		"title": "ATTACK MODE",
		"entries":
		[
			["R", "Switch Attack / Grab mode"],
			["LMB (TAP / HOLD)", "Punch combo (3rd hit = heavy strike)"],
			["RMB (HOLD)", "Focus / aim camera"],
		],
	},
	{
		"title": "GRAB MODE",
		"entries":
		[
			["LMB / RMB (HOLD)", "Grab with left / right arm"],
			["MOUSE MOVE", "Drag held object"],
			["SCROLL WHEEL", "Push / pull held object"],
			["FLICK UP + RELEASE", "Throw (homes toward crosshair)"],
		],
	},
]

var _badge_style: StyleBoxFlat

@onready var left_column: VBoxContainer = $Margin/Content/Columns/LeftColumn
@onready var right_column: VBoxContainer = $Margin/Content/Columns/RightColumn
@onready var back_button: Button = $Margin/Content/BackButton


func _ready() -> void:
	_badge_style = _create_badge_style()
	_populate_column(left_column, LEFT_SECTIONS)
	_populate_column(right_column, RIGHT_SECTIONS)
	back_button.pressed.connect(func(): back_pressed.emit())


func _populate_column(column: VBoxContainer, sections: Array) -> void:
	for section in sections:
		var header := Label.new()
		header.text = section["title"]
		header.add_theme_font_override("font", FONT)
		header.add_theme_font_size_override("font_size", 24)
		header.add_theme_color_override("font_color", Color(0.5882353, 1.0, 1.0, 1.0))
		column.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 12)
		column.add_child(grid)

		for entry in section["entries"]:
			grid.add_child(_make_key_badge(entry[0]))
			grid.add_child(_make_action_label(entry[1]))


func _make_key_badge(key_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _badge_style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = key_text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	panel.add_child(label)
	return panel


func _make_action_label(action_text: String) -> Label:
	var label := Label.new()
	label.text = action_text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.95, 1.0))
	return label


func _create_badge_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.16, 0.22, 1.0)
	sb.border_color = Color(0.5882353, 1.0, 1.0, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb
