-- Spawner: wave composition (formation patterns) and spawn-point picking
-- Holds no run state of its own except the enemy id counter; called by GameState
-- Queue entries are tables {kind, laneX}: spawnNext places the enemy at its
-- formation lane x (clamped to the edge inset) instead of a random x

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Spawner = {}
local nextId = 0

local function dist(x1, y1, x2, y2)
	local dx, dy = x1 - x2, y1 - y2
	return math.sqrt(dx * dx + dy * dy)
end

-- Enemy ids are unique per run: GameState calls resetIds() in startRun.
function Spawner.resetIds()
	nextId = 0
end

-- Formation lane lists, one per wave (design 640 px wide arena).
local LANES = {
	-- W1 wedge: V shape, center first, pairs spreading outward.
	{ 320, 260, 380, 200, 440, 140 },
	-- W2 alternating lanes: staggered left/right.
	{ 160, 480, 200, 440, 240, 400, 280, 360, 320 },
	-- W3 dense: tight cluster around center (spawn interval x0.7 too).
	{ 280, 360, 300, 340, 260, 380, 320, 290, 350, 310, 330 },
	-- W4 escort: gunners at 240/400, flanked by drones in queue order.
	-- Queue D G D D G D puts the gunners in slots 2 and 5, which the
	-- round-robin lane pairing maps to 240 and 400 (mirroring in
	-- pickSpawnPoint swaps 240<->400, so the pair holds).
	{ 200, 240, 280, 360, 400, 440, 220, 320, 380, 480, 160, 520 },
	-- W5 swarm: ring around the boss spawn (320, 70).
	{ 260, 380, 300, 340, 240, 400, 280, 360, 320, 270, 370, 310, 350 },
}

-- Queue order per wave. W4 escorts each gunner with drones (D G D D G D,
-- then weavers, then leftover drones). W5 interleaves drones/weavers around
-- the boss, gunners last. Other waves: drones, weavers, gunners.
local function kindOrder(wave, def)
	local order = {}
	if wave == 4 then
		local drones, weavers, gunners = def.Drones, def.Weavers, def.Gunners
		while gunners > 0 do
			if drones > 0 then
				table.insert(order, "Drone")
				drones -= 1
			end
			table.insert(order, "Gunner")
			gunners -= 1
			if drones > 0 then
				table.insert(order, "Drone")
				drones -= 1
			end
		end
		for _ = 1, weavers do
			table.insert(order, "Weaver")
		end
		for _ = 1, drones do
			table.insert(order, "Drone")
		end
		return order
	end
	if wave == 5 then
		local drones, weavers, gunners = def.Drones, def.Weavers, def.Gunners
		while drones > 0 or weavers > 0 do
			if drones > 0 then
				table.insert(order, "Drone")
				drones -= 1
			end
			if weavers > 0 then
				table.insert(order, "Weaver")
				weavers -= 1
			end
		end
		for _ = 1, gunners do
			table.insert(order, "Gunner")
		end
		return order
	end
	for _ = 1, def.Drones do
		table.insert(order, "Drone")
	end
	for _ = 1, def.Weavers do
		table.insert(order, "Weaver")
	end
	for _ = 1, def.Gunners do
		table.insert(order, "Gunner")
	end
	return order
end

-- Build the spawn queue for a wave: formation kind order + lane x per slot.
-- SWARM counts already include the +2/+2; nothing extra is added here.
function Spawner.buildWaveQueue(wave)
	local def = Config.Waves[wave]
	local kinds = kindOrder(wave, def)
	local lanes = LANES[wave]
	local queue = {}
	for i, kind in ipairs(kinds) do
		local laneX = lanes[(i - 1) % #lanes + 1]
		table.insert(queue, { kind = kind, laneX = laneX })
	end
	return queue
end

-- Top-edge spawn point (y = 20) at the formation lane x, clamped to the
-- edge inset. If the lane is too close to the player, mirror it across the
-- arena center; if still too close, take the farther top corner.
function Spawner.pickSpawnPoint(laneX, playerX, playerY)
	local width = Config.Layout.ArenaWidth
	local inset = Config.Tuning.SpawnEdgeInset
	local minDist = Config.Tuning.SpawnMinPlayerDistance
	local x = math.clamp(laneX, inset, width - inset)
	if dist(x, 20, playerX, playerY) < minDist then
		x = width - x
		if dist(x, 20, playerX, playerY) < minDist then
			x = (playerX < width / 2) and (width - inset) or inset
		end
	end
	return x, 20
end

-- Base speed + 8 per wave above wave 1; SWIFT multiplies by 1.15.
local function waveSpeed(base, wave, modifier)
	local speed = base + Config.Tuning.WaveSpeedBonus * (wave - 1)
	if modifier == "SWIFT" then
		speed = speed * Config.Tuning.SwiftMultiplier
	end
	return speed
end

-- Shared enemy record builder. `phase` is the ATTACK phase (boss only);
-- `swayPhase` is the sine offset for Weaver sway / Gunner strafe / boss sway.
local function makeEnemy(kind, x, y, wave, now)
	local def = Config.Waves[wave]
	local modifier = def.Modifier
	local hp, speed, size, score = 1, 0, 24, 100
	if kind == "Drone" then
		hp = Config.Tuning.DroneHp
		speed = waveSpeed(Config.Tuning.DroneSpeed, wave, modifier)
		size = Config.Tuning.DroneSize
		score = Config.Tuning.DroneScore
	elseif kind == "Weaver" then
		hp = Config.Tuning.WeaverHp
		speed = waveSpeed(Config.Tuning.WeaverSpeed, wave, modifier)
		size = Config.Tuning.WeaverSize
		score = Config.Tuning.WeaverScore
	elseif kind == "Gunner" then
		hp = Config.Tuning.GunnerHp
		speed = waveSpeed(Config.Tuning.GunnerSpeed, wave, modifier)
		size = Config.Tuning.GunnerSize
		score = Config.Tuning.GunnerScore
	end
	nextId += 1
	local enemy = {
		id = nextId,
		kind = kind,
		x = x,
		y = y,
		hp = hp,
		maxHp = hp,
		speed = speed,
		size = size,
		score = score,
		baseX = x,
		swayPhase = math.random() * math.pi * 2,
		bornAt = now,
		diving = false,
		charging = false,
		lastFiredAt = nil,
	}
	if kind == "Drone" then
		enemy.diveState = "steer"
		enemy.telegraphUntil = 0
		enemy.diveX = x
	elseif kind == "Weaver" then
		enemy.lastTrailAt = now
	elseif kind == "Gunner" then
		enemy.fireAt = now + Config.Tuning.GunnerFireSeconds
		enemy.chargeUntil = 0
	end
	return enemy
end

-- Pop the next formation entry off the queue and build its enemy record.
function Spawner.spawnNext(queue, wave, playerX, playerY, now)
	local entry = table.remove(queue, 1)
	if entry == nil then
		return nil
	end
	local x, y = Spawner.pickSpawnPoint(entry.laneX, playerX, playerY)
	return makeEnemy(entry.kind, x, y, wave, now)
end

-- A drone spawned mid-arena (boss phase 3 summons two near the boss).
function Spawner.spawnDroneAt(x, y, wave, now)
	if Config.Waves[wave] == nil then
		return nil
	end
	local width, height = Config.Layout.ArenaWidth, Config.Layout.ArenaHeight
	x = math.clamp(x, Config.Tuning.SpawnEdgeInset, width - Config.Tuning.SpawnEdgeInset)
	y = math.clamp(y, Config.Tuning.SpawnEdgeInset, height - Config.Tuning.SpawnEdgeInset)
	return makeEnemy("Drone", x, y, wave, now)
end

-- The wave-5 boss: fixed spawn (320, 70), full HP, starts in attack phase 1.
-- `now` is the run clock at spawn time; GameState passes state.clock.
function Spawner.spawnBoss(wave, now)
	if Config.Waves[wave] == nil then
		return nil
	end
	now = now or 0
	return {
		id = "boss",
		kind = "Boss",
		x = Config.Tuning.BossSpawnX,
		y = Config.Tuning.BossSpawnY,
		hp = Config.Tuning.BossHp,
		maxHp = Config.Tuning.BossHp,
		speed = Config.Tuning.BossSpeed,
		size = Config.Tuning.BossSize,
		score = Config.Tuning.BossScore,
		baseX = Config.Tuning.BossSpawnX,
		swayPhase = 0,
		phase = 1,
		bornAt = now,
		fireAt = now + Config.Tuning.BossFireSecondsP1,
		nextDroneAt = nil,
		lastFiredAt = nil,
		diving = false,
		charging = false,
	}
end

return Spawner
