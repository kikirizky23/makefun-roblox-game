-- GameState: the single source of truth for the whole run
-- No other file holds game state; the client only renders snapshots
-- DataStore is optional: load and save are wrapped in pcall

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Spawner = require(script.Parent.Spawner)
local GameState = {}
local T, L = Config.Tuning, Config.Layout
local state = { phase = "MENU", score = 0, wave = 0, hearts = Config.StartHearts,
	timeElapsed = 0, bestScore = 0, clock = 0, spawnTimer = 0, orbTimer = 0,
	waveClearTimer = 0, banner = nil, bannerUntil = 0,
	player = { x = T.PlayerSpawnX, y = T.PlayerSpawnY, mx = 0, my = 0,
		invulnUntil = 0, dashUntil = 0, dashReadyAt = 0, lastShotAt = 0 },
	enemies = {}, bolts = {}, orbs = {}, spawnQueue = {}, events = {} }
local nextBoltId, nextOrbId, store = 0, 0, nil
local function clamp(v, low, high) return v < low and low or (v > high and high or v) end; local function dist(x1, y1, x2, y2) local dx, dy = x1 - x2, y1 - y2; return math.sqrt(dx * dx + dy * dy) end
local function pushEvent(kind, x, y, text) table.insert(state.events, { type = kind, x = x, y = y, text = text }) end
function GameState.showWaveBanner(title, sub, seconds)
	state.banner = { title = title, sub = sub }; state.bannerUntil = state.clock + seconds
end
function GameState.getPhase() return state.phase end
function GameState.loadBestScore()
	local ok, result = pcall(function()
		if store == nil then store = DataStoreService:GetDataStore(Config.DataStoreName) end
		return store:GetAsync(Config.DataStoreKey) end)
	if ok and typeof(result) == "number" then state.bestScore = result end
end
function GameState.saveBestScore()
	if state.score <= state.bestScore then return end
	state.bestScore = state.score
	pcall(function()
		if store == nil then store = DataStoreService:GetDataStore(Config.DataStoreName) end
		store:SetAsync(Config.DataStoreKey, state.bestScore) end)
end
function GameState.resetToMenu()
	state.phase, state.score, state.wave = "MENU", 0, 0
	state.hearts, state.timeElapsed, state.banner = Config.StartHearts, 0, nil
	state.enemies, state.bolts, state.orbs, state.spawnQueue, state.events = {}, {}, {}, {}, {}
	local p = state.player
	p.x, p.y, p.mx, p.my = T.PlayerSpawnX, T.PlayerSpawnY, 0, 0
	p.invulnUntil, p.dashUntil, p.dashReadyAt, p.lastShotAt = 0, 0, 0, 0
	state.spawnTimer, state.orbTimer, state.waveClearTimer = 0, 0, 0
end
function GameState.startRun()
	state.phase, state.score, state.wave = "PLAYING", 0, 0
	state.hearts, state.timeElapsed, state.banner = Config.StartHearts, 0, nil
	state.enemies, state.bolts, state.orbs, state.spawnQueue, state.events = {}, {}, {}, {}, {}
	local p = state.player
	p.x, p.y, p.mx, p.my = T.PlayerSpawnX, T.PlayerSpawnY, 0, 0
	p.invulnUntil, p.dashUntil, p.dashReadyAt, p.lastShotAt = 0, 0, 0, 0
	GameState.startWave(1)
end
function GameState.startWave(wave)
	state.wave, state.phase, state.spawnTimer, state.orbTimer = wave, "PLAYING", 0, 0
	GameState.spawnWave(wave)
	GameState.showWaveBanner("WAVE " .. wave, "Clear them all", T.NextWaveBannerSeconds)
end
function GameState.spawnWave(wave) state.spawnQueue = Spawner.buildWave(wave) end
function GameState.setMove(mx, my)
	local len = math.sqrt(mx * mx + my * my)
	if len > 1 then mx, my = mx / len, my / len end
	state.player.mx, state.player.my = mx, my
end
function GameState.shootBolt(tx, ty)
	local now = state.clock
	if state.phase ~= "PLAYING" or now - state.player.lastShotAt < T.FireCooldown then return end
	state.player.lastShotAt = now
	tx, ty = clamp(tx, 0, L.ArenaWidth), clamp(ty, 0, L.ArenaHeight)
	local dx, dy = tx - state.player.x, ty - state.player.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then dx, dy, len = 1, 0, 1 end
	nextBoltId += 1
	table.insert(state.bolts, { id = nextBoltId, x = state.player.x, y = state.player.y, dx = dx / len, dy = dy / len, bornAt = now })
end
function GameState.tryDash()
	local now = state.clock
	if state.phase ~= "PLAYING" or now < state.player.dashReadyAt then return end
	state.player.dashUntil, state.player.dashReadyAt = now + T.DashSeconds, now + T.DashCooldown
	if state.player.invulnUntil < state.player.dashUntil then state.player.invulnUntil = state.player.dashUntil end
end
function GameState.updatePlayer(dt, now)
	local p = state.player
	local speed = now < p.dashUntil and T.PlayerSpeed * T.DashMultiplier or T.PlayerSpeed
	local len = math.sqrt(p.mx * p.mx + p.my * p.my)
	if len > 0 then p.x += (p.mx / len) * speed * dt; p.y += (p.my / len) * speed * dt end
	p.x = clamp(p.x, T.PlayerMinX, T.PlayerMaxX); p.y = clamp(p.y, T.PlayerMinY, T.PlayerMaxY)
end
function GameState.updateEnemies(dt, now)
	local p = state.player
	for _, e in ipairs(state.enemies) do
		if e.kind == "Chaser" then
			local len = dist(p.x, p.y, e.x, e.y)
			if len > 0 then e.vx, e.vy = (p.x - e.x) / len * e.speed, (p.y - e.y) / len * e.speed end
		end
		e.x += e.vx * dt; e.y += e.vy * dt
		if e.x < e.size / 2 or e.x > L.ArenaWidth - e.size / 2 then e.vx = -e.vx; e.x = clamp(e.x, e.size / 2, L.ArenaWidth - e.size / 2) end
		if e.y < e.size / 2 or e.y > L.ArenaHeight - e.size / 2 then e.vy = -e.vy; e.y = clamp(e.y, e.size / 2, L.ArenaHeight - e.size / 2) end
	end
end
function GameState.updateBolts(dt, now)
	for i = #state.bolts, 1, -1 do
		local b = state.bolts[i]
		b.x += b.dx * T.BoltSpeed * dt; b.y += b.dy * T.BoltSpeed * dt
		if now - b.bornAt > T.BoltLifetime or b.x < 0 or b.x > L.ArenaWidth or b.y < 0 or b.y > L.ArenaHeight then table.remove(state.bolts, i) end
	end
end
function GameState.updateOrbs(dt, now)
	state.orbTimer += dt
	if state.orbTimer >= T.OrbSpawnSeconds and #state.orbs < T.OrbMaxOnField then
		state.orbTimer, nextOrbId = 0, nextOrbId + 1
		local x, y = Spawner.pickOrbPoint(state.player.x, state.player.y)
		table.insert(state.orbs, { id = nextOrbId, x = x, y = y, bornAt = now })
	end
	for i = #state.orbs, 1, -1 do if now - state.orbs[i].bornAt > T.OrbLifetime then table.remove(state.orbs, i) end end
end
function GameState.checkBoltHits()
	for i = #state.bolts, 1, -1 do
		local b = state.bolts[i]
		for j = #state.enemies, 1, -1 do
			local e = state.enemies[j]
			if dist(b.x, b.y, e.x, e.y) < (T.BoltSizeX + e.size) / 2 then table.remove(state.bolts, i); GameState.killEnemy(j); return end
		end
	end
end
function GameState.checkPlayerHits(now)
	if now < state.player.invulnUntil then return end
	local p = state.player
	for _, e in ipairs(state.enemies) do if dist(p.x, p.y, e.x, e.y) < (T.PlayerSize + e.size) / 2 then GameState.damagePlayer(); return end end
end
function GameState.checkOrbPickups(now)
	local p = state.player
	for i = #state.orbs, 1, -1 do
		local orb = state.orbs[i]
		if dist(p.x, p.y, orb.x, orb.y) < T.OrbPickupRadius then table.remove(state.orbs, i); GameState.awardOrb(orb) end
	end
end
function GameState.damagePlayer()
	local now = state.clock
	if now < state.player.invulnUntil then return end
	state.hearts -= 1; state.player.invulnUntil = now + T.InvulnSeconds
	pushEvent("damage", state.player.x, state.player.y, "-1")
	if state.hearts <= 0 then GameState.endRun(false) end
end
function GameState.killEnemy(index)
	local e = state.enemies[index]
	if e == nil then return end
	local score, text = T.ChaserScore, "+" .. tostring(T.ChaserScore)
	if e.kind == "Drifter" then score, text = T.DrifterScore, "+" .. tostring(T.DrifterScore) end
	state.score += score; pushEvent("kill", e.x, e.y, text); table.remove(state.enemies, index)
	if #state.enemies == 0 and #state.spawnQueue == 0 and state.phase == "PLAYING" then GameState.clearWave() end
end
function GameState.awardOrb(orb)
	state.score += T.OrbScore
	local text = "+" .. tostring(T.OrbScore)
	if state.hearts < Config.MaxHearts and math.random() < T.OrbHealChance then state.hearts += 1; text = "+" .. tostring(T.OrbScore) .. " ♥" end
	pushEvent("pickup", orb.x, orb.y, text)
end
function GameState.awardWaveBonus()
	local bonus = Config.Waves[state.wave].Bonus
	state.score += bonus; return bonus
end
function GameState.clearWave()
	local bonus = GameState.awardWaveBonus()
	state.phase, state.waveClearTimer = "WAVE_CLEAR", T.WaveClearBannerSeconds
	GameState.showWaveBanner("WAVE " .. state.wave .. " CLEARED", "+" .. bonus .. " BONUS", T.WaveClearBannerSeconds)
end
function GameState.endRun(won)
	state.phase = won and "WIN" or "LOSE"
	state.banner, state.enemies, state.bolts = nil, {}, {}
	task.spawn(GameState.saveBestScore)
end
function GameState.stepGame(dt)
	state.clock += dt
	if state.banner ~= nil and state.clock >= state.bannerUntil then state.banner = nil end
	if state.phase == "WAVE_CLEAR" then
		state.waveClearTimer -= dt
		if state.waveClearTimer <= 0 then if state.wave >= Config.TotalWaves then GameState.endRun(true) else GameState.startWave(state.wave + 1) end end
		return
	end
	if state.phase ~= "PLAYING" then return end
	state.timeElapsed += dt
	local now = state.clock
	if #state.spawnQueue > 0 then
		state.spawnTimer += dt
		if state.spawnTimer >= T.SpawnInterval then
			state.spawnTimer = 0
			local enemy = Spawner.spawnNext(state.spawnQueue, state.wave, state.player.x, state.player.y, now)
			if enemy ~= nil then table.insert(state.enemies, enemy) end
		end
	end
	GameState.updatePlayer(dt, now); GameState.updateEnemies(dt, now); GameState.updateBolts(dt, now)
	GameState.updateOrbs(dt, now); GameState.checkBoltHits(); GameState.checkPlayerHits(now); GameState.checkOrbPickups(now)
end
function GameState.getSnapshot()
	local p = state.player
	local snap = { phase = state.phase, score = state.score, wave = state.wave, hearts = state.hearts,
		time = state.timeElapsed, best = state.bestScore, dashReady = state.clock >= p.dashReadyAt,
		player = { x = p.x, y = p.y, invuln = state.clock < p.invulnUntil },
		enemies = {}, bolts = {}, orbs = {}, banner = state.banner, events = state.events }
	for _, e in ipairs(state.enemies) do table.insert(snap.enemies, { id = e.id, kind = e.kind, x = e.x, y = e.y }) end
	for _, b in ipairs(state.bolts) do table.insert(snap.bolts, { id = b.id, x = b.x, y = b.y, angle = math.atan2(b.dy, b.dx) }) end
	for _, o in ipairs(state.orbs) do table.insert(snap.orbs, { id = o.id, x = o.x, y = o.y }) end
	state.events = {}
	return snap
end
return GameState
