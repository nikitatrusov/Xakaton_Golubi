extends Control

func _ready() -> void:
	_build()

func _build() -> void:
	# 1. Фон
	var bg := ColorRect.new()
	bg.color = Color("#264653") # Тот же цвет, что и в меню управления
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 2. Контейнер по центру
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	# 3. Заголовок
	var title := Label.new()
	title.text = "ГОЛУБИНАЯ ПОЧТА"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#e9c46a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# 4. Кнопка "Начать игру"
	var start_btn := Button.new()
	start_btn.text = "Начать забег"
	start_btn.custom_minimum_size = Vector2(300, 60)
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.pressed.connect(_on_start_pressed)
	box.add_child(start_btn)

	# 5. Кнопка "Выход" (опционально)
	var quit_btn := Button.new()
	quit_btn.text = "Выход"
	quit_btn.custom_minimum_size = Vector2(300, 60)
	quit_btn.add_theme_font_size_override("font_size", 24)
	quit_btn.pressed.connect(_on_quit_pressed)
	box.add_child(quit_btn)

func _on_start_pressed() -> void:
	# Переход на экран управления (ваш текущий скрипт)
	# Вам нужно заменить "res://Management.tscn" на реальный путь к вашей сцене управления
	get_tree().change_scene_to_file("res://Management.tscn") 

func _on_quit_pressed() -> void:
	get_tree().quit()
