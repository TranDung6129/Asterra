extends Node2D

const TEAM_COLORS := [Color("#66d9ff"), Color("#ff7b9c")]
const TEAM_DARK := [Color("#102b4a"), Color("#43182b")]
const HEROES := [
	{"id": "bront", "name": "Bront", "role": "ANCHOR", "mass": 1.25, "color": Color("#e5a553"), "skill": "FORTRESS", "description": "Gain 28 shield before launch."},
	{"id": "niva", "name": "Niva", "role": "CONTROL", "mass": 0.90, "color": Color("#91dcff"), "skill": "FROST MARK", "description": "Strong hits leave a slowing frost field."},
	{"id": "kitsu", "name": "Kitsu", "role": "TRICKSHOT", "mass": 0.80, "color": Color("#ff9c6b"), "skill": "AFTERIMAGE", "description": "Keeps more speed after bouncing off walls."},
	{"id": "momo", "name": "Momo", "role": "SUPPORT", "mass": 1.00, "color": Color("#a7ed89"), "skill": "BLOOM PULSE", "description": "Heal nearby allies for 14 HP."},
	{"id": "vex", "name": "Vex", "role": "COMBO", "mass": 1.00, "color": Color("#c99bff"), "skill": "RESONANCE", "description": "At 2 combo charges, pulse nearby enemies."}
]
const PICKUP_COLORS := {"Heart": Color("#ff6d91"), "Shield": Color("#6bc8ff"), "Dash": Color("#ffd66c"), "Core": Color("#bd8aff"), "Chaos": Color("#70f2cf")}

var arena := Rect2(150, 120, 980, 500)
var fighters: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var frost_fields: Array[Dictionary] = []
var hit_cooldowns := {}
var pad_cooldowns := {}
var active_team := 0
var selected := -1
var phase := "title" # title, select, aim, simulation, ended
var dragging := false
var drag_point := Vector2.ZERO
var simulation_time := 0.0
var quiet_time := 0.0
var turn_number := 1
var total_turns := 0
var winner := -1
var event_text := ""
var event_timer := 0.0
var rng := RandomNumberGenerator.new()
var pads: Array[Vector2] = []

func _ready() -> void:
	rng.seed = 8142026
	queue_redraw()

func _process(delta: float) -> void:
	_update_arena()
	if phase == "simulation":
		_simulate(delta)
	if event_timer > 0.0:
		event_timer -= delta
	queue_redraw()

func _update_arena() -> void:
	var size := get_viewport_rect().size
	arena = Rect2(150.0, 112.0, maxf(640.0, size.x - 300.0), maxf(390.0, size.y - 205.0))
	pads = [arena.position + Vector2(arena.size.x * 0.31, arena.size.y * 0.33), arena.position + Vector2(arena.size.x * 0.69, arena.size.y * 0.67)]

func new_match() -> void:
	fighters.clear()
	pickups.clear()
	frost_fields.clear()
	hit_cooldowns.clear()
	pad_cooldowns.clear()
	active_team = 0
	selected = -1
	turn_number = 1
	total_turns = 0
	winner = -1
	for team in 2:
		for h in HEROES.size():
			var line_y := arena.position.y + 78.0 + h * (arena.size.y - 156.0) / 4.0
			var line_x := arena.position.x + (88.0 if team == 0 else arena.size.x - 88.0)
			fighters.append({
				"hero": h, "team": team, "pos": Vector2(line_x, line_y), "vel": Vector2.ZERO,
				"hp": 100.0, "shield": 0.0, "alive": true, "item": "", "core": false,
				"fortress": false, "resonance": 0, "skill_used": false, "pad_lock": 0.0
			})
	_spawn_pickup("Heart", arena.get_center() + Vector2(-115, 0))
	_spawn_pickup("Shield", arena.get_center() + Vector2(115, 0))
	phase = "select"
	_notice("BLUE TEAM — choose a fighter")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		new_match()
		return
	if event.is_action_pressed("skill"):
		_activate_skill()
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var mouse := get_viewport().get_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if phase == "title":
				new_match()
			elif phase == "select":
				_select_fighter_at(mouse)
			elif phase == "aim" and selected >= 0:
				dragging = true
				drag_point = mouse
		else:
			if phase == "aim" and dragging:
				dragging = false
				_launch(mouse)
	elif event is InputEventMouseMotion and phase == "aim" and dragging:
		drag_point = mouse

func _select_fighter_at(mouse: Vector2) -> void:
	for i in fighters.size():
		var f := fighters[i]
		if f.alive and f.team == active_team and mouse.distance_to(f.pos) < 34.0:
			selected = i
			phase = "aim"
			_notice("Pull back from %s, then release" % HEROES[f.hero].name)
			return

func _launch(mouse: Vector2) -> void:
	var f := fighters[selected]
	var pull: Vector2 = f.pos - mouse
	if pull.length() < 12.0:
		_notice("Pull farther to launch")
		return
	pull = pull.limit_length(175.0)
	var speed: float = pull.length() * 4.45
	if f.item == "Dash":
		speed *= 1.18
		f.item = ""
		_notice("DASH TOKEN — launch boosted")
	if f.core:
		speed *= 1.10
		f.core = false
	f.vel = pull.normalized() * speed
	fighters[selected] = f
	phase = "simulation"
	simulation_time = 0.0
	quiet_time = 0.0
	_notice("%s launched!" % HEROES[f.hero].name)

func _activate_skill() -> void:
	if phase != "aim" or selected < 0:
		return
	var f := fighters[selected]
	var hero: Dictionary = HEROES[f.hero]
	if f.skill_used:
		_notice("Skill already used this turn")
		return
	match hero.id:
		"bront":
			f.shield = minf(45.0, f.shield + 28.0)
			f.fortress = true
			f.skill_used = true
			_notice("FORTRESS — 28 shield")
		"momo":
			var healed := 0
			for i in fighters.size():
				var ally := fighters[i]
				if ally.alive and ally.team == f.team and ally.pos.distance_to(f.pos) < 175.0:
					ally.hp = minf(100.0, ally.hp + 14.0)
					fighters[i] = ally
					healed += 1
			f.skill_used = true
			_notice("BLOOM PULSE — healed %d ally%s" % [healed, "" if healed == 1 else " allies"])
		"vex":
			if int(f.resonance) < 2:
				_notice("Need 2 resonance charges")
				return
			for i in fighters.size():
				var target := fighters[i]
				if target.alive and target.team != f.team and target.pos.distance_to(f.pos) < 150.0:
					target.vel += (target.pos - f.pos).normalized() * 410.0
					fighters[i] = target
			f.resonance = 0
			f.skill_used = true
			_notice("RESONANCE BURST!")
		_:
			_notice("%s is a passive skill" % hero.skill)
			return
	fighters[selected] = f

func _simulate(delta: float) -> void:
	simulation_time += delta
	for key in hit_cooldowns.keys():
		hit_cooldowns[key] = float(hit_cooldowns[key]) - delta
		if hit_cooldowns[key] <= 0.0: hit_cooldowns.erase(key)
	for key in pad_cooldowns.keys():
		pad_cooldowns[key] = float(pad_cooldowns[key]) - delta
		if pad_cooldowns[key] <= 0.0: pad_cooldowns.erase(key)
	for field in frost_fields:
		field.ttl -= delta
	frost_fields = frost_fields.filter(func(field): return field.ttl > 0.0)
	for i in fighters.size():
		var f := fighters[i]
		if not f.alive: continue
		var damping := 0.72
		for field in frost_fields:
			if f.pos.distance_to(field.pos) < 74.0: damping = 2.15
		f.vel = f.vel.move_toward(Vector2.ZERO, damping * 100.0 * delta)
		f.pos += f.vel * delta
		_bounce_walls(f)
		_check_pad(i, f)
		fighters[i] = f
	for a in fighters.size():
		for b in range(a + 1, fighters.size()):
			_resolve_fighter_collision(a, b)
	_check_pickups()
	var moving := false
	for f in fighters:
		if f.alive and f.vel.length() > 13.0: moving = true
	if not moving: quiet_time += delta
	else: quiet_time = 0.0
	if quiet_time > 0.65 or simulation_time > 10.0:
		_end_turn()

func _bounce_walls(f: Dictionary) -> void:
	var radius := 23.0
	var restitution := 0.72 if HEROES[f.hero].id != "kitsu" else 0.87
	if f.pos.x < arena.position.x + radius:
		f.pos.x = arena.position.x + radius; f.vel.x = absf(f.vel.x) * restitution
	elif f.pos.x > arena.end.x - radius:
		f.pos.x = arena.end.x - radius; f.vel.x = -absf(f.vel.x) * restitution
	if f.pos.y < arena.position.y + radius:
		f.pos.y = arena.position.y + radius; f.vel.y = absf(f.vel.y) * restitution
	elif f.pos.y > arena.end.y - radius:
		f.pos.y = arena.end.y - radius; f.vel.y = -absf(f.vel.y) * restitution

func _check_pad(index: int, f: Dictionary) -> void:
	for pad in pads:
		if f.pos.distance_to(pad) < 40.0 and not pad_cooldowns.has(index):
			f.vel *= 1.30
			pad_cooldowns[index] = 0.45
			_notice("BOUNCE PAD!")

func _resolve_fighter_collision(a: int, b: int) -> void:
	var first := fighters[a]
	var second := fighters[b]
	if not first.alive or not second.alive: return
	var offset: Vector2 = second.pos - first.pos
	var distance := maxf(0.01, offset.length())
	var minimum := 46.0
	if distance >= minimum: return
	var normal := offset / distance
	var overlap := minimum - distance
	var total_mass := float(first.mass) + float(second.mass)
	first.pos -= normal * overlap * (float(second.mass) / total_mass)
	second.pos += normal * overlap * (float(first.mass) / total_mass)
	var relative: Vector2 = second.vel - first.vel
	var along_normal := relative.dot(normal)
	var damaging_impact := false
	var impact := 0.0
	if along_normal < 0.0:
		var restitution := 0.77
		impact = -(1.0 + restitution) * along_normal / (1.0 / float(first.mass) + 1.0 / float(second.mass))
		first.vel -= normal * impact / float(first.mass)
		second.vel += normal * impact / float(second.mass)
		var key := "%d:%d" % [a, b]
		if impact > 135.0 and not hit_cooldowns.has(key):
			hit_cooldowns[key] = 0.30
			damaging_impact = true
	fighters[a] = first
	fighters[b] = second
	if damaging_impact:
		_apply_impact_damage(a, b, impact, (first.pos + second.pos) * 0.5)

func _apply_impact_damage(a: int, b: int, impulse: float, at: Vector2) -> void:
	var damage := clampf((impulse - 125.0) * 0.052, 2.0, 27.0)
	for index in [a, b]:
		var f := fighters[index]
		var absorbed := minf(float(f.shield), damage)
		f.shield -= absorbed
		f.hp -= damage - absorbed
		if f.hp <= 0.0:
			f.hp = 0.0; f.alive = false; f.vel = Vector2.ZERO
			_notice("%s was RIFTED!" % HEROES[f.hero].name)
		fighters[index] = f
	var source := fighters[a]
	if HEROES[source.hero].id == "niva" and impulse > 200.0:
		frost_fields.append({"pos": at, "ttl": 3.0})
	if HEROES[source.hero].id == "vex":
		source.resonance = mini(3, int(source.resonance) + 1)
		fighters[a] = source
	_notice("IMPACT  -%d HP" % roundi(damage))

func _check_pickups() -> void:
	for p in pickups.duplicate():
		for i in fighters.size():
			var f := fighters[i]
			if f.alive and f.pos.distance_to(p.pos) < 31.0:
				_collect_pickup(i, p)
				pickups.erase(p)
				break

func _collect_pickup(index: int, pickup: Dictionary) -> void:
	var f := fighters[index]
	match pickup.type:
		"Heart": f.hp = minf(100.0, f.hp + 14.0)
		"Shield": f.shield = minf(45.0, f.shield + 18.0)
		"Dash": f.item = "Dash"
		"Core": f.core = true
		"Chaos":
			var options := ["Heart", "Shield", "Dash", "Core"]
			var effect: String = options[rng.randi_range(0, options.size() - 1)]
			pickup.type = effect
			fighters[index] = f
			_collect_pickup(index, pickup)
			return
	fighters[index] = f
	_notice("%s picked up %s" % [HEROES[f.hero].name, pickup.type])

func _end_turn() -> void:
	for i in fighters.size():
		var f := fighters[i]
		f.vel = Vector2.ZERO
		f.skill_used = false
		fighters[i] = f
	var blue_alive := fighters.any(func(f): return f.alive and f.team == 0)
	var pink_alive := fighters.any(func(f): return f.alive and f.team == 1)
	if not blue_alive or not pink_alive:
		winner = 0 if blue_alive else 1
		phase = "ended"
		_notice("%s TEAM WINS THE RIFT" % ("BLUE" if winner == 0 else "PINK"))
		return
	total_turns += 1
	if total_turns % 2 == 0 and pickups.size() < 2:
		var types := ["Heart", "Shield", "Dash", "Core", "Chaos"]
		_spawn_pickup(types[rng.randi_range(0, types.size() - 1)], _free_pickup_position())
	active_team = 1 - active_team
	turn_number += 1 if active_team == 0 else 0
	selected = -1
	phase = "select"
	_notice("%s TEAM — choose a fighter" % ("BLUE" if active_team == 0 else "PINK"))

func _spawn_pickup(type: String, pos: Vector2) -> void:
	pickups.append({"type": type, "pos": pos})

func _free_pickup_position() -> Vector2:
	for _attempt in 12:
		var pos := Vector2(rng.randf_range(arena.position.x + 120.0, arena.end.x - 120.0), rng.randf_range(arena.position.y + 70.0, arena.end.y - 70.0))
		var safe := true
		for f in fighters:
			if f.pos.distance_to(pos) < 100.0: safe = false
			if safe: return pos
	return arena.get_center()

func _notice(message: String) -> void:
	event_text = message
	event_timer = 2.3

func _draw() -> void:
	var screen := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color("#090d1c"))
	# Atmospheric stars and title bar.
	for i in 35:
		var x := fmod(float(i * 173), maxf(1.0, screen.x))
		var y := fmod(float(i * 71), maxf(1.0, screen.y))
		draw_circle(Vector2(x, y), 1.2, Color(0.35, 0.5, 0.8, 0.20))
	var font := ThemeDB.fallback_font
	if phase == "title":
		_draw_title(font, screen)
		return
	_draw_header(font, screen)
	_draw_arena()
	_draw_fighters(font)
	_draw_hud(font, screen)
	if phase == "aim" and selected >= 0:
		_draw_aim()
	if event_timer > 0.0:
		var box := Rect2(screen.x * 0.5 - 205.0, 70.0, 410.0, 32.0)
		draw_style_box(_panel_style(Color("#17223d"), 12.0), box)
		draw_string(font, box.position + Vector2(18, 22), event_text, HORIZONTAL_ALIGNMENT_CENTER, 374, 16, Color("#f4f7ff"))
	if phase == "ended":
		_draw_result(font, screen)

func _draw_title(font: Font, screen: Vector2) -> void:
	var center := screen * 0.5
	draw_circle(center + Vector2(0, -15), 180.0, Color(0.28, 0.18, 0.65, 0.12))
	draw_circle(center + Vector2(0, -15), 120.0, Color(0.28, 0.65, 0.90, 0.09))
	draw_string(font, Vector2(center.x - 175, center.y - 90), "RIFTBOUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color("#edf4ff"))
	draw_string(font, Vector2(center.x - 180, center.y - 54), "TACTICAL PHYSICS ARENA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#8ba6d7"))
	var card := Rect2(center.x - 270, center.y - 20, 540, 180)
	draw_style_box(_panel_style(Color("#172340"), 22.0), card)
	draw_string(font, card.position + Vector2(36, 48), "Five heroes. One shot can reshape the match.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#eef5ff"))
	draw_string(font, card.position + Vector2(36, 78), "Local hot-seat  •  Drag back to aim  •  Space for skills", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#a9bddf"))
	var start := Rect2(center.x - 145, center.y + 104, 290, 44)
	draw_style_box(_panel_style(Color("#2769bc"), 14.0), start)
	draw_string(font, start.position + Vector2(18, 29), "CLICK ANYWHERE TO START", HORIZONTAL_ALIGNMENT_CENTER, 254, 16, Color.WHITE)

func _draw_header(font: Font, screen: Vector2) -> void:
	draw_string(font, Vector2(30, 42), "RIFTBOUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#eff5ff"))
	draw_string(font, Vector2(30, 63), "LOCAL ARENA PROTOTYPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8094be"))
	var team_text := "%s TEAM TURN" % ("BLUE" if active_team == 0 else "PINK")
	draw_string(font, Vector2(screen.x * 0.5 - 105, 43), team_text, HORIZONTAL_ALIGNMENT_CENTER, 210, 20, TEAM_COLORS[active_team])
	draw_string(font, Vector2(screen.x * 0.5 - 80, 64), "ROUND %d  •  R to restart" % turn_number, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color("#9caed0"))

func _draw_arena() -> void:
	draw_style_box(_panel_style(Color("#111d37"), 26.0), arena.grow(10.0))
	draw_rect(arena, Color("#172644"), true)
	for x in range(int(arena.position.x) + 30, int(arena.end.x), 60):
		draw_line(Vector2(x, arena.position.y), Vector2(x, arena.end.y), Color(0.35, 0.55, 0.85, 0.055), 1.0)
	for y in range(int(arena.position.y) + 30, int(arena.end.y), 60):
		draw_line(Vector2(arena.position.x, y), Vector2(arena.end.x, y), Color(0.35, 0.55, 0.85, 0.055), 1.0)
	draw_arc(arena.get_center(), minf(arena.size.x, arena.size.y) * 0.22, 0, TAU, 48, Color(0.43, 0.72, 1.0, 0.12), 2.0)
	for pad in pads:
		draw_circle(pad, 40.0, Color("#4d79db"))
		draw_circle(pad, 33.0, Color("#283f82"))
		draw_arc(pad, 26.0, 0, TAU, 22, Color("#a1cbff"), 2.0)
	for field in frost_fields:
		draw_circle(field.pos, 74.0, Color(0.38, 0.82, 1.0, 0.17))
		draw_arc(field.pos, 74.0, 0, TAU, 24, Color(0.54, 0.9, 1.0, 0.45), 1.2)
	for pickup in pickups:
		var p: Vector2 = pickup.pos
		draw_circle(p, 19.0, PICKUP_COLORS[pickup.type])
		draw_circle(p, 12.0, Color("#f5f8ff"))
		draw_string(ThemeDB.fallback_font, p + Vector2(-10, 5), pickup.type.left(1), HORIZONTAL_ALIGNMENT_CENTER, 20, 14, PICKUP_COLORS[pickup.type].darkened(0.55))

func _draw_fighters(font: Font) -> void:
	for i in fighters.size():
		var f := fighters[i]
		var hero: Dictionary = HEROES[f.hero]
		var p: Vector2 = f.pos
		if not f.alive:
			draw_circle(p, 21.0, Color("#293249"))
			draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), Color("#8490a5"), 3.0)
			draw_line(p + Vector2(9, -9), p + Vector2(-9, 9), Color("#8490a5"), 3.0)
			continue
		if float(f.shield) > 0.0:
			draw_arc(p, 29.0, 0, TAU, 24, Color("#75ddff"), 3.0)
		draw_circle(p + Vector2(2, 4), 24.0, Color(0.0, 0.0, 0.0, 0.22))
		draw_circle(p, 23.0, hero.color)
		draw_circle(p, 17.0, hero.color.lightened(0.20))
		draw_circle(p + Vector2(-6, -4), 3.0, Color("#172039"))
		draw_circle(p + Vector2(6, -4), 3.0, Color("#172039"))
		draw_arc(p + Vector2(0, 3), 7.0, 0.15, PI - 0.15, 12, Color("#172039"), 1.7)
		if i == selected:
			draw_arc(p, 32.0, 0, TAU, 28, TEAM_COLORS[f.team], 2.5)
		var hp_box := Rect2(p.x - 25, p.y - 38, 50, 5)
		draw_rect(hp_box, Color("#0b1020"), true)
		draw_rect(Rect2(hp_box.position, Vector2(50.0 * float(f.hp) / 100.0, 5)), Color("#7fe295"), true)
		draw_string(font, p + Vector2(-24, 45), hero.name, HORIZONTAL_ALIGNMENT_CENTER, 48, 11, Color("#f3f6ff"))
		if f.item != "": draw_string(font, p + Vector2(-7, -50), "◆", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PICKUP_COLORS["Dash"])
		if f.core: draw_string(font, p + Vector2(6, -50), "✦", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PICKUP_COLORS["Core"])

func _draw_hud(font: Font, screen: Vector2) -> void:
	for team in 2:
		var x := 18.0 if team == 0 else screen.x - 132.0
		var panel := Rect2(x, 96.0, 114.0, 228.0)
		draw_style_box(_panel_style(TEAM_DARK[team], 15.0), panel)
		draw_string(font, panel.position + Vector2(12, 22), "%s SQUAD" % ("BLUE" if team == 0 else "PINK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEAM_COLORS[team])
		for h in HEROES.size():
			var f: Dictionary = fighters[team * HEROES.size() + h]
			var row_y := panel.position.y + 48.0 + h * 34.0
			draw_circle(Vector2(panel.position.x + 15, row_y - 4), 7.0, HEROES[h].color if f.alive else Color("#3a4356"))
			draw_string(font, Vector2(panel.position.x + 27, row_y), HEROES[h].name, HORIZONTAL_ALIGNMENT_LEFT, 53, 11, Color("#f0f4ff") if f.alive else Color("#67738b"))
			draw_string(font, Vector2(panel.end.x - 33, row_y), "%d" % roundi(f.hp), HORIZONTAL_ALIGNMENT_RIGHT, 27, 11, Color("#dfe8ff") if f.alive else Color("#67738b"))
	if selected >= 0 and selected < fighters.size() and fighters[selected].alive:
		var f := fighters[selected]
		var hero: Dictionary = HEROES[f.hero]
		var card := Rect2(screen.x * 0.5 - 170.0, screen.y - 76.0, 340.0, 58.0)
		draw_style_box(_panel_style(Color("#1b2948"), 14.0), card)
		draw_string(font, card.position + Vector2(14, 21), "%s  ·  %s" % [hero.name, hero.role], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hero.color)
		draw_string(font, card.position + Vector2(14, 43), "[SPACE] %s — %s" % [hero.skill, hero.description], HORIZONTAL_ALIGNMENT_LEFT, 312, 11, Color("#c0cde6"))
	else:
		draw_string(font, Vector2(screen.x * 0.5 - 180, screen.y - 35), "Choose any living hero, then pull back and release.", HORIZONTAL_ALIGNMENT_CENTER, 360, 13, Color("#b8c8e6"))

func _draw_aim() -> void:
	var f := fighters[selected]
	var pull: Vector2 = (f.pos - drag_point).limit_length(175.0)
	if dragging:
		draw_line(f.pos, drag_point, Color("#ffffff"), 2.0)
		draw_line(f.pos, f.pos + pull.normalized() * minf(125.0, pull.length()), TEAM_COLORS[f.team], 4.0)
		draw_arc(f.pos, 38.0, 0, TAU, 28, Color(TEAM_COLORS[f.team], 0.4), 1.0)
		var power := roundi(pull.length() / 175.0 * 100.0)
		draw_string(ThemeDB.fallback_font, f.pos + Vector2(-28, -62), "%d%%" % power, HORIZONTAL_ALIGNMENT_CENTER, 56, 13, Color.WHITE)

func _draw_result(font: Font, screen: Vector2) -> void:
	var box := Rect2(screen.x * 0.5 - 245.0, screen.y * 0.5 - 92.0, 490.0, 184.0)
	draw_style_box(_panel_style(Color("#172747"), 20.0), box)
	draw_string(font, box.position + Vector2(26, 58), "%s TEAM WINS" % ("BLUE" if winner == 0 else "PINK"), HORIZONTAL_ALIGNMENT_CENTER, 438, 30, TEAM_COLORS[winner])
	draw_string(font, box.position + Vector2(26, 92), "The arena remembers every impact.", HORIZONTAL_ALIGNMENT_CENTER, 438, 15, Color("#c6d3eb"))
	draw_string(font, box.position + Vector2(26, 142), "Press R to start a new match", HORIZONTAL_ALIGNMENT_CENTER, 438, 14, Color("#9eb5dd"))

func _panel_style(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	style.border_color = Color(0.5, 0.68, 1.0, 0.20)
	style.set_border_width_all(1)
	return style
