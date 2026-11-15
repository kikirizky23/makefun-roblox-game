-- GameState: the single source of truth for the whole run
-- No other file holds game state; the client only renders snapshots
-- DataStore is optional: load and save are wrapped in pcall
-- Auto-fire is server-side: there is no client Shoot path
-- Amended mechanics (Codex design pass): boss attack phases, telegraphs
-- (drone dive, weaver trails, gunner charge), danger bonuses (near-miss,
-- kill-after-fire), dash invulnerability, formation spawns, wave-clear
-- freeze + reward power-up, threat-based auto-aim

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Spawner = require(script.Parent.Spawner)

local GameState = {}
local T, L = Config.Tuning, Config.Layout

-- Boss sway: side-to-side sine whose PEAK horizontal speed equals the boss
-- speed (70, or 100 in phase 3). The amplitude (220 px each way from
-- x = 320) is a layout choice, not a brief number: freq = speed / amplitude.
local BOSS_SWAY_AMPLITUDE = 220
-- Gunner strafe: how far it slides left/right of its anchor while hovering.
local GUNNER_STRAFE_AMPLITUDE = 90
local GUNNER_STRAFE_FREQUENCY = 0.8

local state = {
	phase = "MENU",
	runId = 0, -- bumps on every startRun; the client drops stale drag state when it changes
	score = 0,
	killPoints = 0,
	waveBonuses = 0,
	dangerBonus = 0,
	pickupPoints = 0,
	wave = 0,
	hearts = Config.StartHearts,
	timeElapsed = 0,
	bestScore = 0,
	clock = 0,
	spawnTimer = 0,
	waveClearTimer = 0,
	freezeTimer = 0,
	banner = nil,
	bannerUntil = 0,
	player = {
		x = T.PlayerSpawnX,
		y = T.PlayerSpawnY,
		moveX = 0,
		moveY = 0,
		invulnUntil = 0,
		dashUntil = 0,
		dashReadyAt = 0,
		dashInvulnUntil = 0,
		touchTarget = nil :: any,
	},
	enemies = {},
	bolts = {},
	bullets = {},
	powerups = {},
	trails = {},
	boss = nil,
	spawnQueue = {},
	events = {},
	streak = 0,
	lastKillAt = 0,
	modifier = "STANDARD",
	shieldUntil = 0,
	rapidUntil = 0,
	spreadUntil = 0,
	fireTimer = 0,
	targetId = nil,
}

local nextBoltId, nextBulletId, nextPowerupId, nextTrailId, store = 0, 0, 0, 0, nil

local function clamp(v, low, high)
	return v < low and low or (v > high and high or v)
end

local function dist(x1, y1, x2, y2)
	local dx, dy = x1 - x2, y1 - y2
	return math.sqrt(dx * dx + dy * dy)
end

local function pushEvent(kind, x, y, text)
	table.insert(state.events, { type = kind, x = x, y = y, text = text })
end

function GameState.showWaveBanner(title, sub, seconds)
	state.banner = { title = title, sub = sub }
	state.bannerUntil = state.clock + seconds
end

function GameState.getPhase()
	return state.phase
end

function GameState.loadBestScore()
	local ok, result = pcall(function()
		if store == nil then
			store = DataStoreService:GetDataStore(Config.DataStoreName)
		end
		return store:GetAsync(Config.DataStoreKey)
	end)
	if ok and typeof(result) == "number" then
		state.bestScore = math.max(state.bestScore, result)
	end
end

function GameState.saveBestScore()
	-- Capture the score first: this runs task.spawned from endRun, and the
	-- async save below must persist THIS run's score even if a new run
	-- starts (and changes state.score) before the save completes.
	local scoreToSave = state.score
	if scoreToSave <= state.bestScore then
		return
	end
	-- No optimistic assignment here: bestScore is only updated from the
	-- stored result below, so a failed save cannot leave a phantom best
	-- that blocks later retries.
	local ok, newValue = pcall(function()
		if store == nil then
			store = DataStoreService:GetDataStore(Config.DataStoreName)
		end
		return store:UpdateAsync(Config.DataStoreKey, function(old)
			if typeof(old) == "number" then
				return math.max(old, scoreToSave)
			end
			return scoreToSave
		end)
	end)
	if ok and typeof(newValue) == "number" then
		state.bestScore = newValue
	end
end

local function resetRunState()
	state.score, state.wave = 0, 0
	state.killPoints, state.waveBonuses, state.dangerBonus, state.pickupPoints = 0, 0, 0, 0
	state.hearts, state.timeElapsed, state.banner = Config.StartHearts, 0, nil
	state.enemies, state.bolts, state.bullets, state.powerups, state.trails = {}, {}, {}, {}, {}
	state.boss, state.spawnQueue, state.events = nil, {}, {}
	state.streak, state.lastKillAt, state.modifier = 0, 0, "STANDARD"
	state.shieldUntil, state.rapidUntil, state.spreadUntil = 0, 0, 0
	state.fireTimer = 0
	state.targetId = nil
	local p = state.player
	p.x, p.y, p.moveX, p.moveY = T.PlayerSpawnX, T.PlayerSpawnY, 0, 0
	p.touchTarget = nil
	p.invulnUntil, p.dashUntil, p.dashReadyAt, p.dashInvulnUntil = 0, 0, 0, 0
	state.spawnTimer, state.waveClearTimer, state.freezeTimer = 0, 0, 0
end

function GameState.resetToMenu()
	state.phase = "MENU"
	resetRunState()
end

function GameState.startRun()
	state.runId += 1
	state.phase = "PLAYING"
	resetRunState()
	Spawner.resetIds()
	nextBoltId, nextBulletId, nextPowerupId, nextTrailId = 0, 0, 0, 0
	GameState.startWave(1)
end

function GameState.startWave(wave)
	state.wave, state.phase, state.spawnTimer = wave, "PLAYING", 0
	state.modifier = Config.Waves[wave].Modifier
	state.spawnQueue = Spawner.buildWaveQueue(wave)
	if Config.Waves[wave].Boss > 0 then
		state.boss = Spawner.spawnBoss(wave, state.clock)
	end
	local sub = state.modifier ~= "STANDARD" and ("Modifier: " .. state.modifier) or "Clear them all"
	GameState.showWaveBanner("WAVE " .. wave, sub, T.NextWaveBannerSeconds)
end

function GameState.setMove(mx, my)
	local len = math.sqrt(mx * mx + my * my)
	if len > 1 then
		mx, my = mx / len, my / len
	end
	state.player.moveX, state.player.moveY = mx, my
end

-- Touch target mode: the client sends where the ship should go (design
-- coords). Validated here (finite + clamped to the arena); updatePlayer
-- re-clamps to the effective bounds (TIGHT inset) every tick and moves
-- by min(speed * dt, distance), stopping exactly on arrival.
function GameState.setTouchTarget(tx, ty)
	if tx ~= tx or ty ~= ty or tx == math.huge or tx == -math.huge or ty == math.huge or ty == -math.huge then
		return
	end
	-- Entering target mode also zeroes the stored keyboard vector: on
	-- arrival the target is cleared, and a stale vector would otherwise
	-- move the ship on the next tick.
	state.player.moveX, state.player.moveY = 0, 0
	state.player.touchTarget = {
		x = clamp(tx, T.PlayerMinX, T.PlayerMaxX),
		y = clamp(ty, T.PlayerMinY, T.PlayerMaxY),
	}
end

function GameState.clearTouchTarget()
	state.player.touchTarget = nil
end

function GameState.tryDash()
	local now = state.clock
	if state.phase ~= "PLAYING" or now < state.player.dashReadyAt then
		return
	end
	state.player.dashUntil = now + T.DashSeconds
	state.player.dashReadyAt = now + T.DashCooldown
	-- Dash grants brief invulnerability: dashing through bullets and
	-- enemies is the skill move. Damage checks respect dashInvulnUntil
	-- exactly like the hit invulnerability.
	state.player.dashInvulnUntil = now + T.DashInvulnSeconds
	table.insert(state.events, { type = "dash", x = state.player.x, y = state.player.y })
end

-- Boss attack phase from HP: P1 above 75% (31-40), P2 at 50-75% (20-30),
-- P3 below 50% (under 20).
function GameState.bossPhase(hp, maxHp)
	local frac = hp / maxHp
	if frac > 0.75 then
		return 1
	end
	if frac >= 0.5 then
		return 2
	end
	return 3
end

-- Threat-based auto-aim: THREAT TIER first, then nearest. A threatening
-- enemy (firing recently, charging, diving, or the boss) always wins
-- over a passive one, however near the passive one is; within a tier
-- the nearest wins. "Recently fired" counts as firing for 1.5 s after
-- the shot (same window as the kill-after-fire bonus).
local function isThreatening(e, now)
	if e.kind == "Boss" then
		return true
	end
	if e.charging == true or e.diving == true then
		return true
	end
	return e.lastFiredAt ~= nil and now - e.lastFiredAt <= T.DangerKillWindowSeconds
end

local function pickTarget()
	local p = state.player
	local now = state.clock
	local best, bestDist = nil, nil
	local bestThreat, bestThreatDist = nil, nil
	local function consider(e)
		local d = dist(p.x, p.y, e.x, e.y)
		if isThreatening(e, now) then
			if bestThreatDist == nil or d < bestThreatDist then
				bestThreat, bestThreatDist = e, d
			end
		elseif bestDist == nil or d < bestDist then
			best, bestDist = e, d
		end
	end
	for _, e in ipairs(state.enemies) do
		consider(e)
	end
	if state.boss ~= nil then
		consider(state.boss)
	end
	local target = bestThreat or best
	state.targetId = target ~= nil and target.id or nil
	return target
end

local function fireBullets(angle)
	local p = state.player
	local angles = { angle }
	if state.clock < state.spreadUntil then
		local s = math.rad(T.SpreadAngleDegrees)
		angles = { angle - s, angle, angle + s }
	end
	for _, a in ipairs(angles) do
		nextBulletId += 1
		table.insert(state.bullets, {
			id = nextBulletId,
			x = p.x,
			y = p.y,
			dx = math.cos(a),
			dy = math.sin(a),
			bornAt = state.clock,
		})
	end
end

function GameState.updatePlayer(dt, now)
	local p = state.player
	local speed = now < p.dashUntil and T.PlayerSpeed * T.DashMultiplier or T.PlayerSpeed
	local minX, maxX, minY, maxY = T.PlayerMinX, T.PlayerMaxX, T.PlayerMinY, T.PlayerMaxY
	if state.modifier == "TIGHT" then
		local inset = T.TightArenaInset
		minX, maxX, minY, maxY = minX + inset, maxX - inset, minY + inset, maxY - inset
	end
	if p.touchTarget ~= nil then
		-- Touch target mode: move toward the stored target, stopping
		-- exactly on arrival. A unit-vector move would overshoot by up
		-- to a full tick (18 px at 360 px/s, 43 px while dashing) and
		-- oscillate around the target; min(step, distance) cannot.
		local tx = clamp(p.touchTarget.x, minX, maxX)
		local ty = clamp(p.touchTarget.y, minY, maxY)
		local dx, dy = tx - p.x, ty - p.y
		local d = math.sqrt(dx * dx + dy * dy)
		local step = speed * dt
		if d <= step then
			p.x, p.y = tx, ty
			p.touchTarget = nil
		elseif d > 0 then
			p.x += dx / d * step
			p.y += dy / d * step
		end
	else
		local len = math.sqrt(p.moveX * p.moveX + p.moveY * p.moveY)
		if len > 0 then
			p.x += (p.moveX / len) * speed * dt
			p.y += (p.moveY / len) * speed * dt
		end
	end
	p.x = clamp(p.x, minX, maxX)
	p.y = clamp(p.y, minY, maxY)
	-- Auto-fire: aim at the threat-picked target, straight up when nothing
	-- is live. Rapid halves the interval.
	local interval = now < state.rapidUntil and T.RapidFireInterval or T.FireInterval
	state.fireTimer += dt
	if state.fireTimer >= interval then
		state.fireTimer -= interval
		local target = pickTarget()
		local angle = -math.pi / 2
		if target ~= nil then
			angle = math.atan2(target.y - p.y, target.x - p.x)
		end
		fireBullets(angle)
	else
		-- Keep the reticle live even between shots.
		pickTarget()
	end
end

function GameState.updateEnemies(dt, now)
	local p = state.player
	for i = #state.enemies, 1, -1 do
		local e = state.enemies[i]
		if e.kind == "Drone" then
			if e.diveState == "dive" then
				-- Diving: fast straight down its lane, no steering.
				e.y += T.DroneDiveSpeed * dt
				e.x = e.diveX
				if e.y > L.ArenaHeight + e.size then
					table.remove(state.enemies, i)
				end
			elseif e.diveState == "telegraph" then
				-- Telegraph: stopped, flashing (diving flag is on). The
				-- dive starts when the telegraph window ends.
				if now >= e.telegraphUntil then
					e.diveState = "dive"
					e.diveX = e.x
				end
			else
				-- Steer straight at the player; close in and the drone
				-- telegraphs its dive instead of touching.
				local len = dist(p.x, p.y, e.x, e.y)
				if len > 0 then
					e.x += (p.x - e.x) / len * e.speed * dt
					e.y += (p.y - e.y) / len * e.speed * dt
				end
				e.x = clamp(e.x, e.size / 2, L.ArenaWidth - e.size / 2)
				e.y = clamp(e.y, e.size / 2, L.ArenaHeight - e.size / 2)
				if len < T.DroneDiveTriggerDistance then
					e.diveState = "telegraph"
					e.telegraphUntil = now + T.DroneTelegraphSeconds
					e.diving = true
				end
			end
		elseif e.kind == "Weaver" then
			-- Sine-wave descent: falls at speed, sways around its anchor x.
			e.y += e.speed * dt
			e.x = e.baseX + T.WeaverAmplitude * math.sin(T.WeaverFrequency * (now - e.bornAt) + e.swayPhase)
			e.x = clamp(e.x, e.size / 2, L.ArenaWidth - e.size / 2)
			-- Trail: a fading point every 0.15 s; each lives 1.0 s.
			if now - e.lastTrailAt >= T.WeaverTrailInterval then
				e.lastTrailAt = now
				nextTrailId += 1
				table.insert(state.trails, { id = nextTrailId, x = e.x, y = e.y, expiresAt = now + T.WeaverTrailLifetime })
			end
			if e.y > L.ArenaHeight + e.size then
				-- Flew past the bottom edge: gone, no points.
				table.remove(state.enemies, i)
			end
		elseif e.kind == "Gunner" then
			-- Hover near y ~ 90, strafing side to side.
			local targetX = e.baseX + GUNNER_STRAFE_AMPLITUDE * math.sin(GUNNER_STRAFE_FREQUENCY * (now - e.bornAt) + e.swayPhase)
			local targetY = T.GunnerHoverY
			local dx, dy = targetX - e.x, targetY - e.y
			local len = math.sqrt(dx * dx + dy * dy)
			if len > 0 then
				local step = math.min(e.speed * dt, len)
				e.x += dx / len * step
				e.y += dy / len * step
			end
			e.x = clamp(e.x, e.size / 2, L.ArenaWidth - e.size / 2)
			e.y = clamp(e.y, e.size / 2, L.ArenaHeight - e.size / 2)
			if e.charging then
				-- Charge finished: fire the 3-bolt fan, then re-arm.
				if now >= e.chargeUntil then
					e.charging = false
					e.fireAt = now + T.GunnerFireSeconds
					e.lastFiredAt = now
					local aimLen = dist(p.x, p.y, e.x, e.y)
					local baseAngle = math.pi / 2
					if aimLen > 0 then
						baseAngle = math.atan2(p.y - e.y, p.x - e.x)
					end
					for _, offset in ipairs({ -T.FanSpreadHalfAngle, 0, T.FanSpreadHalfAngle }) do
						local a = baseAngle + offset
						nextBoltId += 1
						table.insert(state.bolts, { id = nextBoltId, x = e.x, y = e.y, dx = math.cos(a), dy = math.sin(a), speed = T.EnemyBoltSpeed, bornAt = now })
					end
				end
			elseif now >= e.fireAt then
				-- Telegraph: 0.6 s charging before the fan fires.
				e.charging = true
				e.chargeUntil = now + T.GunnerChargeSeconds
			end
		end
	end
end

local function fireBossBolt(boss, angle, now)
	nextBoltId += 1
	table.insert(state.bolts, { id = nextBoltId, x = boss.x, y = boss.y, dx = math.cos(angle), dy = math.sin(angle), speed = T.BossBoltSpeed, bornAt = now })
end

function GameState.updateBoss(dt, now)
	local boss = state.boss
	if boss == nil then
		return
	end
	boss.phase = GameState.bossPhase(boss.hp, boss.maxHp)
	-- Side-to-side sine: peak horizontal speed is 70 (100 in phase 3).
	-- The sway ANGLE accumulates (angle += freq * dt) instead of being
	-- recomputed from total boss age: changing speed at P3 only changes
	-- the rate, never the phase, so the cruiser cannot teleport ~208 px
	-- when the phase flips (the old sin(freq * age) formula did).
	local speed = boss.phase == 3 and T.BossPhase3Speed or T.BossSpeed
	local freq = speed / BOSS_SWAY_AMPLITUDE
	if boss.swayAngle == nil then
		boss.swayAngle = boss.swayPhase or 0
	end
	boss.swayAngle += freq * dt
	boss.x = boss.baseX + BOSS_SWAY_AMPLITUDE * math.sin(boss.swayAngle)
	boss.x = clamp(boss.x, boss.size / 2, L.ArenaWidth - boss.size / 2)
	if now >= boss.fireAt then
		boss.lastFiredAt = now
		local p = state.player
		local baseAngle = math.atan2(p.y - boss.y, p.x - boss.x)
		if boss.phase == 1 then
			-- P1: single aimed shot every 2.2 s.
			fireBossBolt(boss, baseAngle, now)
			boss.fireAt = now + T.BossFireSecondsP1
		elseif boss.phase == 2 then
			-- P2: 3-bolt fan every 1.8 s.
			for _, offset in ipairs({ -T.FanSpreadHalfAngle, 0, T.FanSpreadHalfAngle }) do
				fireBossBolt(boss, baseAngle + offset, now)
			end
			boss.fireAt = now + T.BossFireSecondsP2
		else
			-- P3: fast SWEEP every 1.1 s. Each shot fires on a sweep
			-- angle that walks back and forth across a 120-degree arc
			-- centered on the player's bearing, advancing one fixed step
			-- per shot and reversing at the arc ends — a walking barrage,
			-- not the aimed tracking of P1.
			if boss.sweepAngle == nil then
				boss.sweepAngle = -T.BossSweepHalfAngle
				boss.sweepDir = 1
			end
			fireBossBolt(boss, baseAngle + boss.sweepAngle, now)
			boss.sweepAngle += boss.sweepDir * T.BossSweepStep
			if boss.sweepAngle >= T.BossSweepHalfAngle then
				boss.sweepAngle = T.BossSweepHalfAngle
				boss.sweepDir = -1
			elseif boss.sweepAngle <= -T.BossSweepHalfAngle then
				boss.sweepAngle = -T.BossSweepHalfAngle
				boss.sweepDir = 1
			end
			boss.fireAt = now + T.BossFireSecondsP3
		end
	end
	if boss.phase == 3 then
		-- P3: summon 2 drones every 6 s, flanking the boss.
		if boss.nextDroneAt == nil then
			boss.nextDroneAt = now + T.BossDroneSpawnSeconds
		end
		if now >= boss.nextDroneAt then
			boss.nextDroneAt = now + T.BossDroneSpawnSeconds
			local d1 = Spawner.spawnDroneAt(boss.x - 60, boss.y + 40, state.wave, now)
			local d2 = Spawner.spawnDroneAt(boss.x + 60, boss.y + 40, state.wave, now)
			if d1 ~= nil then
				table.insert(state.enemies, d1)
			end
			if d2 ~= nil then
				table.insert(state.enemies, d2)
			end
		end
	end
end

function GameState.updateBullets(dt, now)
	for i = #state.bullets, 1, -1 do
		local b = state.bullets[i]
		b.x += b.dx * T.BulletSpeed * dt
		b.y += b.dy * T.BulletSpeed * dt
		if now - b.bornAt > T.BulletLifetime or b.x < 0 or b.x > L.ArenaWidth or b.y < 0 or b.y > L.ArenaHeight then
			table.remove(state.bullets, i)
		end
	end
end

function GameState.updateBolts(dt, now)
	local p = state.player
	for i = #state.bolts, 1, -1 do
		local s = state.bolts[i]
		s.x += s.dx * (s.speed or T.EnemyBoltSpeed) * dt
		s.y += s.dy * (s.speed or T.EnemyBoltSpeed) * dt
		-- Near-miss: a bolt that passes within 30 px WITHOUT hitting
		-- pays +25 once. Award on EXIT from the annulus, not on
		-- entry: a bolt still approaching can hit on the next tick,
		-- and an incoming hit is not a near miss. A bolt that hits
		-- is removed by checkPlayerHits before it can exit, so an
		-- armed bolt that leaves the annulus has truly missed.
		-- This check runs BEFORE removal below, so an armed bolt
		-- that leaves the annulus and the arena in the same tick
		-- still pays instead of being silently dropped.
		local d = dist(p.x, p.y, s.x, s.y)
		local hitR = (T.PlayerSize + T.EnemyBoltSize) / 2
		if s.nearMissGiven ~= true and d < T.NearMissRadius and d >= hitR then
			s.nearMissArmed = true
		elseif s.nearMissArmed == true and d >= T.NearMissRadius then
			s.nearMissArmed = false
			s.nearMissGiven = true
			state.score += T.NearMissBonus
			state.dangerBonus += T.NearMissBonus
			-- A near-miss pays the bonus but never touches lastKillAt:
			-- the streak is a kill chain only, so a near-miss must not
			-- refresh the streak window.
			pushEvent("CLOSE!", p.x, p.y, "CLOSE! +" .. tostring(T.NearMissBonus))
		end
		if now - s.bornAt > T.EnemyBoltLifetime or s.x < 0 or s.x > L.ArenaWidth or s.y < 0 or s.y > L.ArenaHeight then
			table.remove(state.bolts, i)
		end
	end
end

function GameState.updateTrails(now)
	for i = #state.trails, 1, -1 do
		if now >= state.trails[i].expiresAt then
			table.remove(state.trails, i)
		end
	end
end

function GameState.updatePowerups(now)
	for i = #state.powerups, 1, -1 do
		if now - state.powerups[i].bornAt > T.PowerupLifetime then
			table.remove(state.powerups, i)
		end
	end
end

-- Award points for a kill, applying the streak multiplier, plus the
-- kill-after-fire danger bonus: killed within 1.5 s of its last shot.
local function awardKill(x, y, base, target)
	if state.clock - state.lastKillAt <= T.StreakWindowSeconds then
		state.streak += 1
	else
		state.streak = 1
	end
	state.lastKillAt = state.clock
	local mult = math.min(state.streak, T.StreakMaxMult)
	local awarded = base * mult
	local text = "+" .. tostring(awarded)
	if mult > 1 then
		text = text .. " ×" .. tostring(mult)
	end
	state.score += awarded
	state.killPoints += awarded
	pushEvent("kill", x, y, text)
	if target ~= nil and target.lastFiredAt ~= nil and state.clock - target.lastFiredAt <= T.DangerKillWindowSeconds then
		state.score += T.DangerKillBonus
		state.dangerBonus += T.DangerKillBonus
		pushEvent("DANGER!", x, y, "DANGER! +" .. tostring(T.DangerKillBonus))
	end
end

local function maybeDropPowerup(x, y)
	if #state.powerups >= T.PowerupMaxOnField then
		return
	end
	if math.random() < T.PowerupDropChance then
		nextPowerupId += 1
		local kinds = { "Shield", "Rapid", "Spread" }
		table.insert(state.powerups, {
			id = nextPowerupId,
			x = x,
			y = y,
			kind = kinds[math.random(1, 3)],
			bornAt = state.clock,
		})
	end
end

function GameState.checkBulletHits()
	for i = #state.bullets, 1, -1 do
		local b = state.bullets[i]
		local hit = false
		for j = #state.enemies, 1, -1 do
			local e = state.enemies[j]
			if dist(b.x, b.y, e.x, e.y) < e.size / 2 + 7 then
				table.remove(state.bullets, i)
				hit = true
				e.hp -= 1
				if e.hp <= 0 then
					awardKill(e.x, e.y, e.score, e)
					maybeDropPowerup(e.x, e.y)
					table.remove(state.enemies, j)
					if #state.enemies == 0 and #state.spawnQueue == 0 and state.boss == nil and state.phase == "PLAYING" then
						GameState.clearWave()
					end
				end
				break
			end
		end
		if not hit and state.boss ~= nil then
			local boss = state.boss
			if dist(b.x, b.y, boss.x, boss.y) < boss.size / 2 + 7 then
				table.remove(state.bullets, i)
				boss.hp -= 1
				boss.phase = GameState.bossPhase(boss.hp, boss.maxHp)
				if boss.hp <= 0 then
					awardKill(boss.x, boss.y, boss.score, boss)
					state.boss = nil
					-- No endRun here: the wave only ends once the remaining
					-- enemies and spawn queue are empty, so the wave-clear
					-- check below (and in stepGame) fires clearWave(), which
					-- awards the wave 5 bonus, and WIN follows from the
					-- WAVE_CLEAR timer. Ending here would skip the 1,250
					-- bonus and discard the surviving enemies.
				end
			end
		end
		-- A kill can end the wave (clearWave), which leaves PLAYING;
		-- stop here, never mid-loop.
		if state.phase ~= "PLAYING" then
			return
		end
	end
end

function GameState.damagePlayer()
	local now = state.clock
	if now < state.player.invulnUntil or now < state.player.dashInvulnUntil then
		return
	end
	state.hearts -= 1
	state.player.invulnUntil = now + T.InvulnSeconds
	state.streak, state.lastKillAt = 0, 0
	pushEvent("damage", state.player.x, state.player.y, "-1")
	if state.hearts <= 0 then
		GameState.endRun(false)
	end
end

-- A hit while shielded is absorbed: no hull lost, streak kept.
-- The shield breaks, and the player still gets the 1.2 s invulnerability
-- window so the same touching enemy cannot damage them on the next frame.
local function absorbHit()
	state.shieldUntil = 0
	state.player.invulnUntil = state.clock + T.InvulnSeconds
	pushEvent("shield", state.player.x, state.player.y, "SHIELD")
end

function GameState.checkPlayerHits(now)
	if now < state.player.invulnUntil or now < state.player.dashInvulnUntil then
		return
	end
	local p = state.player
	local function takeHit()
		if now < state.shieldUntil then
			absorbHit()
		else
			GameState.damagePlayer()
		end
	end
	for _, e in ipairs(state.enemies) do
		if dist(p.x, p.y, e.x, e.y) < (T.PlayerSize + e.size) / 2 then
			takeHit()
			return
		end
	end
	if state.boss ~= nil then
		local boss = state.boss
		if dist(p.x, p.y, boss.x, boss.y) < (T.PlayerSize + boss.size) / 2 then
			takeHit()
			return
		end
	end
	for i = #state.trails, 1, -1 do
		local t = state.trails[i]
		if dist(p.x, p.y, t.x, t.y) < (T.PlayerSize + T.TrailSize) / 2 then
			table.remove(state.trails, i)
			takeHit()
			return
		end
	end
	for i = #state.bolts, 1, -1 do
		local s = state.bolts[i]
		if dist(p.x, p.y, s.x, s.y) < (T.PlayerSize + T.EnemyBoltSize) / 2 then
			table.remove(state.bolts, i)
			takeHit()
			return
		end
	end
end

function GameState.checkPowerupPickups(now)
	local p = state.player
	for i = #state.powerups, 1, -1 do
		local powerup = state.powerups[i]
		if dist(p.x, p.y, powerup.x, powerup.y) < T.PowerupPickupRadius then
			table.remove(state.powerups, i)
			state.score += T.PowerupScore
			state.pickupPoints += T.PowerupScore
			local text = "+" .. tostring(T.PowerupScore) .. " " .. powerup.kind
			if powerup.kind == "Shield" then
				state.shieldUntil = now + T.ShieldSeconds
			elseif powerup.kind == "Rapid" then
				state.rapidUntil = now + T.RapidSeconds
			elseif powerup.kind == "Spread" then
				state.spreadUntil = now + T.SpreadSeconds
			end
			pushEvent("pickup", powerup.x, powerup.y, text)
		end
	end
end

function GameState.awardWaveBonus()
	local bonus = Config.Waves[state.wave].Bonus
	state.score += bonus
	state.waveBonuses += bonus
	return bonus
end

function GameState.clearWave()
	-- Idempotency guard: only a PLAYING wave can clear, so the wave
	-- bonus is paid exactly once even if a future caller lacks a guard.
	if state.phase ~= "PLAYING" then return end
	local bonus = GameState.awardWaveBonus()
	state.phase, state.waveClearTimer = "WAVE_CLEAR", T.WaveClearBannerSeconds
	state.bolts, state.bullets = {}, {}
	-- A finger released during the intermission sends a stop the server
	-- rejects (Input is PLAYING-only), so the old touch target would
	-- survive into the next wave. Clear movement here instead.
	GameState.clearTouchTarget()
	GameState.setMove(0, 0)
	state.freezeTimer = T.FreezeSeconds
	-- Streak and lastKillAt are PRESERVED across the clear (no reset).
	-- The clock keeps running through the 0.6 s freeze + 2.5 s
	-- intermission (3.1 s total, longer than the 3.0 s streak window),
	-- so shift the kill timestamp forward by exactly the paused time:
	-- the streak survives with the same remaining window it had when
	-- the wave cleared.
	state.lastKillAt += T.FreezeSeconds + T.WaveClearBannerSeconds
	if state.wave < Config.TotalWaves then
		local nextWave = state.wave + 1
		local nextMod = Config.Waves[nextWave].Modifier
		GameState.showWaveBanner("WAVE " .. nextWave .. " — " .. nextMod .. " FORMATIONS", "+" .. bonus .. " BONUS", T.FreezeSeconds + T.WaveClearBannerSeconds)
	else
		GameState.showWaveBanner("WAVE " .. state.wave .. " CLEARED", "+" .. bonus .. " BONUS", T.FreezeSeconds + T.WaveClearBannerSeconds)
	end
	-- Reward power-up at arena center (320, 240). Guaranteed: bypasses
	-- the on-field cap so the wave-clear reward always appears.
	-- Skipped on the final wave: endRun clears state.powerups the
	-- moment the WAVE_CLEAR timer expires, so a wave-5 reward could
	-- never be picked up (pickups only run while PLAYING).
	if state.wave < Config.TotalWaves then
		nextPowerupId += 1
		local kinds = { "Shield", "Rapid", "Spread" }
		table.insert(state.powerups, {
			id = nextPowerupId,
			x = L.ArenaWidth / 2,
			y = L.ArenaHeight / 2,
			kind = kinds[math.random(1, 3)],
			bornAt = state.clock,
		})
	end
end

function GameState.endRun(won)
	state.phase = won and "WIN" or "LOSE"
	state.banner = nil
	state.enemies, state.bolts, state.bullets, state.powerups, state.trails = {}, {}, {}, {}, {}
	state.boss, state.spawnQueue = nil, {}
	state.streak, state.lastKillAt = 0, 0
	state.targetId = nil
	-- Clear run timers + player effects only: the final score, wave, time and
	-- breakdown fields must survive for the WIN/LOSE screen and saveBestScore,
	-- so this is NOT a full resetRunState() (that would zero the score first).
	state.fireTimer, state.spawnTimer, state.waveClearTimer, state.freezeTimer = 0, 0, 0, 0
	state.shieldUntil, state.rapidUntil, state.spreadUntil = 0, 0, 0
	local p = state.player
	p.invulnUntil, p.dashUntil, p.dashReadyAt, p.dashInvulnUntil = 0, 0, 0, 0
	p.touchTarget = nil
	task.spawn(GameState.saveBestScore)
end

function GameState.stepGame(dt)
	state.clock += dt
	if state.banner ~= nil and state.clock >= state.bannerUntil then
		state.banner = nil
	end
	-- Wave-clear freeze: brief pause, nothing else ticks — except
	-- power-up ageing: drops must not gain a free 0.6 s of life here
	-- (the freeze only ever runs during the wave-clear intermission;
	-- only clearWave sets freezeTimer). The WAVE_CLEAR branch below
	-- ages them through the remaining 2.5 s, so a drop's 9 s lifetime
	-- is measured in real clock time across the whole 3.1 s pause.
	if state.freezeTimer > 0 then
		state.freezeTimer -= dt
		GameState.updatePowerups(state.clock)
		return
	end
	if state.phase == "WAVE_CLEAR" then
		state.waveClearTimer -= dt
		GameState.updatePowerups(state.clock)
		if state.waveClearTimer <= 0 then
			if state.wave >= Config.TotalWaves then
				GameState.endRun(true)
			else
				GameState.startWave(state.wave + 1)
			end
		end
		return
	end
	if state.phase ~= "PLAYING" then
		return
	end
	state.timeElapsed += dt
	local now = state.clock
	if state.streak > 0 and state.clock - state.lastKillAt > T.StreakWindowSeconds then
		state.streak = 0
	end
	if #state.spawnQueue > 0 then
		state.spawnTimer += dt
		local interval = T.SpawnInterval
		if state.modifier == "DENSE" then
			interval = interval * T.DenseSpawnFactor
		end
		if state.spawnTimer >= interval then
			state.spawnTimer = 0
			local enemy = Spawner.spawnNext(state.spawnQueue, state.wave, state.player.x, state.player.y, now)
			if enemy ~= nil then
				table.insert(state.enemies, enemy)
			end
		end
	end
	GameState.updatePlayer(dt, now)
	GameState.updateEnemies(dt, now)
	GameState.updateBoss(dt, now)
	GameState.updateBullets(dt, now)
	GameState.updateBolts(dt, now)
	GameState.updateTrails(now)
	GameState.updatePowerups(now)
	-- A Weaver that flew off the bottom can empty the wave without a kill.
	if #state.enemies == 0 and #state.spawnQueue == 0 and state.boss == nil and state.phase == "PLAYING" then
		GameState.clearWave()
	end
	GameState.checkBulletHits()
	-- A boss killed by the last bullet can empty the arena AFTER the
	-- check above already ran: resolve completion here, before any
	-- surviving bolt/trail can hit the player and end the run in LOSE
	-- (skipping the wave 5 bonus and the WIN).
	if #state.enemies == 0 and #state.spawnQueue == 0 and state.boss == nil and state.phase == "PLAYING" then
		GameState.clearWave()
	end
	if state.phase ~= "PLAYING" then
		return
	end
	GameState.checkPlayerHits(now)
	if state.phase ~= "PLAYING" then
		return
	end
	GameState.checkPowerupPickups(now)
end

function GameState.getSnapshot()
	local p = state.player
	-- The HUD power-up is derived from the real effect timers, not from
	-- the last pickup record: a broken Shield (shieldUntil = 0) vanishes
	-- at once, and a newer pickup cannot hide an older effect that is
	-- still running. When several run at once, show the one expiring
	-- latest (the most recently applied).
	local powerupField = nil
	local bestName, bestUntil = nil, 0
	if state.clock < state.shieldUntil and state.shieldUntil > bestUntil then
		bestName, bestUntil = "Shield", state.shieldUntil
	end
	if state.clock < state.rapidUntil and state.rapidUntil > bestUntil then
		bestName, bestUntil = "Rapid", state.rapidUntil
	end
	if state.clock < state.spreadUntil and state.spreadUntil > bestUntil then
		bestName, bestUntil = "Spread", state.spreadUntil
	end
	if bestName ~= nil then
		local remaining = bestUntil - state.clock
		powerupField = { name = bestName, seconds = math.floor(remaining * 10 + 0.5) / 10 }
	end
	local snap = {
		phase = state.phase,
		runId = state.runId,
		score = state.score,
		killPoints = state.killPoints,
		waveBonuses = state.waveBonuses,
		dangerBonus = state.dangerBonus,
		pickupPoints = state.pickupPoints,
		wave = state.wave,
		hearts = state.hearts,
		time = state.timeElapsed,
		best = state.bestScore,
		dashReady = state.clock >= p.dashReadyAt,
		modifier = state.modifier,
		streak = state.streak,
		mult = (state.streak == 0 and 1 or math.min(state.streak, T.StreakMaxMult)),
		player = { x = p.x, y = p.y, invuln = state.clock < p.invulnUntil or state.clock < p.dashInvulnUntil },
		enemies = {},
		bolts = {},
		bullets = {},
		powerups = {},
		trails = {},
		boss = nil,
		targetId = state.targetId,
		powerup = powerupField,
		banner = state.banner,
		events = state.events,
	}
	for _, e in ipairs(state.enemies) do
		table.insert(snap.enemies, { id = e.id, kind = e.kind, x = e.x, y = e.y, charging = e.charging == true, diving = e.diving == true })
	end
	for _, b in ipairs(state.bolts) do
		table.insert(snap.bolts, { id = b.id, x = b.x, y = b.y, angle = math.atan2(b.dy, b.dx) })
	end
	for _, b in ipairs(state.bullets) do
		table.insert(snap.bullets, { id = b.id, x = b.x, y = b.y, angle = math.atan2(b.dy, b.dx) })
	end
	for _, u in ipairs(state.powerups) do
		table.insert(snap.powerups, { id = u.id, x = u.x, y = u.y, kind = u.kind })
	end
	for _, t in ipairs(state.trails) do
		table.insert(snap.trails, { id = t.id, x = t.x, y = t.y })
	end
	if state.boss ~= nil then
		snap.boss = { x = state.boss.x, y = state.boss.y, hp = state.boss.hp, maxHp = state.boss.maxHp, phase = state.boss.phase }
	end
	state.events = {}
	return snap
end

return GameState
