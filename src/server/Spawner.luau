-- Spawner: wave composition and spawn-point picking only
-- Holds no run state of its own; called by GameState

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Spawner = {}
local nextId = 0
local function dist(x1, y1, x2, y2) local dx, dy = x1 - x2, y1 - y2; return math.sqrt(dx * dx + dy * dy) end
-- Build the spawn queue for a wave: chasers first, then drifters
function Spawner.buildWave(wave)
	local def = Config.Waves[wave]
	local queue = {}
	for _ = 1, def.Chasers do table.insert(queue, "Chaser") end
	for _ = 1, def.Drifters do table.insert(queue, "Drifter") end
	return queue
end
-- Random point on an arena edge, inset 20 px, at least 120 px from player
function Spawner.pickSpawnPoint(playerX, playerY)
	local width, height = Config.Layout.ArenaWidth, Config.Layout.ArenaHeight
	local inset, minDist = Config.Tuning.SpawnEdgeInset, Config.Tuning.SpawnMinPlayerDistance
	for _ = 1, 12 do
		local edge = math.random(1, 4)
		local x, y = inset, inset
		if edge == 1 then x, y = math.random(inset, width - inset), inset
		elseif edge == 2 then x, y = math.random(inset, width - inset), height - inset
		elseif edge == 3 then x, y = inset, math.random(inset, height - inset)
		else x, y = width - inset, math.random(inset, height - inset) end
		if dist(x, y, playerX, playerY) >= minDist then return x, y end
	end
	return width - inset, height - inset
end
-- Random arena point at least 80 px from the player, for orbs
function Spawner.pickOrbPoint(playerX, playerY)
	local width, height = Config.Layout.ArenaWidth, Config.Layout.ArenaHeight
	local minDist = Config.Tuning.OrbMinPlayerDistance
	for _ = 1, 12 do
		local x, y = math.random(30, width - 30), math.random(30, height - 30)
		if dist(x, y, playerX, playerY) >= minDist then return x, y end
	end
	return width / 2, 40
end
-- Pop the next kind off the queue and build its enemy record
function Spawner.spawnNext(queue, wave, playerX, playerY, now)
	local kind = table.remove(queue, 1)
	if kind == nil then return nil end
	local def = Config.Waves[wave]
	local x, y = Spawner.pickSpawnPoint(playerX, playerY)
	local speed, size = def.ChaserSpeed, Config.Tuning.ChaserSize
	if kind == "Drifter" then speed, size = def.DrifterSpeed, Config.Tuning.DrifterSize end
	local angle = math.random() * math.pi * 2
	nextId += 1
	return { id = nextId, kind = kind, x = x, y = y,
		vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
		speed = speed, size = size, bornAt = now }
end

return Spawner
