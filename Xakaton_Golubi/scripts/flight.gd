extends Node3D
## 3D-полёт. Голубь летит вперёд (по -Z), игрок двигает его по высоте и в стороны.
## WASD/стрелки — лететь, Пробел или ЛКМ — удар крылом, E (или Q) — умение голубя.
## Все модели собраны из примитивов — потом можно заменить на .glb.

const SCALE := 20.0     # условные «пиксели» из game.gd -> единицы мира
const LATERAL := 10.0
const X_LIM := 8.0
const Y_MIN := 1.6
const Y_MAX := 8.0

var order: Dictionary
var pigeon: Dictionary
var length_w := 0.0
var world_speed := 11.0
var ppos := Vector3(0.0, 4.0, 0.0)
var hp := 3
var max_hp := 3
var ability := ""
var ability_cd := 0.0
var slap_cd := 0.0
var slap_radius := 4.5
var invuln := 0.0
var dash_t := 0.0
var shield_hits := 0
var shield_t := 0.0
var shake := 0.0
var finished := false
var delivered := false
var reported := false
var kills := 0
var t := 0.0
var spawn_t := 2.0
var quip_t := 4.0

var pigeon_node: Node3D
var wing_l: Node3D
var wing_r: Node3D
var shield_node: MeshInstance3D
var cam: Camera3D
var ground: MeshInstance3D
var road: MeshInstance3D
var buildings: Array = []
var cloud_nodes: Array = []
var drones: Array = []     # {node, rotors, hp, kind, cd, ph, kb, life}
var shots: Array = []      # вражеские пули {node, vel, life}
var feathers: Array = []   # перья игрока {node, vel, life}
var fxs: Array = []        # эффекты {node, mat, t, dur, r}

var hud_info: Label
var hud_stats: Label
var hud_prog: ProgressBar
var hud_quip: Label
var hud_over: ColorRect
var hud_over_text: Label


func _ready() -> void:
	var flight := Game.current_flight()
	order = flight["order"]
	pigeon = Game.pigeons[flight["pigeon"]]
	hp = pigeon["hp"]
	max_hp = pigeon["max_hp"]
	ability = pigeon["ability"]
	world_speed = Game.flight_speed(order, pigeon) / SCALE
	length_w = Game.flight_length(order) / SCALE
	slap_radius = 4.5 * Game.slap_mult
	_build_environment()
	_build_pigeon()
	_build_hud()
	cam.position = ppos + Vector3(0.0, 2.8, 9.0)
	hud_quip.text = "%s: «%s»" % [pigeon["name"], Game.QUIPS[randi() % Game.QUIPS.size()]]


# ---------- Помощники для примитивов ----------

func _mat(color: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	return c


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ---------- Мир ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3d7fd1")
	sky_mat.sky_horizon_color = Color("#bfe3f7")
	sky_mat.ground_horizon_color = Color("#bfe3f7")
	sky_mat.ground_bottom_color = Color("#9fc9a8")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color("#bfe3f7")
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	ground = MeshInstance3D.new()
	ground.mesh = pm
	ground.material_override = _mat(Color("#7fb069"))
	add_child(ground)

	var rm := PlaneMesh.new()
	rm.size = Vector2(12.0, 400.0)
	road = MeshInstance3D.new()
	road.mesh = rm
	road.material_override = _mat(Color("#4a4e57"))
	road.position.y = 0.03
	add_child(road)

	for i in 36:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(4.0, 9.0), randf_range(4.0, 22.0), randf_range(4.0, 9.0))
		b.mesh = bm
		b.material_override = _mat(Color.from_hsv(randf_range(0.04, 0.12), randf_range(0.1, 0.3), randf_range(0.6, 0.9)))
		add_child(b)
		_place_building(b, true)
		buildings.append(b)

	for i in 12:
		var c := Node3D.new()
		var cm := _mat(Color.WHITE, 0.0, 0.85)
		for k in 3:
			_part(c, _sphere(randf_range(4.0, 7.0)), cm, Vector3(randf_range(-6.0, 6.0), randf_range(-1.0, 1.0), randf_range(-3.0, 3.0)), Vector3(1.0, 0.55, 1.0))
		add_child(c)
		_place_cloud(c, true)
		cloud_nodes.append(c)


func _place_building(b: MeshInstance3D, initial: bool) -> void:
	var bm: BoxMesh = b.mesh
	var side := 1.0 if randf() < 0.5 else -1.0
	var z := ppos.z + randf_range(-170.0, 20.0) if initial else ppos.z - 170.0 - randf_range(0.0, 15.0)
	b.position = Vector3(side * randf_range(11.0, 45.0), bm.size.y * 0.5, z)


func _place_cloud(c: Node3D, initial: bool) -> void:
	var z := ppos.z + randf_range(-200.0, 30.0) if initial else ppos.z - 200.0 - randf_range(0.0, 20.0)
	c.position = Vector3(randf_range(-70.0, 70.0), randf_range(30.0, 50.0), z)


# ---------- Модель голубя ----------

func _build_pigeon() -> void:
	pigeon_node = Node3D.new()
	add_child(pigeon_node)
	var grey := _mat(Color("#9aa5b1"))
	var dark := _mat(Color("#6c7683"))
	var teal := _mat(Color("#3fa796"), 0.25)
	var orange := _mat(Color("#f4a261"))
	var black := _mat(Color("#111111"))

	_part(pigeon_node, _sphere(0.5), grey, Vector3.ZERO, Vector3(0.9, 0.85, 1.5))
	_part(pigeon_node, _sphere(0.3), teal, Vector3(0.0, 0.3, -0.55))
	_part(pigeon_node, _sphere(0.26), _mat(Color("#7d8794")), Vector3(0.0, 0.5, -0.82))
	_part(pigeon_node, _cyl(0.0, 0.08, 0.3), orange, Vector3(0.0, 0.46, -1.15), Vector3.ONE, Vector3(-PI / 2.0, 0.0, 0.0))
	for sx in [-1.0, 1.0]:
		_part(pigeon_node, _sphere(0.05), black, Vector3(sx * 0.13, 0.56, -0.98))
	_part(pigeon_node, _box(Vector3(0.4, 0.04, 0.6)), dark, Vector3(0.0, 0.0, 0.95), Vector3.ONE, Vector3(0.15, 0.0, 0.0))

	wing_l = Node3D.new()
	wing_l.position = Vector3(-0.38, 0.15, -0.05)
	pigeon_node.add_child(wing_l)
	_part(wing_l, _box(Vector3(1.1, 0.05, 0.65)), dark, Vector3(-0.55, 0.0, 0.1))
	wing_r = Node3D.new()
	wing_r.position = Vector3(0.38, 0.15, -0.05)
	pigeon_node.add_child(wing_r)
	_part(wing_r, _box(Vector3(1.1, 0.05, 0.65)), dark, Vector3(0.55, 0.0, 0.1))

	# Груз под брюшком.
	if order["type"] == "Посылка":
		_part(pigeon_node, _box(Vector3(0.45, 0.35, 0.45)), _mat(Color("#b08968")), Vector3(0.0, -0.55, -0.05))
		_part(pigeon_node, _box(Vector3(0.47, 0.06, 0.1)), _mat(Color("#e9c46a")), Vector3(0.0, -0.55, -0.05))
	else:
		_part(pigeon_node, _box(Vector3(0.4, 0.05, 0.28)), _mat(Color.WHITE), Vector3(0.0, -0.52, -0.05))
		_part(pigeon_node, _sphere(0.05), _mat(Color("#e63946")), Vector3(0.0, -0.5, -0.05))

	shield_node = _part(pigeon_node, _sphere(1.7), _mat(Color("#4cc9f0"), 1.5, 0.25), Vector3(0.0, 0.2, 0.0))
	shield_node.visible = false
	pigeon_node.position = ppos


# ---------- Модель дрона ----------

func _build_drone(kind: String) -> Dictionary:
	var root := Node3D.new()
	var model := Node3D.new()
	root.add_child(model)
	var shooter := kind == "shooter"
	if shooter:
		model.scale = Vector3.ONE * 1.3
	var body_col := Color("#6a040f") if shooter else Color("#2b2d42")
	var accent := Color("#e85d04") if shooter else Color("#8d99ae")
	var body := _mat(body_col)
	var acc := _mat(accent, 0.8)
	var rotors: Array = []

	_part(model, _sphere(0.45), body, Vector3.ZERO, Vector3(1.2, 0.55, 1.4))              # корпус
	_part(model, _sphere(0.3), _mat(accent), Vector3(0.0, 0.14, 0.1), Vector3(1.0, 0.5, 1.1))  # купол
	_part(model, _sphere(0.14), _mat(Color("#ff1d25"), 3.0), Vector3(0.0, 0.0, -0.62), Vector3(1.0, 1.0, 0.6))  # «глаз»
	_part(model, _sphere(0.13), _mat(Color("#1b1b1b")), Vector3(0.0, -0.3, -0.3))         # подвес камеры

	for sx in [-1.0, 1.0]:
		_part(model, _box(Vector3(0.05, 0.05, 0.9)), body, Vector3(sx * 0.4, -0.42, 0.0))  # лыжи шасси
		for sz in [-1.0, 1.0]:
			var ang := atan2(-sz, sx)
			_part(model, _box(Vector3(0.9, 0.06, 0.08)), body, Vector3(sx * 0.45, 0.05, sz * 0.45), Vector3.ONE, Vector3(0.0, ang, 0.0))  # луч
			_part(model, _cyl(0.1, 0.1, 0.14), body, Vector3(sx * 0.77, 0.1, sz * 0.77))   # мотор
			_part(model, _sphere(0.04), acc, Vector3(sx * 0.77, 0.0, sz * 0.77))           # светодиод
			var rotor := Node3D.new()
			rotor.position = Vector3(sx * 0.77, 0.2, sz * 0.77)
			model.add_child(rotor)
			_part(rotor, _box(Vector3(0.9, 0.012, 0.07)), _mat(Color("#cfd8dc")))
			_part(rotor, _box(Vector3(0.07, 0.012, 0.9)), _mat(Color("#cfd8dc")))
			_part(rotor, _cyl(0.44, 0.44, 0.008), _mat(Color.WHITE, 0.0, 0.12))
			rotors.append(rotor)

	if shooter:
		_part(model, _cyl(0.07, 0.09, 0.7), _mat(Color("#222222")), Vector3(0.0, -0.15, -0.85), Vector3.ONE, Vector3(-PI / 2.0, 0.0, 0.0))  # ствол
	else:
		_part(model, _cyl(0.015, 0.015, 0.4), body, Vector3(0.0, 0.4, 0.35))               # антенна
		_part(model, _sphere(0.04), _mat(Color("#ff1d25"), 3.0), Vector3(0.0, 0.6, 0.35))
	return {"node": root, "rotors": rotors}


# ---------- HUD ----------

func _hud_label(layer: CanvasLayer, p: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = p
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	layer.add_child(l)
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_info = _hud_label(layer, Vector2(20.0, 14.0), 22)
	hud_stats = _hud_label(layer, Vector2(20.0, 46.0), 18)
	hud_prog = ProgressBar.new()
	hud_prog.position = Vector2(20.0, 80.0)
	hud_prog.size = Vector2(420.0, 16.0)
	hud_prog.max_value = 1.0
	hud_prog.show_percentage = false
	hud_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_prog)
	hud_quip = _hud_label(layer, Vector2(20.0, 106.0), 18)
	var help := _hud_label(layer, Vector2(20.0, 685.0), 15)
	help.text = "WASD/стрелки — лететь | Пробел/ЛКМ — удар крылом | E — умение"

	hud_over = ColorRect.new()
	hud_over.color = Color(0, 0, 0, 0.55)
	hud_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_over.visible = false
	layer.add_child(hud_over)
	hud_over_text = Label.new()
	hud_over_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_over_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_over_text.add_theme_font_size_override("font_size", 40)
	hud_over.add_child(hud_over_text)


func _update_hud() -> void:
	var info: Dictionary = Game.ABILITIES[ability]
	hud_info.text = "%s → %s  |  %s" % [order["type"], order["place"], pigeon["name"]]
	var slap_txt := "готов" if slap_cd <= 0.0 else "%.1f" % slap_cd
	var ab_txt := "готово (E)" if ability_cd <= 0.0 else "%.0f с" % ability_cd
	hud_stats.text = "HP %d/%d   сбито: %d   Удар: %s   %s: %s" % [hp, max_hp, kills, slap_txt, info["name"], ab_txt]
	hud_prog.value = clampf(-ppos.z / length_w, 0.0, 1.0)


# ---------- Главный цикл ----------

func _process(delta: float) -> void:
	t += delta
	_update_fx(delta)
	# Взмахи крыльев.
	var flap := sin(t * 16.0) * 0.6
	wing_l.rotation.z = -flap
	wing_r.rotation.z = flap
	if finished:
		return

	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y -= 1.0
	dir = dir.normalized()
	ppos.x = clampf(ppos.x + dir.x * LATERAL * delta, -X_LIM, X_LIM)
	ppos.y = clampf(ppos.y + dir.y * LATERAL * delta, Y_MIN, Y_MAX)
	var spd := world_speed * (2.4 if dash_t > 0.0 else 1.0)
	ppos.z -= spd * delta

	slap_cd = maxf(0.0, slap_cd - delta)
	ability_cd = maxf(0.0, ability_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	dash_t = maxf(0.0, dash_t - delta)
	shake = maxf(0.0, shake - delta)
	if shield_hits > 0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_hits = 0
			shield_node.visible = false
	quip_t -= delta
	if quip_t <= 0.0:
		hud_quip.visible = false

	pigeon_node.position = ppos
	pigeon_node.rotation.z = lerpf(pigeon_node.rotation.z, -dir.x * 0.45, 8.0 * delta)
	pigeon_node.rotation.x = lerpf(pigeon_node.rotation.x, dir.y * 0.3, 8.0 * delta)
	pigeon_node.visible = not (invuln > 0.0 and int(t * 12.0) % 2 == 0)

	_update_camera(delta)
	_update_world()

	spawn_t -= delta
	if spawn_t <= 0.0:
		_spawn_drone()
		spawn_t = Game.spawn_interval(order) * 1.2 * randf_range(0.7, 1.3)

	_update_drones(delta)
	_update_shots(delta)
	_update_feathers(delta)
	_update_hud()

	if -ppos.z >= length_w:
		_finish(true)
	elif hp <= 0:
		_finish(false)


func _update_camera(delta: float) -> void:
	var target := ppos + Vector3(-ppos.x * 0.3, 2.8, 9.0)
	cam.position = cam.position.lerp(target, 6.0 * delta)
	if shake > 0.0:
		cam.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake * 0.6
	cam.look_at(Vector3(ppos.x * 0.6, ppos.y, ppos.z - 10.0), Vector3.UP)


func _update_world() -> void:
	ground.position.z = ppos.z
	road.position.z = ppos.z
	for b in buildings:
		if b.position.z > ppos.z + 25.0:
			_place_building(b, false)
	for c in cloud_nodes:
		if c.position.z > ppos.z + 40.0:
			_place_cloud(c, false)


# ---------- Дроны ----------

func _spawn_drone() -> void:
	var kind := "shooter" if Game.day >= 3 and randf() < 0.35 else "scout"
	var built := _build_drone(kind)
	var node: Node3D = built["node"]
	node.position = Vector3(randf_range(-X_LIM, X_LIM), randf_range(Y_MIN, Y_MAX), ppos.z - randf_range(55.0, 70.0))
	add_child(node)
	drones.append({
		"node": node,
		"rotors": built["rotors"],
		"hp": 2 if kind == "shooter" else 1,
		"kind": kind,
		"cd": randf_range(1.0, 2.0),
		"ph": randf() * TAU,
		"kb": Vector3.ZERO,
		"life": 12.0,
	})


func _kill_drone(i: int) -> void:
	var d: Dictionary = drones[i]
	var node: Node3D = d["node"]
	_spawn_fx(node.position, 1.8, Color("#ff9f1c"), 0.3)
	node.queue_free()
	drones.remove_at(i)
	kills += 1


func _update_drones(delta: float) -> void:
	var i := drones.size() - 1
	while i >= 0:
		var d: Dictionary = drones[i]
		var node: Node3D = d["node"]
		var p := node.position
		var kb: Vector3 = d["kb"]
		d["life"] -= delta
		if d["kind"] == "scout":
			p += (ppos - p).normalized() * 7.5 * delta
		else:
			var ph: float = d["ph"]
			p.z = lerpf(p.z, ppos.z - 32.0, 1.5 * delta)
			p.x = lerpf(p.x, clampf(ppos.x + sin(t * 1.1 + ph) * 6.0, -X_LIM, X_LIM), 1.2 * delta)
			p.y = lerpf(p.y, clampf(ppos.y + cos(t * 0.9 + ph) * 2.0, Y_MIN, Y_MAX), 1.2 * delta)
			d["cd"] -= delta
			if d["cd"] <= 0.0:
				_spawn_shot(p)
				d["cd"] = 2.2
		p += kb * delta
		d["kb"] = kb.lerp(Vector3.ZERO, 5.0 * delta)
		node.position = p
		if p.distance_to(ppos) > 0.5:
			node.look_at(ppos, Vector3.UP)
		for r in d["rotors"]:
			r.rotation.y += 45.0 * delta

		var remove := false
		if p.distance_to(ppos) < 1.5:
			if invuln <= 0.0:
				_hit()
			_spawn_fx(p, 1.8, Color("#ff9f1c"), 0.3)
			remove = true
		elif p.z > ppos.z + 12.0 or d["life"] <= 0.0:
			remove = true
		if remove:
			node.queue_free()
			drones.remove_at(i)
		i -= 1


func _spawn_shot(from: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _sphere(0.2)
	m.material_override = _mat(Color("#ff3b3b"), 3.0)
	m.position = from
	add_child(m)
	var aim := ppos + Vector3(0.0, 0.0, -world_speed * 0.4)
	shots.append({"node": m, "vel": (aim - from).normalized() * 22.0, "life": 6.0})


func _update_shots(delta: float) -> void:
	var i := shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		var node: Node3D = s["node"]
		var vel: Vector3 = s["vel"]
		node.position += vel * delta
		s["life"] -= delta
		var remove := false
		if node.position.distance_to(ppos) < 0.9:
			if invuln <= 0.0:
				_hit()
			remove = true
		elif s["life"] <= 0.0 or node.position.z > ppos.z + 10.0:
			remove = true
		if remove:
			node.queue_free()
			shots.remove_at(i)
		i -= 1


func _update_feathers(delta: float) -> void:
	var i := feathers.size() - 1
	while i >= 0:
		var f: Dictionary = feathers[i]
		var node: Node3D = f["node"]
		var vel: Vector3 = f["vel"]
		node.position += vel * delta
		f["life"] -= delta
		var remove: bool = f["life"] <= 0.0
		var j := drones.size() - 1
		while j >= 0 and not remove:
			var d: Dictionary = drones[j]
			var dn: Node3D = d["node"]
			if dn.position.distance_to(node.position) < 1.4:
				d["hp"] -= 1
				if d["hp"] <= 0:
					_kill_drone(j)
				remove = true
			j -= 1
		if remove:
			node.queue_free()
			feathers.remove_at(i)
		i -= 1


# ---------- Бой и умения ----------

func _hit() -> void:
	if shield_hits > 0:
		shield_hits -= 1
		invuln = 0.4
		_spawn_fx(ppos, 2.2, Color("#4cc9f0"), 0.25)
		if shield_hits <= 0:
			shield_node.visible = false
		return
	hp -= 1
	invuln = 1.2
	shake = 0.35


func _slap() -> void:
	slap_cd = 0.55
	_spawn_fx(ppos, slap_radius, Color.WHITE, 0.22)
	_blast(slap_radius, 1, 18.0)


## Урон по дронам и пулям в радиусе вокруг голубя.
func _blast(radius: float, damage: int, knock: float) -> void:
	var i := drones.size() - 1
	while i >= 0:
		var d: Dictionary = drones[i]
		var node: Node3D = d["node"]
		if node.position.distance_to(ppos) <= radius:
			d["hp"] -= damage
			d["kb"] = (node.position - ppos).normalized() * knock
			if d["hp"] <= 0:
				_kill_drone(i)
		i -= 1
	i = shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		var sn: Node3D = s["node"]
		if sn.position.distance_to(ppos) <= radius:
			sn.queue_free()
			shots.remove_at(i)
		i -= 1


func _use_ability() -> void:
	if ability_cd > 0.0 or finished:
		return
	var info: Dictionary = Game.ABILITIES[ability]
	ability_cd = info["cd"]
	match ability:
		"dash":
			dash_t = 0.8
			invuln = maxf(invuln, 0.8)
		"shield":
			shield_hits = 2
			shield_t = 5.0
			shield_node.visible = true
		"scream":
			var r := 16.0 * Game.slap_mult
			_spawn_fx(ppos, r, Color("#ffd166"), 0.45)
			_blast(r, 2, 25.0)
		"feathers":
			for k in 5:
				var a := (k - 2) * 0.14
				var m := _part(self, _box(Vector3(0.08, 0.04, 0.7)), _mat(Color.WHITE, 1.2))
				m.position = ppos + Vector3(0.0, 0.0, -1.2)
				feathers.append({"node": m, "vel": Vector3(sin(a) * 12.0, 0.0, -(world_speed + 28.0) * cos(a)), "life": 1.6})
		"mend":
			hp = mini(max_hp, hp + 1)
			_spawn_fx(ppos, 2.5, Color("#80ed99"), 0.5)


func _spawn_fx(pos: Vector3, radius: float, color: Color, dur: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	m.mesh = sm
	var mat := _mat(color, 2.0, 0.5)
	m.material_override = mat
	m.position = pos
	m.scale = Vector3.ONE * radius * 0.2
	add_child(m)
	fxs.append({"node": m, "mat": mat, "t": 0.0, "dur": dur, "r": radius})


func _update_fx(delta: float) -> void:
	var i := fxs.size() - 1
	while i >= 0:
		var f: Dictionary = fxs[i]
		var node: Node3D = f["node"]
		var mat: StandardMaterial3D = f["mat"]
		f["t"] += delta
		var k: float = clampf(f["t"] / f["dur"], 0.0, 1.0)
		var r: float = f["r"]
		node.scale = Vector3.ONE * lerpf(r * 0.2, r, k)
		var c: Color = mat.albedo_color
		c.a = 0.5 * (1.0 - k)
		mat.albedo_color = c
		if k >= 1.0:
			node.queue_free()
			fxs.remove_at(i)
		i -= 1


# ---------- Конец полёта ----------

func _finish(ok: bool) -> void:
	finished = true
	delivered = ok
	hud_over.visible = true
	hud_over_text.text = ("Доставлено!" if ok else "Голубь сбит…") + "\n\nEnter или клик — дальше"


func _continue() -> void:
	if reported:
		return
	reported = true
	Game.report_flight(delivered, hp)
	Game.after_flight(get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		var enter: bool = event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
		var click: bool = event is InputEventMouseButton and event.pressed
		if enter or click:
			_continue()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and slap_cd <= 0.0:
			_slap()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			_use_ability()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and slap_cd <= 0.0:
		_slap()
