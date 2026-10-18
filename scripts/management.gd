extends Control
## Лобби: видео-фон на весь экран, зоны UI по углам, попапы выбора.

var selected_pigeon: int = -1
var selected_order: int = -1

var pigeon_button: Button
var order_button: Button
var play_button: Button
var hint_label: Label
var calc_label: Label

var pigeon_popup: PopupPanel
var order_popup: PopupPanel


func _ready() -> void:
	if Game.pigeons.is_empty():
		Game.new_run()
	_build()


func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()


func _label(text: String, size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# Полупрозрачная плашка для читаемости поверх видео.
func _panel(alpha := 0.55) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, alpha)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", style)
	return p


func _build() -> void:
	_clear()

	# --- Фон и видео на весь экран ---
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var video := VideoStreamPlayer.new()
	video.stream = load("res://pigeon_background.ogv")
	video.autoplay = true
	video.loop = true
	video.expand = true
	video.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(video)

	# Лёгкое затемнение, чтобы текст читался.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	if Game.game_over or Game.run_won:
		_build_end()
		return

	_build_top_left()
	_build_top_right_story()
	_build_left_loft()
	_build_right_relics()
	_build_bottom_left_calc()
	_build_bottom_right_controls()
	_refresh_bottom_controls()


# ---------- Сверху слева: день и золото ----------

func _build_top_left() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 20.0
	p.offset_top = 16.0
	add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	p.add_child(box)
	box.add_child(_label("День %d / %d" % [Game.day, Game.DAYS_PER_RUN], 18, Color("#a8dadc")))
	box.add_child(_label("🪙 %d" % Game.gold, 28, Color("#e9c46a")))


# ---------- Сверху справа: сюжет ----------

func _build_top_right_story() -> void:
	var st: Dictionary = Game.STORY.get(Game.day, {})
	if st.is_empty() and Game.results.is_empty():
		return
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -460.0
	p.offset_right = -20.0
	p.offset_top = 16.0
	add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)

	if Game.results.size() > 0:
		var r := _label("Вчера: " + " | ".join(Game.results), 14, Color("#a8dadc"))
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(r)

	if not st.is_empty():
		box.add_child(_label("Сюжет · " + str(st["title"]), 18, Color("#f4a261")))
		var story := _label(str(st["text"]), 15, Color("#f1faee"))
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size = Vector2(420, 0)
		box.add_child(story)


# ---------- Слева: голубятня ----------

func _build_left_loft() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	p.offset_left = 20.0
	p.offset_right = 20.0 + 360.0
	p.offset_top = -170.0
	p.offset_bottom = 170.0
	add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	box.add_child(_label("Голубятня", 20, Color("#2a9d8f")))

	for pg in Game.pigeons:
		var ab: Dictionary = Game.ABILITIES[pg["ability"]]
		var line := "%s · HP %d/%d · груз %.1f · %s" % [pg["name"], pg["hp"], pg["max_hp"], pg["capacity"], ab["name"]]
		if not pg["alive"]:
			line = "%s — погиб" % pg["name"]
		box.add_child(_label("• " + line, 14))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var heal := Button.new()
	heal.text = "Подкормить всех (+1 HP) — %d" % Game.HEAL_COST
	heal.custom_minimum_size = Vector2(0, 36)
	heal.disabled = Game.gold < Game.HEAL_COST
	heal.pressed.connect(_on_heal)
	box.add_child(heal)

	var hire := Button.new()
	hire.text = "Нанять голубя — %d" % Game.HIRE_COST
	hire.custom_minimum_size = Vector2(0, 36)
	hire.disabled = Game.gold < Game.HIRE_COST or Game.pigeons.size() >= Game.MAX_PIGEONS
	hire.pressed.connect(_on_hire)
	box.add_child(hire)


# ---------- Справа: реликвии ----------

func _build_right_relics() -> void:
	if Game.relic_choices.is_empty():
		return
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.offset_left = -380.0
	p.offset_right = -20.0
	p.offset_top = -170.0
	p.offset_bottom = 170.0
	add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	box.add_child(_label("Выберите реликвию", 20, Color("#f4a261")))
	for r in Game.relic_choices:
		var b := Button.new()
		b.text = "%s\n%s" % [r["name"], r["desc"]]
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(_on_relic.bind(r["id"]))
		box.add_child(b)


# ---------- Снизу слева: расчёт ----------

func _build_bottom_left_calc() -> void:
	var p := _panel(0.45)
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.offset_left = 20.0
	p.offset_bottom = -20.0
	add_child(p)
	calc_label = _label("", 16, Color("#e9c46a"))
	p.add_child(calc_label)


# ---------- Снизу справа: выбор и «Играть» ----------

func _build_bottom_right_controls() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_left = -380.0
	col.offset_right = -20.0
	col.offset_top = -250.0
	col.offset_bottom = -20.0
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_END
	add_child(col)

	pigeon_button = Button.new()
	pigeon_button.custom_minimum_size = Vector2(360, 44)
	pigeon_button.add_theme_font_size_override("font_size", 18)
	pigeon_button.pressed.connect(_open_pigeon_popup)
	col.add_child(pigeon_button)

	order_button = Button.new()
	order_button.custom_minimum_size = Vector2(360, 44)
	order_button.add_theme_font_size_override("font_size", 18)
	order_button.pressed.connect(_open_order_popup)
	col.add_child(order_button)

	play_button = Button.new()
	play_button.text = "ИГРАТЬ"
	play_button.custom_minimum_size = Vector2(360, 90)
	play_button.add_theme_font_size_override("font_size", 32)
	play_button.pressed.connect(_on_play)
	col.add_child(play_button)

	hint_label = _label("", 15, Color("#f1faee"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.custom_minimum_size = Vector2(360, 0)
	col.add_child(hint_label)

	pigeon_popup = _make_popup()
	order_popup = _make_popup()


func _make_popup() -> PopupPanel:
	var p := PopupPanel.new()
	add_child(p)
	return p


# ---------- Обновление нижних кнопок и расчёта ----------

func _refresh_bottom_controls() -> void:
	if selected_pigeon >= 0 and selected_pigeon < Game.pigeons.size():
		var p: Dictionary = Game.pigeons[selected_pigeon]
		pigeon_button.text = "Голубь: %s (HP %d/%d)" % [p["name"], p["hp"], p["max_hp"]]
	else:
		pigeon_button.text = "Выбрать голубя"

	if selected_order >= 0 and selected_order < Game.orders.size():
		var o: Dictionary = Game.orders[selected_order]
		order_button.text = "Заказ: %s → %s (%d🪙)" % [o["type"], o["place"], Game.payout(o)]
	else:
		order_button.text = "Выбрать заказ"

	var ok := true
	var reason := ""
	if selected_pigeon < 0:
		ok = false
		reason = "Выбери голубя"
	elif selected_order < 0:
		ok = false
		reason = "Выбери заказ"
	else:
		var p: Dictionary = Game.pigeons[selected_pigeon]
		var o: Dictionary = Game.orders[selected_order]
		if not p["alive"]:
			ok = false
			reason = "Голубь погиб"
		elif p["capacity"] < o["weight"]:
			ok = false
			reason = "Голубь не поднимет такой груз"
		elif Game.gold < o["feed"]:
			ok = false
			reason = "Не хватает золота на корм"
	play_button.disabled = not ok
	hint_label.text = reason

	if selected_order >= 0 and selected_order < Game.orders.size():
		var o: Dictionary = Game.orders[selected_order]
		calc_label.text = "Расчёт: корм −%d, доход +%d" % [o["feed"], Game.payout(o)]
	else:
		calc_label.text = "Расчёт: выбери заказ"


# ---------- Попап выбора голубя ----------

func _open_pigeon_popup() -> void:
	var content := _popup_content(pigeon_popup)
	content.add_child(_label("Выбери голубя", 22, Color("#e9c46a")))
	for i in Game.pigeons.size():
		var p: Dictionary = Game.pigeons[i]
		var ab: Dictionary = Game.ABILITIES[p["ability"]]
		var b := Button.new()
		var text := "%s — HP %d/%d, груз %.1f, %s" % [p["name"], p["hp"], p["max_hp"], p["capacity"], ab["name"]]
		if not p["alive"]:
			text = "%s — погиб" % p["name"]
			b.disabled = true
		b.text = text
		b.custom_minimum_size = Vector2(460, 48)
		b.pressed.connect(_on_pigeon_chosen.bind(i))
		content.add_child(b)
	var close := Button.new()
	close.text = "Отмена"
	close.custom_minimum_size = Vector2(460, 40)
	close.pressed.connect(pigeon_popup.hide)
	content.add_child(close)
	pigeon_popup.popup_centered()


func _on_pigeon_chosen(index: int) -> void:
	selected_pigeon = index
	pigeon_popup.hide()
	_refresh_bottom_controls()


# ---------- Попап выбора заказа ----------

func _open_order_popup() -> void:
	var content := _popup_content(order_popup)
	content.add_child(_label("Выбери заказ", 22, Color("#e9c46a")))
	for i in Game.orders.size():
		var o: Dictionary = Game.orders[i]
		var b := Button.new()
		b.text = "[%s] %s · %.1f км · вес %.1f · %d🪙 · корм %d" % [
			o["type"], o["place"], o["dist"], o["weight"], Game.payout(o), o["feed"]
		]
		b.custom_minimum_size = Vector2(620, 48)
		b.pressed.connect(_on_order_chosen.bind(i))
		content.add_child(b)
	var close := Button.new()
	close.text = "Отмена"
	close.custom_minimum_size = Vector2(620, 40)
	close.pressed.connect(order_popup.hide)
	content.add_child(close)
	order_popup.popup_centered()


func _on_order_chosen(index: int) -> void:
	selected_order = index
	order_popup.hide()
	_refresh_bottom_controls()


func _popup_content(popup: PopupPanel) -> VBoxContainer:
	for c in popup.get_children():
		c.queue_free()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	popup.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box


# ---------- Играть ----------

func _on_play() -> void:
	if selected_pigeon < 0 or selected_order < 0:
		return
	var assign := {selected_order: selected_pigeon}
	Game.start_flights(assign)
	get_tree().change_scene_to_file(Game.FLIGHT_SCENE)


# ---------- Магазин / реликвии ----------

func _on_relic(id: String) -> void:
	Game.take_relic(id)
	_build()


func _on_heal() -> void:
	Game.heal_all()
	_build()


func _on_hire() -> void:
	Game.hire_pigeon()
	_build()


# ---------- Конец забега ----------

func _build_end() -> void:
	var end := Control.new()
	end.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(end)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	end.add_child(dim)

	var p := _panel(0.85)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -420.0
	p.offset_right = 420.0
	p.offset_top = -180.0
	p.offset_bottom = 180.0
	end.add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	p.add_child(box)

	var title := "Забег пройден! Итог: %d золота" % Game.gold if Game.run_won else "Забег окончен"
	box.add_child(_label(title, 32, Color("#e9c46a")))
	var ending := _label(Game.ending_text(), 18, Color("#f1faee"))
	ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ending)
	var again := Button.new()
	again.text = "Новый забег"
	again.custom_minimum_size = Vector2(0, 56)
	again.pressed.connect(_on_restart)
	box.add_child(again)


func _on_restart() -> void:
	Game.new_run()
	selected_pigeon = -1
	selected_order = -1
	_build()
