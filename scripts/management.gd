extends Control
## Меню-менеджмент: выбираем, какой голубь везёт какой заказ, смотрим расчёты, отправляем.

var assign := {}  # индекс заказа -> индекс голубя


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


func _build() -> void:
	_clear()
	var bg := ColorRect.new()
	bg.color = Color("#264653")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	if Game.game_over or Game.run_won:
		_build_end(box)
		return

	box.add_child(_label("Голубиная почта — день %d из %d    Золото: %d" % [Game.day, Game.DAYS_PER_RUN, Game.gold], 26, Color("#e9c46a")))

	if Game.results.size() > 0:
		box.add_child(_label("Вчера: " + " | ".join(Game.results), 15, Color("#a8dadc")))

	var st: Dictionary = Game.STORY.get(Game.day, {})
	if not st.is_empty():
		box.add_child(_label("Сюжет · " + str(st["title"]), 20, Color("#f4a261")))
		var story := _label(str(st["text"]), 16, Color("#f1faee"))
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(story)

	if Game.relic_choices.size() > 0:
		box.add_child(_label("Выберите реликвию:", 20, Color("#f4a261")))
		var rbox := HBoxContainer.new()
		for r in Game.relic_choices:
			var b := Button.new()
			b.text = "%s\n%s" % [r["name"], r["desc"]]
			b.custom_minimum_size = Vector2(260, 60)
			b.pressed.connect(_on_relic.bind(r["id"]))
			rbox.add_child(b)
		box.add_child(rbox)

	# --- Голуби ---
	box.add_child(_label("Голуби:", 20, Color("#2a9d8f")))
	for p in Game.pigeons:
		var ab: Dictionary = Game.ABILITIES[p["ability"]]
		var line := "%s — HP %d/%d, груз %.1f, умение: %s (%s)" % [p["name"], p["hp"], p["max_hp"], p["capacity"], ab["name"], ab["desc"]]
		if not p["alive"]:
			line = "%s — погиб" % p["name"]
		box.add_child(_label("  " + line, 16))

	# --- Заказы ---
	box.add_child(_label("Заказы:", 20, Color("#2a9d8f")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var total_feed := 0
	var total_income := 0
	for i in Game.orders.size():
		var order: Dictionary = Game.orders[i]
		var row := HBoxContainer.new()
		var info := _label("[%s] %s, %.1f км, вес %.1f | награда %d, корм %d" % [order["type"], order["place"], order["dist"], order["weight"], Game.payout(order), order["feed"]], 16)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(420, 0)
		opt.add_item("— не отправлять —", 0)
		for p_idx in Game.pigeons.size():
			var pg: Dictionary = Game.pigeons[p_idx]
			var ok: bool = pg["alive"] and pg["capacity"] >= order["weight"]
			var t := Game.flight_time(order, pg)
			opt.add_item("%s (HP %d) ~%d с, дронов ~%d" % [pg["name"], pg["hp"], int(t), Game.expected_drones(order, pg)], p_idx + 1)
			opt.set_item_disabled(opt.get_item_count() - 1, not ok)
		var sel := 0
		if assign.has(i):
			sel = int(assign[i]) + 1
			total_feed += order["feed"]
			total_income += Game.payout(order)
		opt.select(sel)
		opt.item_selected.connect(_on_pick.bind(i))
		row.add_child(opt)
		list.add_child(row)

	# --- Магазин ---
	var shop := HBoxContainer.new()
	var heal := Button.new()
	heal.text = "Подкормить всех (+1 HP) — %d" % Game.HEAL_COST
	heal.disabled = Game.gold < Game.HEAL_COST
	heal.pressed.connect(_on_heal)
	shop.add_child(heal)
	var hire := Button.new()
	hire.text = "Нанять голубя — %d" % Game.HIRE_COST
	hire.disabled = Game.gold < Game.HIRE_COST or Game.pigeons.size() >= Game.MAX_PIGEONS
	hire.pressed.connect(_on_hire)
	shop.add_child(hire)
	box.add_child(shop)

		# --- Отправка (Правый нижний угол) ---
	var bottom_right := MarginContainer.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.add_theme_constant_override("margin_right", 20)
	bottom_right.add_theme_constant_override("margin_bottom", 20)
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom_right)

	var corner_box := VBoxContainer.new()
	corner_box.add_theme_constant_override("separation", 5)
	bottom_right.add_child(corner_box)

	# Текст с расчетом дня
	corner_box.add_child(_label("Расчёт дня: корм −%d, ожидаемый доход +%d" % [total_feed, total_income], 18, Color("#e9c46a")))

	# Сама кнопка
	var send := Button.new()
	send.text = "Играть"
	send.custom_minimum_size = Vector2(250, 48) # Лучше задать фиксированную ширину
	send.disabled = assign.is_empty() or total_feed > Game.gold or Game.relic_choices.size() > 0
	send.pressed.connect(_on_send)
	
	# ВОТ ГЛАВНОЕ ИСПРАВЛЕНИЕ: добавляем кнопку в corner_box, а не в box!
	corner_box.add_child(send) 


func _build_end(box: VBoxContainer) -> void:
	var title := "Забег пройден! Итог: %d золота" % Game.gold if Game.run_won else "Забег окончен"
	box.add_child(_label(title, 32, Color("#e9c46a")))
	var ending := _label(Game.ending_text(), 20, Color("#f1faee"))
	ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ending)
	var again := Button.new()
	again.text = "Новый забег"
	again.custom_minimum_size = Vector2(0, 56)
	again.pressed.connect(_on_restart)
	box.add_child(again)


func _on_pick(index: int, order_idx: int) -> void:
	if index == 0:
		assign.erase(order_idx)
	else:
		var p := index - 1
		for k in assign.keys():
			if assign[k] == p:
				assign.erase(k)
		assign[order_idx] = p
	_build()


func _on_relic(id: String) -> void:
	Game.take_relic(id)
	_build()


func _on_heal() -> void:
	Game.heal_all()
	_build()


func _on_hire() -> void:
	Game.hire_pigeon()
	_build()


func _on_restart() -> void:
	Game.new_run()
	assign = {}
	_build()


func _on_send() -> void:
	Game.start_flights(assign)
	get_tree().change_scene_to_file(Game.FLIGHT_SCENE)
