extends Node3D
class_name CharacterSelectController

## CharacterSelectController — 3D Character Select Scene with custom 3D replacement transitions for all 8 champions.

@onready var rooster_anchor: Node3D = $RoosterAnchor
@onready var camera: Camera3D = $Camera3D
@onready var spotlight: SpotLight3D = $SpotLight3D

var current_index: int = 0
var roosters: Array[RoosterData] = []
var is_transitioning: bool = false

# Online match state
var _nm: Node = null
var _online_waiting_label: Label = null

# UI references
var ui_layer: CanvasLayer
var name_label: Label
var anime_label: Label
var roster_buttons: Array[Button] = []
var card_rest_positions: Array[Vector2] = []
var card_rest_rotations: Array[float] = []

# 3D Name Stadium Banner (Arena phase notif style behind the rooster)
var name_banner_3d: Node3D = null
var banner_title_3d: Label3D = null
var banner_sub_3d: Label3D = null
var banner_badge_3d: Label3D = null

# Active 3D model instance on the center stage
var current_rooster_model: Node3D = null
const ROOSTER_BASE_SCALE: Vector3 = Vector3(1.35, 1.35, 1.35)

func _ready() -> void:
	roosters = GameManager.all_roosters.duplicate()
	if roosters.is_empty():
		GameManager._load_all_roosters()
		roosters = GameManager.all_roosters.duplicate()
	
	# Find current selected index
	if GameManager.selected_player_rooster:
		for i in range(roosters.size()):
			if roosters[i].rooster_id == GameManager.selected_player_rooster.rooster_id:
				current_index = i
				break

	# Online mode: wire NetworkManager.match_ready so arena loads when both roosters are synced
	if GameManager.is_online_match:
		_nm = get_node_or_null("/root/NetworkManager")
		if _nm and not _nm.match_ready.is_connected(_on_network_match_ready):
			_nm.match_ready.connect(_on_network_match_ready)
			_nm.opponent_disconnected_forfeit.connect(_on_online_forfeit)

	_setup_3d_name_banner()
	_build_select_ui()
	_spawn_initial_rooster(roosters[current_index])

func _spawn_initial_rooster(r: RoosterData) -> void:
	if not rooster_anchor:
		return
	if current_rooster_model:
		current_rooster_model.queue_free()
		current_rooster_model = null
	
	current_rooster_model = _instantiate_model(r.model_path)
	if current_rooster_model:
		rooster_anchor.add_child(current_rooster_model)
		current_rooster_model.position = Vector3.ZERO
		current_rooster_model.rotation_degrees = Vector3(0, 0, 0)
		current_rooster_model.scale = ROOSTER_BASE_SCALE
	
	GameManager.selected_player_rooster = r
	_update_ui_details(r)
	_highlight_active_roster_button()

func _instantiate_model(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is PackedScene:
			return res.instantiate()
	return null

func _update_ui_details(r: RoosterData) -> void:
	if not r:
		return
	if is_instance_valid(name_label):
		name_label.text = r.display_name.to_upper()
	if is_instance_valid(anime_label):
		anime_label.text = "%s  •  HP: %d" % [r.anime_reference, r.base_hp]
	_update_3d_name_banner(r)

func _setup_3d_name_banner() -> void:
	if is_instance_valid(name_banner_3d):
		return

	name_banner_3d = Node3D.new()
	name_banner_3d.name = "RoosterNameBanner3D"
	# Positioned in 3D world space behind the rooster (pedestal is at Z = 0, Y = 1.2)
	name_banner_3d.position = Vector3(0, 2.40, -2.1)
	add_child(name_banner_3d)

	# 1. Top Badge (Anime Lore Reference) — bold uppercase (large)
	banner_badge_3d = Label3D.new()
	banner_badge_3d.name = "BadgeLabel3D"
	banner_badge_3d.text = "--- DRAGON BALL (GOKU) ---"
	banner_badge_3d.font = UIFontStyle.get_anton_font()
	banner_badge_3d.font_size = 110
	banner_badge_3d.outline_size = 20
	banner_badge_3d.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
	banner_badge_3d.modulate = Color(0.85, 0.92, 1.0, 0.95)
	banner_badge_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	banner_badge_3d.no_depth_test = false
	banner_badge_3d.position = Vector3(0, 1.80, 0.0)
	name_banner_3d.add_child(banner_badge_3d)

	# 2. Main Giant Rooster Name — Massive Anton font uppercase matching Arena phase banner
	banner_title_3d = Label3D.new()
	banner_title_3d.name = "TitleLabel3D"
	banner_title_3d.text = "HEN-GOKU"
	banner_title_3d.font = UIFontStyle.get_anton_font()
	banner_title_3d.font_size = 420
	banner_title_3d.outline_size = 40
	banner_title_3d.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
	banner_title_3d.modulate = Color(1.0, 0.85, 0.2)
	banner_title_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	banner_title_3d.no_depth_test = false
	banner_title_3d.position = Vector3(0, 0.60, 0.0)
	name_banner_3d.add_child(banner_title_3d)

	# 3. Subtitle / HP and Combatant details — Anton font uppercase (large)
	banner_sub_3d = Label3D.new()
	banner_sub_3d.name = "SubLabel3D"
	banner_sub_3d.text = "BASE HP: 22  •  SIGNATURE COMBATANT"
	banner_sub_3d.font = UIFontStyle.get_anton_font()
	banner_sub_3d.font_size = 100
	banner_sub_3d.outline_size = 18
	banner_sub_3d.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
	banner_sub_3d.modulate = Color(0.80, 0.88, 1.0, 0.90)
	banner_sub_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	banner_sub_3d.no_depth_test = false
	banner_sub_3d.position = Vector3(0, -0.70, 0.0)
	name_banner_3d.add_child(banner_sub_3d)

func _update_3d_name_banner(r: RoosterData) -> void:
	if not r:
		return
	_setup_3d_name_banner()
	if not is_instance_valid(name_banner_3d):
		return

	if banner_badge_3d:
		banner_badge_3d.text = ("--- %s ---" % r.anime_reference).to_upper()
	if banner_title_3d:
		banner_title_3d.text = r.display_name.to_upper()
		banner_title_3d.modulate = Color(1.0, 0.85, 0.2)
		var name_len := r.display_name.length()
		if name_len > 12:
			banner_title_3d.font_size = 340
		elif name_len > 9:
			banner_title_3d.font_size = 380
		else:
			banner_title_3d.font_size = 420
	if banner_sub_3d:
		banner_sub_3d.text = ("BASE HP: %d  •  SIGNATURE COMBATANT" % r.base_hp).to_upper()

	# Punchy pop-in animation matching the Arena Phase Banner
	name_banner_3d.scale = Vector3(0.6, 0.6, 0.6)
	var tw := name_banner_3d.create_tween()
	if tw:
		tw.tween_property(name_banner_3d, "scale", Vector3.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _highlight_active_roster_button() -> void:
	var total_cards := roster_buttons.size()
	for i in range(total_cards):
		var btn: Button = roster_buttons[i]
		var is_sel: bool = (i == current_index)
		var style := btn.get_theme_stylebox("normal") as StyleBoxFlat
		
		var rx: float = card_rest_positions[i].x if i < card_rest_positions.size() else btn.position.x
		var ry: float = card_rest_positions[i].y if i < card_rest_positions.size() else btn.position.y
		var rrot: float = card_rest_rotations[i] if i < card_rest_rotations.size() else 0.0
		var base_z: int = total_cards - i
		
		var tw := btn.create_tween()
		if tw:
			tw.set_parallel(true)
		if is_sel:
			if style:
				style.border_color = Color.GOLD
				style.set_border_width_all(4)
				style.shadow_size = 28
				style.shadow_color = Color(1.0, 0.85, 0.2, 0.85)
			btn.z_index = 20
			# Only golden champion glow — stays at standard 1.0 scale matching the fanned lineup
			tw.tween_property(btn, "position", Vector2(rx, ry), 0.15).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(btn, "rotation_degrees", rrot, 0.15)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.15)
		else:
			if style:
				style.border_color = Color(0.3, 0.35, 0.45, 0.5)
				style.set_border_width_all(1)
				style.shadow_size = 0
				style.shadow_color = Color.TRANSPARENT
			btn.z_index = base_z
			tw.tween_property(btn, "position", Vector2(rx, ry), 0.15).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(btn, "rotation_degrees", rrot, 0.15)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.15)

func _on_roster_card_clicked(target_index: int) -> void:
	# Duplicate click guard: If the same card is clicked, nothing happens!
	if is_transitioning or target_index == current_index:
		return
	
	var old_r: RoosterData = roosters[current_index]
	var new_r: RoosterData = roosters[target_index]
	current_index = target_index
	GameManager.selected_player_rooster = new_r
	
	_update_ui_details(new_r)
	_highlight_active_roster_button()
	_execute_replacement_cinematic(old_r, new_r)


# ===========================================================================
# 8 UNIQUE CINEMATIC TRANSITIONS
# ===========================================================================

func _execute_replacement_cinematic(_old_r: RoosterData, new_r: RoosterData) -> void:
	is_transitioning = true
	var old_model := current_rooster_model
	current_rooster_model = null
	
	match new_r.rooster_id:
		"hen_goku":
			_play_hen_goku_transition(old_model, new_r)
		"eren_pecker":
			_play_eren_titan_transition(old_model, new_r)
		"chick_yagami":
			_play_yagami_ryuk_transition(old_model, new_r)
		"daniel":
			_play_daniel_unseen_hand_transition(old_model, new_r)
		"cocktaro":
			_play_cocktaro_stand_transition(old_model, new_r)
		"nechicko":
			_play_nechicko_demon_transition(old_model, new_r)
		"decluck":
			_play_decluck_detroit_smash_transition(old_model, new_r)
		"cluckey_d_puffy":
			_play_cluckey_gear5_transition(old_model, new_r)
		_:
			_play_default_transition(old_model, new_r)

func _finish_transition(new_model: Node3D) -> void:
	current_rooster_model = new_model
	if current_rooster_model and current_rooster_model.get_parent() != rooster_anchor:
		current_rooster_model.get_parent().remove_child(current_rooster_model)
		rooster_anchor.add_child(current_rooster_model)
		current_rooster_model.position = Vector3.ZERO
		current_rooster_model.rotation_degrees = Vector3(0, 0, 0)
		current_rooster_model.scale = ROOSTER_BASE_SCALE
	is_transitioning = false


# 1. HEN-GOKU: 3D Volumetric Kame-cock beam stretches across the entire screen, blasts rooster, then Hen-Goku swoops in
func _play_hen_goku_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)
	var chest_height := target_stage_pos.y + 0.35 # Y = 1.55

	var incoming := _instantiate_model(new_r.model_path)
	add_child(incoming)
	incoming.position = Vector3(8.0, 2.5, 0.0) # Offscreen right
	incoming.rotation_degrees = Vector3(0, -90, 0)
	incoming.scale = ROOSTER_BASE_SCALE

	# --- 3D Laser Beam Hierarchy ---
	var beam_root := Node3D.new()
	add_child(beam_root)
	beam_root.position = Vector3(8.0, chest_height, 0.0)
	
	# Leading Energy Ball Head
	var head_sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.42
	sphere_mesh.height = 0.84
	head_sphere.mesh = sphere_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	head_mat.albedo_color = Color(1.0, 1.0, 0.9, 0.95)
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.3, 0.85, 1.0)
	head_mat.emission_energy_multiplier = 4.5
	head_sphere.material_override = head_mat
	beam_root.add_child(head_sphere)

	# Outer Glowing Cyan Laser Cylinder
	var outer_beam := MeshInstance3D.new()
	var outer_cyl := CylinderMesh.new()
	outer_cyl.top_radius = 0.36
	outer_cyl.bottom_radius = 0.36
	outer_cyl.height = 1.0
	outer_beam.mesh = outer_cyl
	var outer_mat := StandardMaterial3D.new()
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.albedo_color = Color(0.2, 0.75, 1.0, 0.75)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(0.2, 0.8, 1.0)
	outer_mat.emission_energy_multiplier = 3.5
	outer_beam.material_override = outer_mat
	outer_beam.rotation_degrees.z = 90.0
	beam_root.add_child(outer_beam)

	# Inner Intense White-Hot Core
	var core_beam := MeshInstance3D.new()
	var core_cyl := CylinderMesh.new()
	core_cyl.top_radius = 0.18
	core_cyl.bottom_radius = 0.18
	core_cyl.height = 1.0
	core_beam.mesh = core_cyl
	var core_mat := StandardMaterial3D.new()
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 1.0, 1.0)
	core_mat.emission_energy_multiplier = 5.0
	core_beam.material_override = core_mat
	core_beam.rotation_degrees.z = 90.0
	beam_root.add_child(core_beam)

	# Shockwave Ring
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.65
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.85, 1.0)
	ring_mat.emission_energy_multiplier = 4.0
	ring.material_override = ring_mat
	ring.rotation_degrees.z = 90.0
	beam_root.add_child(ring)

	var start_x: float = 8.0
	var end_x: float = -8.0

	var tw := create_tween()
	
	# Step 1: Laser beam dynamically stretches from right (X=8.0) across the entire screen to left (X=-8.0)
	tw.tween_method(func(progress: float):
		var current_head_x: float = lerp(start_x, end_x, progress)
		head_sphere.position.x = current_head_x - start_x
		ring.position.x = current_head_x - start_x
		
		var current_length: float = start_x - current_head_x
		if current_length > 0.01:
			outer_cyl.height = current_length
			core_cyl.height = current_length
			outer_beam.position.x = -current_length * 0.5
			core_beam.position.x = -current_length * 0.5
		
		# When the beam head reaches center (X <= 0), old rooster is hit and blasted away
		if current_head_x <= 0.0 and old_model and is_instance_valid(old_model):
			old_model.position.x = current_head_x - 0.5
			old_model.rotation_degrees.z += 25.0
			old_model.scale = ROOSTER_BASE_SCALE * clampf((current_head_x - end_x) / 8.0, 0.0, 1.0)
	, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Clean up old rooster once blasted offscreen
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			old_model.queue_free()
	)
	
	# Step 2: Beam dissipates / dissolves
	tw.tween_interval(0.08)
	tw.tween_property(beam_root, "scale:y", 0.0, 0.08)
	tw.parallel().tween_property(beam_root, "scale:z", 0.0, 0.08)
	tw.tween_callback(beam_root.queue_free)

	# Step 3: Hen-Goku dashes in from offscreen right, lands on stage, and faces camera
	tw.tween_property(incoming, "position", target_stage_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(incoming, "rotation_degrees", Vector3(0, 0, 0), 0.25)
	tw.tween_property(incoming, "scale", Vector3(1.65, 0.95, 1.65), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(incoming, "scale", ROOSTER_BASE_SCALE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _finish_transition(incoming))


# 2. EREN PECKER: Pecker Titan stomps from the sky, squashes old rooster flat into a visible pancake, steams and reverts to normal Eren
func _play_eren_titan_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)

	var titan := _instantiate_model("res://resources/models/eren_pecker/erentitan.vox")
	if not titan: titan = _instantiate_model(new_r.model_path)
	add_child(titan)
	titan.position = target_stage_pos + Vector3(0, 7.5, -0.6) # Drops from sky towering slightly behind
	titan.rotation_degrees = Vector3(15, 0, 0)
	titan.scale = Vector3(1.8, 1.8, 1.8)
	
	var tw := create_tween()
	# Titan drops & stomps with heavy speed
	tw.tween_property(titan, "position", target_stage_pos + Vector3(0, 0, -0.6), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(titan, "rotation_degrees", Vector3(0, 0, 0), 0.20)
	
	# ON IMPACT: Old rooster gets completely squashed into a literal paper-thin flat pancake in full view!
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			var tw_squash := create_tween()
			# Instant violent flat pancake squash directly on stage floor (Y = 0 local in anchor)
			tw_squash.tween_property(old_model, "scale", Vector3(2.8, 0.02, 2.8), 0.06).set_trans(Tween.TRANS_QUAD)
			tw_squash.parallel().tween_property(old_model, "position", Vector3(0, 0, 0.2), 0.06)
			# Hold visible flat pancake on the ground for a solid beat
			tw_squash.tween_interval(0.35)
			# Fade/vanish pancake as Eren appears
			tw_squash.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.12).set_trans(Tween.TRANS_QUAD)
			tw_squash.tween_callback(old_model.queue_free)
	)
	
	# Titan landing heavy squash and roar
	tw.tween_property(titan, "scale", Vector3(2.3, 1.3, 2.3), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(titan, "scale", Vector3(1.9, 1.9, 1.9), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.30)
	
	# Steam power down to normal Eren in center spotlight
	tw.tween_callback(func():
		var normal_eren := _instantiate_model(new_r.model_path)
		add_child(normal_eren)
		normal_eren.position = target_stage_pos
		normal_eren.rotation_degrees = Vector3(0, 0, 0)
		normal_eren.scale = Vector3(1.65, 0.95, 1.65)
		titan.queue_free()
		
		var tw_pop := create_tween()
		tw_pop.tween_property(normal_eren, "scale", ROOSTER_BASE_SCALE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_pop.tween_callback(func(): _finish_transition(normal_eren))
	)


# 3. CHICK YAGAMI: Ryuk swoops down, grabs rooster by the head, snatches it away; then returns holding Yagami and sets him down on center stage
func _play_yagami_ryuk_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)

	var ryuk := _instantiate_model("res://resources/models/chick_yagami/ryuk.vox")
	if not ryuk: ryuk = _instantiate_model(new_r.model_path)
	add_child(ryuk)
	ryuk.position = target_stage_pos + Vector3(0, 6.5, -2.5) # High in sky behind
	ryuk.rotation_degrees = Vector3(20, 0, 0)
	ryuk.scale = Vector3(1.5, 1.5, 1.5)
	
	var tw := create_tween()
	
	# Step 1: Ryuk swoops down right above the old rooster's head (0.28s)
	tw.tween_property(ryuk, "position", target_stage_pos + Vector3(0, 1.45, 0), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ryuk, "rotation_degrees", Vector3(0, 0, 0), 0.28)
	
	# Clutches rooster by the head and snatches it away into the sky (0.35s)
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			old_model.reparent(ryuk)
			old_model.position = Vector3(0, -0.9, 0) # Dangles cleanly below claws
			old_model.rotation_degrees = Vector3(15, 0, 0)
	)
	tw.tween_property(ryuk, "position", target_stage_pos + Vector3(0, 8.5, -3.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Step 2: Ryuk carries old rooster away, deletes it, and prepares to return with Yagami
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			old_model.queue_free()
	)
	tw.tween_interval(0.12)
	
	# Step 3: Ryuk swoops back down from the sky carrying Chick Yagami!
	tw.tween_callback(func():
		var yagami := _instantiate_model(new_r.model_path)
		add_child(yagami)
		yagami.scale = ROOSTER_BASE_SCALE
		yagami.rotation_degrees = Vector3(0, 0, 0)
		
		# Reposition Ryuk high with Yagami dangling beneath him
		ryuk.position = target_stage_pos + Vector3(0, 7.0, -1.5)
		yagami.reparent(ryuk)
		yagami.position = Vector3(0, -0.95, 0)
		
		var tw_return := create_tween()
		# Ryuk glides down and lowers Yagami onto the stage floor (0.35s)
		tw_return.tween_property(ryuk, "position", target_stage_pos + Vector3(0, 1.45, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Yagami lands on his feet on center stage
		tw_return.tween_callback(func():
			yagami.reparent(self)
			yagami.position = target_stage_pos
			yagami.rotation_degrees = Vector3(0, 0, 0)
			
			# Ryuk flies back up into the shadows
			var tw_fly := create_tween()
			tw_fly.tween_property(ryuk, "position", target_stage_pos + Vector3(0, 7.5, -3.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw_fly.tween_callback(ryuk.queue_free)
			
			# Yagami landing pop & finish transition
			var tw_land := create_tween()
			tw_land.tween_property(yagami, "scale", Vector3(ROOSTER_BASE_SCALE.x * 1.15, ROOSTER_BASE_SCALE.y * 0.9, ROOSTER_BASE_SCALE.z * 1.15), 0.08)
			tw_land.tween_property(yagami, "scale", ROOSTER_BASE_SCALE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_land.tween_callback(func(): _finish_transition(yagami))
		)
	)


# 4. DANIEL: Swarm of chaotic thin squiggly spaghetti Unseen Hands erupt from shadows, pummel rooster away; Daniel runs in, slides, trips flat on face, recovers
func _play_daniel_unseen_hand_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)
	var chest_height := target_stage_pos.y + 0.4 # Y = 1.60

	# --- Construct Swarm of 6 Chaotic Thin Spaghetti Tendrils ---
	var hand_root := Node3D.new()
	add_child(hand_root)
	hand_root.position = Vector3.ZERO

	# Shadow material (dark violet core with bright ethereal purple emission)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.1, 0.01, 0.18, 0.95)
	shadow_mat.emission_enabled = true
	shadow_mat.emission = Color(0.72, 0.12, 1.0)
	shadow_mat.emission_energy_multiplier = 4.0

	var num_hands := 6
	var num_joints := 9
	var hands_data: Array[Dictionary] = []

	var hand_offsets: Array[Vector3] = [
		Vector3(0, 1.1, -0.6),
		Vector3(0, 0.6, 0.7),
		Vector3(0, 0.1, -0.2),
		Vector3(0, -0.4, 0.4),
		Vector3(0, -0.9, -0.5),
		Vector3(0, 1.4, 0.3)
	]

	for h in range(num_hands):
		var h_dict := {
			"offset": hand_offsets[h],
			"freq": 24.0 + float(h) * 3.5,
			"phase_y": float(h) * 1.3,
			"phase_z": float(h) * 1.7 + 0.5,
			"amp_y": 0.45 + float(h % 3) * 0.18,
			"amp_z": 0.35 + float((h + 1) % 3) * 0.15,
			"joint_spheres": [] as Array[MeshInstance3D],
			"link_nodes": [] as Array[Node3D],
			"link_cyls": [] as Array[CylinderMesh],
			"palm_node": Node3D.new(),
			"fingers": [] as Array[MeshInstance3D]
		}
		
		# 1. Thin joint spheres
		for i in range(num_joints):
			var sph_inst := MeshInstance3D.new()
			var sph := SphereMesh.new()
			var t_ratio := float(i) / float(num_joints - 1)
			var rad: float = lerp(0.06, 0.14, t_ratio) # Thinner spaghetti radius
			sph.radius = rad
			sph.height = rad * 2.0
			sph_inst.mesh = sph
			sph_inst.material_override = shadow_mat
			hand_root.add_child(sph_inst)
			h_dict["joint_spheres"].append(sph_inst)

		# 2. Thin continuous connecting cylinders
		for i in range(num_joints - 1):
			var link_node := Node3D.new()
			hand_root.add_child(link_node)
			
			var cyl_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			var t_ratio := float(i) / float(num_joints - 1)
			var rad_start: float = lerp(0.06, 0.14, t_ratio)
			var rad_end: float = lerp(0.06, 0.14, float(i + 1) / float(num_joints - 1))
			cyl.top_radius = rad_end
			cyl.bottom_radius = rad_start
			cyl.height = 1.0
			cyl_inst.mesh = cyl
			cyl_inst.material_override = shadow_mat
			cyl_inst.rotation_degrees.x = 90.0
			link_node.add_child(cyl_inst)
			
			h_dict["link_nodes"].append(link_node)
			h_dict["link_cyls"].append(cyl)

		# 3. Palm & 4 Claw Fingers at the tip
		var palm_node: Node3D = h_dict["palm_node"]
		hand_root.add_child(palm_node)

		var palm := MeshInstance3D.new()
		var palm_box := BoxMesh.new()
		palm_box.size = Vector3(0.3, 0.35, 0.22)
		palm.mesh = palm_box
		palm.material_override = shadow_mat
		palm.position = Vector3(0.12, 0, 0)
		palm_node.add_child(palm)

		for f in range(4):
			var finger := MeshInstance3D.new()
			var f_box := BoxMesh.new()
			f_box.size = Vector3(0.28, 0.07, 0.07)
			finger.mesh = f_box
			finger.material_override = shadow_mat
			finger.position = Vector3(0.28, (f - 1.5) * 0.1, (f % 2 - 0.5) * 0.08)
			finger.rotation_degrees.z = (f - 1.5) * 18.0
			palm_node.add_child(finger)
			h_dict["fingers"].append(finger)

		hands_data.append(h_dict)

	var origin_x: float = -9.5
	var target_tip_x: float = 0.8
	var tw := create_tween()
	var has_hit := [false]

	# Step 1: Chaotic swarm of 6 squiggly spaghetti hands strikes at lightning speed (0.28s)
	tw.tween_method(func(progress: float):
		var cur_tip_x: float = lerp(origin_x, target_tip_x, progress)

		for h in range(num_hands):
			var hd: Dictionary = hands_data[h]
			var offset: Vector3 = hd["offset"]
			var freq: float = hd["freq"]
			var phase_y: float = hd["phase_y"]
			var phase_z: float = hd["phase_z"]
			var amp_y: float = hd["amp_y"]
			var amp_z: float = hd["amp_z"]
			var joint_spheres: Array[MeshInstance3D] = hd["joint_spheres"]
			var link_nodes: Array[Node3D] = hd["link_nodes"]
			var link_cyls: Array[CylinderMesh] = hd["link_cyls"]
			var palm_node: Node3D = hd["palm_node"]
			var fingers: Array[MeshInstance3D] = hd["fingers"]

			# Calculate joint positions along this hand's wild wavy path
			var joint_pts: Array[Vector3] = []
			for i in range(num_joints):
				var t_joint: float = float(i) / float(num_joints - 1)
				var jx: float = lerp(origin_x, cur_tip_x, t_joint)
				var wave_time := progress * freq + float(i) * 0.9
				var jy: float = chest_height + offset.y * t_joint + sin(wave_time + phase_y) * amp_y * t_joint
				var jz: float = offset.z * t_joint + cos(wave_time * 0.8 + phase_z) * amp_z * t_joint
				var pt := Vector3(jx, jy, jz)
				joint_pts.append(pt)
				joint_spheres[i].position = pt

			# Update connecting cylinder links
			for i in range(num_joints - 1):
				var p_start: Vector3 = joint_pts[i]
				var p_end: Vector3 = joint_pts[i + 1]
				var dir := p_end - p_start
				var dist := dir.length()
				if dist > 0.001:
					var l_node: Node3D = link_nodes[i]
					var l_cyl: CylinderMesh = link_cyls[i]
					l_cyl.height = dist + 0.05
					l_node.position = (p_start + p_end) * 0.5
					var up_vec := Vector3.UP if abs(dir.normalized().y) < 0.9 else Vector3.RIGHT
					l_node.look_at(p_end, up_vec)

			# Position & orient palm tip
			var tip_pt: Vector3 = joint_pts[num_joints - 1]
			var prev_pt: Vector3 = joint_pts[num_joints - 2]
			palm_node.position = tip_pt
			var palm_dir := (tip_pt - prev_pt).normalized()
			if palm_dir.length() > 0.001:
				var up_v := Vector3.UP if abs(palm_dir.y) < 0.9 else Vector3.RIGHT
				palm_node.look_at(tip_pt + palm_dir, up_v)

			# Twitch fingers chaotically
			for f in range(fingers.size()):
				fingers[f].rotation_degrees.z = (f - 1.5) * 18.0 + sin(progress * 40.0 + f * 2.0 + h) * 25.0

		# Fast explosive impact: The moment swarm strikes center rooster (cur_tip_x >= -0.2):
		if not has_hit[0] and cur_tip_x >= -0.2 and old_model and is_instance_valid(old_model):
			has_hit[0] = true
			var tw_hit := create_tween()
			if tw_hit:
				tw_hit.set_parallel(true)
				tw_hit.tween_property(old_model, "position", Vector3(10.0, target_stage_pos.y + 2.5, 0.0), 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
				tw_hit.tween_property(old_model, "rotation_degrees", Vector3(360, 0, 720), 0.18)
				tw_hit.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.18)
				tw_hit.chain().tween_callback(old_model.queue_free)
	, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Squiggly hand swarm rapidly dissolves into shadow smoke
	tw.tween_property(hand_root, "scale", Vector3(0.001, 0.001, 0.001), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(hand_root.queue_free)

	# Step 2: Once hands are gone, Daniel slides in already on his side across the arena floor!
	var daniel := _instantiate_model(new_r.model_path)
	add_child(daniel)
	daniel.position = Vector3(-8.5, target_stage_pos.y + 0.35, 0.0) # Offscreen left on the floor
	daniel.rotation_degrees = Vector3(0, 0, -85.0) # Laying on his side
	daniel.scale = ROOSTER_BASE_SCALE
	
	# Slide across the stage on his side into center spotlight (0.32s)
	tw.tween_property(daniel, "position:x", target_stage_pos.x, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(daniel, "rotation_degrees:z", -88.0, 0.32).set_trans(Tween.TRANS_QUAD)
	
	# Brief comical pause on the floor
	tw.tween_interval(0.22)
	
	# Pop back up dusting himself off and face camera
	tw.tween_property(daniel, "position:y", target_stage_pos.y, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(daniel, "rotation_degrees", Vector3(0, 0, 0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(daniel, "scale", Vector3(ROOSTER_BASE_SCALE.x * 0.9, ROOSTER_BASE_SCALE.y * 1.25, ROOSTER_BASE_SCALE.z * 0.9), 0.10)
	tw.tween_property(daniel, "scale", ROOSTER_BASE_SCALE, 0.12).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_callback(func(): _finish_transition(daniel))


# 5. COCKTARO: Star Platinum charges grounded all the way across the arena knocking rooster out of screen, then Cocktaro slides in
func _play_cocktaro_stand_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)

	# 1. Spawn Cocktaro offscreen to the left
	var cocktaro := _instantiate_model(new_r.model_path)
	add_child(cocktaro)
	cocktaro.position = Vector3(-8.5, target_stage_pos.y, 0.0) # Offscreen left
	cocktaro.rotation_degrees = Vector3(0, 0, 0)
	cocktaro.scale = ROOSTER_BASE_SCALE
	
	# 2. Spawn Star Platinum grounded on stage floor offscreen to the left
	var stand := _instantiate_model("res://resources/models/cocktaro/kotarostand.vox")
	if not stand: stand = _instantiate_model(new_r.model_path)
	add_child(stand)
	stand.position = Vector3(-8.5, target_stage_pos.y, 0.0) # Grounded on floor
	stand.rotation_degrees = Vector3(0, 90, 0) # Facing +X directly along charge path
	stand.scale = Vector3(1.6, 1.6, 1.6)

	var tw := create_tween()
	var start_x: float = -8.5
	var end_x: float = 8.5
	
	# Step 1: Star Platinum charges across the arena at readable speed (0.65s)
	tw.tween_method(func(progress: float):
		var cur_x: float = lerp(start_x, end_x, progress)
		stand.position.x = cur_x
		
		# Instantaneous physical contact: The exact frame Star Platinum touches the rooster (cur_x >= -0.5),
		# the rooster is pushed along directly in front of Star Platinum all the way out of screen!
		if cur_x >= -0.5 and old_model and is_instance_valid(old_model):
			old_model.position.x = cur_x + 0.6
			old_model.position.y = target_stage_pos.y + clampf((cur_x + 0.5) * 0.2, 0.0, 1.8)
			old_model.rotation_degrees.z -= 18.0
			old_model.scale = ROOSTER_BASE_SCALE * clampf((end_x - cur_x) / 6.0, 0.0, 1.0)
	, 0.0, 1.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Clean up old rooster and Star Platinum once offscreen right
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			old_model.queue_free()
		stand.queue_free()
	)
	
	# Step 2: Cocktaro slides into his spot from offscreen left with a stylish drift
	tw.tween_property(cocktaro, "position", target_stage_pos, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cocktaro, "rotation_degrees:z", -15.0, 0.16)
	tw.tween_property(cocktaro, "rotation_degrees:z", 0.0, 0.16).set_trans(Tween.TRANS_BACK)
	# Cocktaro tips cap
	tw.tween_property(cocktaro, "rotation_degrees:x", -12.0, 0.12)
	tw.tween_property(cocktaro, "rotation_degrees:x", 0.0, 0.14)
	tw.tween_callback(func(): _finish_transition(cocktaro))


# 6. NECHICKO: Demon Nechicko charges at lightspeed from offscreen left, tackles rooster on physical contact, slides into center, reverts to normal Nezuko
func _play_nechicko_demon_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)

	var demon := _instantiate_model("res://resources/models/nechicko/Nezukodemon.vox")
	if not demon: demon = _instantiate_model(new_r.model_path)
	add_child(demon)
	demon.position = target_stage_pos + Vector3(-8.5, 0, 0) # Offscreen left
	demon.rotation_degrees = Vector3(0, 90, 0) # Facing +X along charge path
	demon.scale = ROOSTER_BASE_SCALE
	
	var tw := create_tween()
	var has_tackled := [false]
	
	# Step 1: Demon Nezuko sprints at high velocity from offscreen to center stage (0.30s)
	tw.tween_method(func(progress: float):
		var cur_x: float = lerp(-8.5, 0.0, progress)
		demon.position.x = target_stage_pos.x + cur_x
		
		# Running stride animation bobbing
		demon.position.y = target_stage_pos.y + abs(sin(progress * 25.0)) * 0.15
		demon.rotation_degrees.z = sin(progress * 25.0) * 12.0
		
		# THE EXACT MOMENT of physical contact with old rooster (cur_x >= -0.4):
		if not has_tackled[0] and cur_x >= -0.4 and old_model and is_instance_valid(old_model):
			has_tackled[0] = true
			var tw_hit := create_tween()
			if tw_hit:
				tw_hit.set_parallel(true)
				tw_hit.tween_property(old_model, "position", Vector3(9.5, target_stage_pos.y + 2.0, 0.0), 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
				tw_hit.tween_property(old_model, "rotation_degrees", Vector3(0, 0, -720), 0.22)
				tw_hit.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.22)
				tw_hit.chain().tween_callback(old_model.queue_free)
	, 0.0, 1.0, 0.30).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# Step 2: Demon slides to a halt in center spotlight and turns to camera
	tw.tween_property(demon, "position", target_stage_pos, 0.10).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(demon, "rotation_degrees", Vector3(0, 0, 0), 0.14).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.20)
	
	# Step 3: Reverts / shrinks into cute normal Nezuko with bamboo muzzle
	tw.tween_callback(func():
		var normal_nezuko := _instantiate_model(new_r.model_path)
		add_child(normal_nezuko)
		normal_nezuko.position = target_stage_pos
		normal_nezuko.rotation_degrees = Vector3(0, 0, 0)
		normal_nezuko.scale = Vector3(1.65, 0.95, 1.65)
		demon.queue_free()
		
		var tw_pop := create_tween()
		tw_pop.tween_property(normal_nezuko, "scale", ROOSTER_BASE_SCALE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw_pop.tween_callback(func(): _finish_transition(normal_nezuko))
	)


# 7. DECLUCK: Chaotic 3D zigzag One For All emerald lightning strikes down from the sky, detonates old rooster, Powered Deku superhero lands and powers down
func _play_decluck_detroit_smash_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)
	
	# Lightning root container
	var lightning_root := Node3D.new()
	add_child(lightning_root)
	
	# Full Cowling emerald lightning material
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt_mat.albedo_color = Color(0.2, 1.0, 0.6, 0.95)
	bolt_mat.emission_enabled = true
	bolt_mat.emission = Color(0.15, 1.0, 0.55)
	bolt_mat.emission_energy_multiplier = 4.5
	
	# Generate 7 chaotic 3D zigzag lightning bolts from the sky
	var num_bolts := 7
	var num_segs := 8
	var bolts_data: Array[Dictionary] = []
	
	for b in range(num_bolts):
		var sky_x: float = randf_range(-3.5, 3.5)
		var sky_z: float = randf_range(-2.5, 2.5)
		var target_x: float = randf_range(-0.4, 0.4)
		var target_z: float = randf_range(-0.4, 0.4)
		
		# Generate 3D zigzag points from Y = 9.5 to Y = target_stage_pos.y
		var pts: Array[Vector3] = []
		for i in range(num_segs):
			var t: float = float(i) / float(num_segs - 1)
			var px: float = lerp(sky_x, target_x, t) + (randf_range(-0.5, 0.5) if (i > 0 and i < num_segs - 1) else 0.0)
			var py: float = lerp(9.5, target_stage_pos.y, t)
			var pz: float = lerp(sky_z, target_z, t) + (randf_range(-0.5, 0.5) if (i > 0 and i < num_segs - 1) else 0.0)
			pts.append(Vector3(px, py, pz))
			
		var b_dict := {
			"pts": pts,
			"link_nodes": [] as Array[Node3D],
			"link_cyls": [] as Array[CylinderMesh]
		}
		
		# Build connected cylinders for each zigzag segment
		for i in range(num_segs - 1):
			var p_start: Vector3 = pts[i]
			var p_end: Vector3 = pts[i + 1]
			var dir := p_end - p_start
			var dist := dir.length()
			
			var link_node := Node3D.new()
			link_node.position = (p_start + p_end) * 0.5
			lightning_root.add_child(link_node)
			
			var cyl_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.08
			cyl.bottom_radius = 0.08
			cyl.height = dist + 0.04
			cyl_inst.mesh = cyl
			cyl_inst.material_override = bolt_mat
			cyl_inst.rotation_degrees.x = 90.0
			link_node.add_child(cyl_inst)
			
			if dist > 0.001:
				var up_v := Vector3.UP if abs(dir.normalized().y) < 0.9 else Vector3.RIGHT
				link_node.look_at(p_end, up_v)
				
			b_dict["link_nodes"].append(link_node)
			b_dict["link_cyls"].append(cyl)
			
		bolts_data.append(b_dict)
		
	# Lightning impact burst sphere at center stage
	var impact_sphere := MeshInstance3D.new()
	var sph_mesh := SphereMesh.new()
	sph_mesh.radius = 1.6
	sph_mesh.height = 3.2
	impact_sphere.mesh = sph_mesh
	impact_sphere.material_override = bolt_mat
	impact_sphere.position = target_stage_pos + Vector3(0, 0.6, 0)
	impact_sphere.scale = Vector3(0.001, 0.001, 0.001)
	lightning_root.add_child(impact_sphere)
	
	# Powered Decluck dropping down from the sky
	var powered := _instantiate_model("res://resources/models/decluck/Decluckpowered.vox")
	if not powered: powered = _instantiate_model(new_r.model_path)
	add_child(powered)
	powered.position = target_stage_pos + Vector3(0, 9.5, 0) # High in sky
	powered.rotation_degrees = Vector3(25, 0, 0)
	powered.scale = ROOSTER_BASE_SCALE
	
	var tw := create_tween()
	var has_turned_black := [false]
	
	# Charred pitch-black material for struck rooster
	var black_mat := StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.02, 0.02, 0.02, 1.0)
	black_mat.roughness = 0.95
	
	# 1. Lightning flashes down rapidly with high voltage jitter (0.20s)
	tw.tween_method(func(progress: float):
		# Jitter lightning bolts slightly during strike
		for b in range(num_bolts):
			var bd: Dictionary = bolts_data[b]
			var link_nodes: Array[Node3D] = bd["link_nodes"]
			for l in link_nodes:
				l.scale = Vector3.ONE * (1.0 + randf_range(-0.3, 0.3))
		
		# On lightning impact (progress >= 0.25): Turn rooster pitch black immediately!
		if not has_turned_black[0] and progress >= 0.25 and old_model and is_instance_valid(old_model):
			has_turned_black[0] = true
			for child in old_model.find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D:
					child.material_override = black_mat
		
		# Electrical shock jitter on rooster
		if has_turned_black[0] and old_model and is_instance_valid(old_model):
			old_model.rotation_degrees.z = randf_range(-14.0, 14.0)
			old_model.rotation_degrees.x = randf_range(-8.0, 8.0)
	, 0.0, 1.0, 0.20).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# Flash impact burst
	tw.tween_callback(func():
		impact_sphere.scale = Vector3(1.2, 1.2, 1.2)
		if old_model and is_instance_valid(old_model):
			old_model.rotation_degrees = Vector3(0, 0, 0)
	)
	
	# Dissolve lightning and impact sphere
	tw.tween_property(impact_sphere, "scale", Vector3(0.001, 0.001, 0.001), 0.10).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(lightning_root, "scale", Vector3(0.001, 0.001, 0.001), 0.10)
	tw.tween_callback(lightning_root.queue_free)
	
	# 2. COMEDIC FREEZE BEAT: Charred black rooster stands completely frozen on screen smoking (0.35s)!
	tw.tween_interval(0.35)
	
	# 3. Powered Deku slams down like a meteor from the sky (0.15s)
	tw.tween_property(powered, "position", target_stage_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(powered, "rotation_degrees", Vector3(0, 0, 0), 0.15)
	
	# ON IMPACT: Charred black rooster gets blown away into the sky!
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			var tw_launch := create_tween()
			if tw_launch:
				tw_launch.set_parallel(true)
				tw_launch.tween_property(old_model, "position", Vector3(0, 12.0, 0), 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
				tw_launch.tween_property(old_model, "rotation_degrees", Vector3(720, 0, 720), 0.22)
				tw_launch.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.22)
				tw_launch.chain().tween_callback(old_model.queue_free)
	)
	
	# Superhero landing squash on floor
	tw.tween_property(powered, "scale", Vector3(ROOSTER_BASE_SCALE.x * 1.5, ROOSTER_BASE_SCALE.y * 0.7, ROOSTER_BASE_SCALE.z * 1.5), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(powered, "scale", ROOSTER_BASE_SCALE, 0.12).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_interval(0.20)
	
	# 4. Powers down smoothly into normal Deku facing camera
	tw.tween_callback(func():
		var normal_deku := _instantiate_model(new_r.model_path)
		add_child(normal_deku)
		normal_deku.position = target_stage_pos
		normal_deku.rotation_degrees = Vector3(0, 0, 0)
		normal_deku.scale = Vector3(1.65, 0.95, 1.65)
		powered.queue_free()
		
		var tw_pop := create_tween()
		tw_pop.tween_property(normal_deku, "scale", ROOSTER_BASE_SCALE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw_pop.tween_callback(func(): _finish_transition(normal_deku))
	)


# 8. CLUCKEY D PUFFY: Gear 5 starts from right, looking at rooster, bounces across and stomps it flat
func _play_cluckey_gear5_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var target_stage_pos := rooster_anchor.global_position # (0, 1.20, 0)

	var gear5 := _instantiate_model("res://resources/models/cluckey_d_puffy/luffy5th gear.vox")
	if not gear5: gear5 = _instantiate_model(new_r.model_path)
	add_child(gear5)
	gear5.position = target_stage_pos + Vector3(6.0, 6.5, 0.0) # High in sky offscreen right
	gear5.rotation_degrees = Vector3(0, -90, 0) # Facing -X directly towards the target rooster!
	gear5.scale = Vector3(1.6, 1.6, 1.6)
	
	var tw := create_tween()
	
	# Bounce 1: Drops down far right at X = 4.2 (0.22s)
	tw.tween_property(gear5, "position", target_stage_pos + Vector3(4.2, 0, 0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(gear5, "scale", Vector3(2.2, 0.9, 2.2), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(gear5, "rotation_degrees", Vector3(0, -90, -20.0), 0.06)
	
	# Bounce 1 Rebound up to X = 2.8, Y = 4.8 (0.20s)
	tw.tween_property(gear5, "position", target_stage_pos + Vector3(2.8, 4.8, 0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gear5, "scale", Vector3(1.4, 2.0, 1.4), 0.18)
	tw.parallel().tween_property(gear5, "rotation_degrees", Vector3(0, -90, 15.0), 0.18)
	
	# Bounce 2: Drops down at X = 2.0 (safe distance away from center rooster) (0.20s)
	tw.tween_property(gear5, "position", target_stage_pos + Vector3(2.0, 0, 0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(gear5, "scale", Vector3(2.3, 0.8, 2.3), 0.06).set_trans(Tween.TRANS_QUAD)
	
	# Bounce 2 High Apex straight up directly above center stage (X = 0.0, Y = 6.2) (0.22s)
	tw.tween_property(gear5, "position", target_stage_pos + Vector3(0.0, 6.2, 0), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gear5, "scale", Vector3(1.3, 2.2, 1.3), 0.20)
	tw.parallel().tween_property(gear5, "rotation_degrees", Vector3(0, -90, 0.0), 0.20)
	
	# Bounce 3: GRAND SLAM STOMP straight down onto the old rooster at X = 0.0! (0.16s)
	tw.tween_property(gear5, "position", target_stage_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(gear5, "scale", Vector3(1.8, 1.8, 1.8), 0.16)
	
	# ON IMPACT: Old rooster gets completely squashed flat like a pancake on the floor!
	tw.tween_callback(func():
		if old_model and is_instance_valid(old_model):
			var tw_squash := create_tween()
			tw_squash.tween_property(old_model, "scale", Vector3(2.5, 0.03, 2.5), 0.08).set_trans(Tween.TRANS_QUAD)
			tw_squash.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_delay(0.04)
			tw_squash.tween_callback(old_model.queue_free)
	)
	tw.tween_property(gear5, "scale", Vector3(2.4, 0.7, 2.4), 0.08).set_trans(Tween.TRANS_QUAD)
	
	# Joyful rubber rebound bounce and turn to face camera
	tw.tween_property(gear5, "position:y", target_stage_pos.y + 1.2, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gear5, "scale", Vector3(1.5, 1.7, 1.5), 0.15)
	tw.parallel().tween_property(gear5, "rotation_degrees", Vector3(0, 0, 0), 0.15)
	tw.tween_property(gear5, "position:y", target_stage_pos.y, 0.12).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(gear5, "scale", Vector3(1.8, 1.4, 1.8), 0.12)
	tw.tween_interval(0.12)
	
	# Swap to normal Luffy laughing with open arms facing camera
	tw.tween_callback(func():
		var normal_luffy := _instantiate_model(new_r.model_path)
		add_child(normal_luffy)
		normal_luffy.position = rooster_anchor.global_position
		normal_luffy.rotation_degrees = Vector3(0, 0, 0)
		normal_luffy.scale = Vector3(1.65, 0.95, 1.65)
		gear5.queue_free()
		
		var tw_pop := create_tween()
		tw_pop.tween_property(normal_luffy, "scale", ROOSTER_BASE_SCALE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw_pop.tween_callback(func(): _finish_transition(normal_luffy))
	)


# Default Fallback Transition
func _play_default_transition(old_model: Node3D, new_r: RoosterData) -> void:
	var incoming := _instantiate_model(new_r.model_path)
	add_child(incoming)
	incoming.position = rooster_anchor.global_position + Vector3(0, 3.5, 0)
	incoming.rotation_degrees = Vector3(0, 0, 0)
	incoming.scale = Vector3(0.5, 0.5, 0.5)
	
	var tw := create_tween()
	if old_model:
		tw.tween_property(old_model, "scale", Vector3(0.001, 0.001, 0.001), 0.2).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(old_model.queue_free)
	
	tw.tween_property(incoming, "position", rooster_anchor.global_position, 0.25).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(incoming, "scale", ROOSTER_BASE_SCALE, 0.25)
	tw.tween_callback(func(): _finish_transition(incoming))


# ===========================================================================
# UI Construction & Extra-Large Cards
# ===========================================================================

func _build_select_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)

	# --- Top Header Bar ---
	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(40, 24)
	top_bar.custom_minimum_size = Vector2(1840, 68)
	top_bar.add_theme_constant_override("separation", 24)
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top_bar)

	var btn_back := Button.new()
	btn_back.text = "MAIN MENU"
	btn_back.icon = UIIcons.get_icon("arrow_left", 20)
	btn_back.flat = true
	btn_back.add_theme_constant_override("h_separation", 10)
	var empty_back := StyleBoxEmpty.new()
	btn_back.add_theme_stylebox_override("normal", empty_back)
	btn_back.add_theme_stylebox_override("hover", empty_back)
	btn_back.add_theme_stylebox_override("pressed", empty_back)
	btn_back.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.2))
	btn_back.add_theme_color_override("icon_hover_color", Color(1.0, 0.85, 0.2))
	UIFontStyle.style_button(btn_back, 26)
	btn_back.pressed.connect(func(): GameManager.change_scene("res://scenes/main_menu.tscn"))
	top_bar.add_child(btn_back)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(header_spacer)

	# Keep hidden header_vbox so existing name_label and anime_label references remain valid in memory
	var header_vbox := VBoxContainer.new()
	header_vbox.visible = false
	root.add_child(header_vbox)

	name_label = Label.new()
	name_label.text = "HEN-GOKU"
	header_vbox.add_child(name_label)

	anime_label = Label.new()
	anime_label.text = "Dragon Ball (Goku)  |  HP: 22"
	header_vbox.add_child(anime_label)

	var fight_btn := Button.new()
	fight_btn.custom_minimum_size = Vector2(260, 58)
	fight_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var fight_style := StyleBoxFlat.new()
	fight_style.bg_color = Color(0.8, 0.12, 0.12, 0.95)
	fight_style.border_color = Color.GOLD
	fight_style.set_border_width_all(2)
	fight_style.set_corner_radius_all(10)
	fight_style.shadow_color = Color(1.0, 0.2, 0.2, 0.6)
	fight_style.shadow_size = 14
	fight_style.content_margin_left = 20
	fight_style.content_margin_right = 20
	fight_style.content_margin_top = 8
	fight_style.content_margin_bottom = 8
	fight_btn.add_theme_stylebox_override("normal", fight_style)
	
	var fight_hover := fight_style.duplicate() as StyleBoxFlat
	fight_hover.bg_color = Color(0.95, 0.2, 0.2, 1.0)
	fight_hover.shadow_size = 20
	fight_btn.add_theme_stylebox_override("hover", fight_hover)
	fight_btn.add_theme_stylebox_override("pressed", fight_hover)

	UIIcons.setup_centered_button(
		fight_btn,
		"FIGHT!",
		"swords",
		26,
		32,
		Color(1.0, 0.95, 0.2),
		Color.WHITE,
		12
	)
	fight_btn.pressed.connect(_confirm_and_start_battle)
	top_bar.add_child(fight_btn)


	# --- Bottom Roster Selection Cards: Large Fanned Overlapping Deck Lineup (300x420 px) ---
	var roster_layer := Control.new()
	roster_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	roster_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(roster_layer)

	var total_cards := roosters.size()
	var mid: float = float(total_cards - 1) * 0.5
	var card_w: float = 300.0
	var card_h: float = 420.0
	var step_x: float = 160.0
	var center_x: float = 1920.0 * 0.5
	var base_y: float = 1080.0 - card_h - 40.0 # 620.0 (40px clean breathing room above screen bottom)

	card_rest_positions.clear()
	card_rest_rotations.clear()
	roster_buttons.clear()

	for i in range(total_cards):
		var r: RoosterData = roosters[i]
		var offset: float = float(i) - mid
		var rx: float = center_x + offset * step_x - (card_w * 0.5)
		var ry: float = base_y + abs(offset) * 4.5
		var rrot: float = offset * 2.0
		var base_z: int = total_cards - i

		card_rest_positions.append(Vector2(rx, ry))
		card_rest_rotations.append(rrot)

		var r_btn := Button.new()
		r_btn.custom_minimum_size = Vector2(card_w, card_h)
		r_btn.size = Vector2(card_w, card_h)
		r_btn.position = Vector2(rx, ry)
		r_btn.rotation_degrees = rrot
		r_btn.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)
		r_btn.z_index = base_z
		r_btn.text = ""
		
		if r.portrait_path != "" and ResourceLoader.exists(r.portrait_path):
			r_btn.icon = load(r.portrait_path)
			r_btn.expand_icon = true
			r_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			r_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		
		var b_style := StyleBoxFlat.new()
		b_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
		b_style.border_color = Color(0.3, 0.35, 0.45, 0.5)
		b_style.set_border_width_all(1)
		b_style.set_corner_radius_all(18)
		r_btn.add_theme_stylebox_override("normal", b_style)
		
		var b_hover := b_style.duplicate() as StyleBoxFlat
		b_hover.border_color = Color(1.0, 0.85, 0.3)
		b_hover.shadow_size = 20
		b_hover.shadow_color = Color(1.0, 0.8, 0.2, 0.65)
		r_btn.add_theme_stylebox_override("hover", b_hover)
		
		# Smooth hover fan lift (temporarily raises card to inspect, then settles back flush into the fan)
		r_btn.mouse_entered.connect(func():
			r_btn.z_index = 35
			var tw := r_btn.create_tween()
			if tw:
				tw.set_parallel(true)
				tw.tween_property(r_btn, "position:y", ry - 45.0, 0.12).set_trans(Tween.TRANS_QUAD)
				tw.tween_property(r_btn, "rotation_degrees", rrot * 0.3, 0.12)
				tw.tween_property(r_btn, "scale", Vector2(1.06, 1.06), 0.12)
		)
		r_btn.mouse_exited.connect(func():
			var is_sel: bool = (current_index == i)
			r_btn.z_index = 20 if is_sel else (total_cards - i)
			var tw := r_btn.create_tween()
			if tw:
				tw.set_parallel(true)
				tw.tween_property(r_btn, "position:y", ry, 0.12).set_trans(Tween.TRANS_QUAD)
				tw.tween_property(r_btn, "rotation_degrees", rrot, 0.12)
				tw.tween_property(r_btn, "scale", Vector2.ONE, 0.12)
		)
		
		r_btn.pressed.connect(_on_roster_card_clicked.bind(i))
		roster_layer.add_child(r_btn)
		roster_buttons.append(r_btn)

func _confirm_and_start_battle() -> void:
	if is_transitioning:
		return
	var player_rooster: RoosterData = roosters[current_index]
	GameManager.selected_player_rooster = player_rooster

	# --- Online Match: Submit rooster to NetworkManager, wait for match_ready ---
	if GameManager.is_online_match and _nm:
		_nm.submit_rooster_choice(player_rooster.rooster_id)
		_show_online_waiting_label("Waiting for opponent's rooster choice…")
		return

	# --- Offline Modes ---
	GameManager.selected_opponent_rooster = GameManager.get_random_opponent(player_rooster)
	
	var is_tourney: bool = (
		GameManager.selected_game_mode == GameManager.GameMode.CASUAL_BOTS
	)

	# Flash transition to target scene
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.95, 0.8, 1.0)
	flash.modulate.a = 0.0
	ui_layer.add_child(flash)
	
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		if is_tourney:
			TournamentManager.start_new_tournament(player_rooster, TournamentManager.Format.SINGLE_ELIMINATION)
			GameManager.change_scene("res://scenes/bracketscene.tscn")
		else:
			TournamentManager.is_tournament_active = false
			GameManager.change_scene("res://scenes/arena.tscn")
	)

## Shows a waiting label overlay during online rooster negotiation
func _show_online_waiting_label(msg: String) -> void:
	if _online_waiting_label and is_instance_valid(_online_waiting_label):
		_online_waiting_label.text = msg
		return
	var overlay := Label.new()
	overlay.text = msg
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_bottom = -40
	UIFontStyle.style_body(overlay, 20, true)
	overlay.add_theme_color_override("font_color", Color.CYAN)
	_online_waiting_label = overlay
	ui_layer.add_child(overlay)

## Called when NetworkManager fires match_ready (both roosters chosen)
func _on_network_match_ready(p1_rooster_id: String, p2_rooster_id: String) -> void:
	if _online_waiting_label and is_instance_valid(_online_waiting_label):
		_online_waiting_label.queue_free()
	# Set opponent rooster from the synced ID
	var nm = _nm if _nm else get_node_or_null("/root/NetworkManager")
	var is_host: bool = nm.is_host if nm else false
	var opponent_id := p2_rooster_id if is_host else p1_rooster_id
	GameManager.selected_opponent_rooster = GameManager.get_rooster_by_id(opponent_id)
	# Load arena with flash transition
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.95, 0.8, 1.0)
	flash.modulate.a = 0.0
	ui_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		TournamentManager.is_tournament_active = false
		GameManager.change_scene("res://scenes/arena.tscn")
	)

## Called if opponent disconnects during rooster select
func _on_online_forfeit() -> void:
	if _online_waiting_label and is_instance_valid(_online_waiting_label):
		_online_waiting_label.text = "[DISCONNECTED] Opponent disconnected. Returning to menu…"
	await get_tree().create_timer(2.5).timeout
	GameManager.reset_online_state()
	GameManager.change_scene("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		var next_idx := (current_index - 1 + roosters.size()) % roosters.size()
		_on_roster_card_clicked(next_idx)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		var next_idx := (current_index + 1) % roosters.size()
		_on_roster_card_clicked(next_idx)
	elif event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
		_confirm_and_start_battle()
