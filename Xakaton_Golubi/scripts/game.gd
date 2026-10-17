extends Node
## Автолоад «Game»: всё состояние забега (рана), экономика, способности и сюжет.

const MANAGEMENT_SCENE := "res://scenes/management.tscn"
const FLIGHT_SCENE := "res://scenes/flight.tscn"

const DAYS_PER_RUN := 7
const MAX_PIGEONS := 5
const HIRE_COST := 40
const HEAL_COST := 10
const PX_PER_KM := 1200.0   # «длина» полёта в условных пикселях на 1 км (в 3D делится на 20)
const BASE_SPEED := 220.0   # условная скорость полёта

const PLACES := ["Соседний двор", "Рынок", "Вокзал", "Порт", "Горная застава", "Соседний город"]
const NAMES := ["Гоша", "Сизый", "Булка", "Кеша", "Пух", "Зефир", "Граф", "Муся", "Чижик", "Барон", "Крошка", "Орлан", "Пончик", "Тоша"]

# Умения голубей: активируются клавишей E в полёте.
const ABILITIES := {
	"dash": {"name": "Рывок", "desc": "бросок вперёд и неуязвимость 0.8 с", "cd": 8.0},
	"shield": {"name": "Пуховый щит", "desc": "поглощает 2 попадания за 5 с", "cd": 12.0},
	"scream": {"name": "Громкое «Кур-р!»", "desc": "звуковая волна сбивает дроны и пули вокруг", "cd": 14.0},
	"feathers": {"name": "Веер перьев", "desc": "5 острых перьев летят вперёд веером", "cd": 9.0},
	"mend": {"name": "Сытный клюв", "desc": "восстанавливает 1 HP прямо в полёте", "cd": 20.0},
}

const QUIPS := [
	"Курлык! Дроны? Пусть попробуют.",
	"Я на маршруте. Не задерживайте.",
	"Если что — клюну первым.",
	"Скажите дронам, что я не люблю шум.",
	"Письмо доставлю, а потом — зерно.",
]

# Реликвии (рогалик-часть): после каждого дня выбираешь 1 из 3.
const RELICS := [
	{"id": "iron", "name": "Железные перья", "desc": "+1 макс. здоровья всем голубям"},
	{"id": "wide", "name": "Широкий взмах", "desc": "Радиус ударов и волн +25%"},
	{"id": "jet", "name": "Реактивный хвост", "desc": "Скорость полёта +15%"},
	{"id": "bag", "name": "Сумка пошире", "desc": "Грузоподъёмность +1"},
	{"id": "tips", "name": "Чаевые", "desc": "Награда за доставку +20%"},
]

# Сюжет: по одной сцене на день.
const STORY := {
	1: {"title": "Наследство", "text": "Старый почтмейстер Фёдор Иваныч оставил тебе голубятню «Сизый Крыл» и пачку долгов. Корпорация «ДронЭкс» уже обещает заменить всю почту дронами. Докажи, что голуби городу ещё нужны."},
	2: {"title": "Первые перехваты", "text": "Клиенты жалуются: часть писем пропадает по дороге. На лапке вернувшегося голубя — царапина от винта. Похоже, дроны «ДронЭкс» охотятся именно на твоих птиц."},
	3: {"title": "Стрелки", "text": "В небе появились дроны с орудиями. Ворчит самый старый голубь: в его молодости ограничивались хулиганским свистом. «ДронЭкс» явно перешла от конкуренции к войне."},
	4: {"title": "Предложение", "text": "К голубятне подъехал чёрный фургон. Вежливый менеджер предлагает выкупить «Сизый Крыл» за смешные деньги. Ты отказываешься, а голуби демонстративно роняют перья на его ботинки."},
	5: {"title": "Письмо без адреса", "text": "Пришло письмо без обратного адреса: бывший инженер «ДронЭкс» обещает доказать, что дроны специально сбивают почтовых голубей. Скоро он выйдет на связь."},
	6: {"title": "Вышка на заставе", "text": "Инженер на связи: всеми налётами управляет диспетчерская вышка на Горной заставе. Доказательства он отправит с твоим голубем, а тебе остаётся донести письмо до мэра."},
	7: {"title": "Письмо мэру", "text": "Сегодня главный рейс: письмо с доказательствами для мэра. «ДронЭкс» бросит на него всё, что есть. Береги голубя — от него зависит судьба всей голубиной почты."},
}

const ENDING_WIN := "Мэр прочитал письмо и лишил «ДронЭкс» городской лицензии на доставку. Голубятня «Сизый Крыл» переживает вторую молодость: заказов не счесть, а Фёдор Иваныч шлёт открытки с рыбалки."
const ENDING_PARTIAL := "Неделя позади, голубятня выстояла, но письмо мэру так и не дошло. «ДронЭкс» затаилась и ждёт следующего сезона. Попробуйте ещё раз!"
const ENDING_LOSE := "Голуби кончились, а вместе с ними и надежда спасти голубятню. «ДронЭкс» празднует. Но это ещё не конец — можно начать заново."

var gold := 0
var day := 1
var pigeons: Array = []        # [{name, ability, max_hp, hp, capacity, alive}]
var orders: Array = []         # [{type, place, dist, weight, reward, feed, story?}]
var relics: Array = []         # id взятых реликвий
var relic_choices: Array = []  # 3 варианта на выбор (пусто — выбирать нечего)

var reward_mult := 1.0
var slap_mult := 1.0
var speed_mult := 1.0

var flight_queue: Array = []   # [{order: Dictionary, pigeon: int}]
var flight_index := 0
var flown := {}                # какие голуби летали сегодня
var results: Array = []        # строки-итоги прошлого дня

var game_over := false
var run_won := false
var story_delivered := false


func new_run() -> void:
	gold = 60
	day = 1
	relics = []
	relic_choices = []
	reward_mult = 1.0
	slap_mult = 1.0
	speed_mult = 1.0
	results = []
	flight_queue = []
	flight_index = 0
	flown = {}
	game_over = false
	run_won = false
	story_delivered = false
	var abil: Array = ABILITIES.keys()
	abil.shuffle()
	pigeons = []
	pigeons.append(make_pigeon(_free_name(), abil[0]))
	pigeons.append(make_pigeon(_free_name(), abil[1]))
	generate_orders()


func _free_name() -> String:
	var pool: Array = []
	for n in NAMES:
		var used := false
		for p in pigeons:
			if p["name"] == n:
				used = true
		if not used:
			pool.append(n)
	if pool.is_empty():
		return str(NAMES[randi() % NAMES.size()]) + " II"
	return str(pool[randi() % pool.size()])


func make_pigeon(pigeon_name: String, ability_id: String) -> Dictionary:
	return {"name": pigeon_name, "ability": ability_id, "max_hp": 3, "hp": 3, "capacity": 2.0, "alive": true}


func generate_orders() -> void:
	orders = []
	var count := 3 + int(day / 3.0)
	for i in count:
		var parcel := randf() < 0.5
		var place_idx := randi() % PLACES.size()
		var dist := snappedf(1.0 + place_idx * 0.9 + randf() * 0.5, 0.1)
		var weight := 0.2
		if parcel:
			weight = snappedf(randf_range(0.8, 3.0), 0.1)
		orders.append({
			"type": "Посылка" if parcel else "Письмо",
			"place": PLACES[place_idx],
			"dist": dist,
			"weight": weight,
			"reward": int(dist * 9.0 + weight * 8.0),
			"feed": int(ceil(dist * 1.5)),
		})
	if day == DAYS_PER_RUN:
		orders.append({
			"type": "Письмо",
			"place": "Мэрия (доказательства)",
			"dist": 5.0,
			"weight": 0.2,
			"reward": 150,
			"feed": 8,
			"story": true,
		})


# ---------- Расчёты (их показывает меню) ----------

func payout(order: Dictionary) -> int:
	return int(order["reward"] * reward_mult)


func flight_length(order: Dictionary) -> float:
	return order["dist"] * PX_PER_KM


func flight_speed(order: Dictionary, _pigeon: Dictionary) -> float:
	# Тяжёлый груз замедляет голубя.
	return BASE_SPEED * speed_mult * (1.0 - 0.06 * order["weight"])


func flight_time(order: Dictionary, pigeon: Dictionary) -> float:
	return flight_length(order) / flight_speed(order, pigeon)


func spawn_interval(order: Dictionary) -> float:
	return maxf(0.7, 2.2 - day * 0.09 - order["dist"] * 0.04)


func expected_drones(order: Dictionary, pigeon: Dictionary) -> int:
	return int(flight_time(order, pigeon) / spawn_interval(order))


# ---------- Ход дня ----------

func start_flights(assign: Dictionary) -> void:
	flight_queue = []
	flight_index = 0
	flown = {}
	results = []
	for order_idx in assign.keys():
		var order: Dictionary = orders[order_idx]
		gold -= order["feed"]
		flight_queue.append({"order": order, "pigeon": assign[order_idx]})
		flown[assign[order_idx]] = true


func current_flight() -> Dictionary:
	return flight_queue[flight_index]


func report_flight(delivered: bool, hp_left: int) -> void:
	var flight: Dictionary = flight_queue[flight_index]
	var pigeon: Dictionary = pigeons[flight["pigeon"]]
	var order: Dictionary = flight["order"]
	pigeon["hp"] = maxi(hp_left, 0)
	if pigeon["hp"] <= 0:
		pigeon["alive"] = false
	if delivered:
		var pay := payout(order)
		gold += pay
		if order.get("story", false):
			story_delivered = true
		results.append("%s доставил(а): %s → %s, +%d" % [pigeon["name"], order["type"], order["place"], pay])
	else:
		results.append("%s не долетел(а): %s → %s" % [pigeon["name"], order["type"], order["place"]])
	flight_index += 1


func after_flight(tree: SceneTree) -> void:
	if flight_index < flight_queue.size():
		tree.change_scene_to_file(FLIGHT_SCENE)
	else:
		end_day()
		tree.change_scene_to_file(MANAGEMENT_SCENE)


func end_day() -> void:
	# Голуби, которые сегодня отдыхали, восстанавливают 1 HP.
	for i in pigeons.size():
		var p: Dictionary = pigeons[i]
		if p["alive"] and not flown.has(i):
			p["hp"] = mini(p["max_hp"], p["hp"] + 1)
	day += 1
	var any_alive := false
	for p in pigeons:
		if p["alive"]:
			any_alive = true
	if not any_alive and gold < HIRE_COST:
		game_over = true
		return
	if day > DAYS_PER_RUN:
		run_won = true
		return
	generate_orders()
	relic_choices = _roll_relics()


func ending_text() -> String:
	if game_over:
		return ENDING_LOSE
	if story_delivered:
		return ENDING_WIN
	return ENDING_PARTIAL


func _roll_relics() -> Array:
	var pool := RELICS.duplicate()
	pool.shuffle()
	return pool.slice(0, 3)


func take_relic(id: String) -> void:
	match id:
		"iron":
			for p in pigeons:
				p["max_hp"] += 1
				p["hp"] += 1
		"wide":
			slap_mult *= 1.25
		"jet":
			speed_mult *= 1.15
		"bag":
			for p in pigeons:
				p["capacity"] += 1.0
		"tips":
			reward_mult += 0.2
	relics.append(id)
	relic_choices = []


# ---------- Магазин ----------

func heal_all() -> bool:
	if gold < HEAL_COST:
		return false
	gold -= HEAL_COST
	for p in pigeons:
		if p["alive"]:
			p["hp"] = mini(p["max_hp"], p["hp"] + 1)
	return true


func hire_pigeon() -> bool:
	if gold < HIRE_COST or pigeons.size() >= MAX_PIGEONS:
		return false
	gold -= HIRE_COST
	var abil: Array = ABILITIES.keys()
	var p := make_pigeon(_free_name(), abil[randi() % abil.size()])
	# Новичок получает уже взятые бонусы.
	for id in relics:
		if id == "iron":
			p["max_hp"] += 1
			p["hp"] += 1
		elif id == "bag":
			p["capacity"] += 1.0
	pigeons.append(p)
	return true
