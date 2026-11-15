-- init.server: boot, wiring, and the single server loop
-- Creates the remotes folder, loads the best score, steps the game
-- on Heartbeat and broadcasts a state snapshot at 20 Hz
-- Auto-fire is server-side: there is no client Shoot action

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(script.GameState)

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = Config.RemotesFolder
remotesFolder.Parent = ReplicatedStorage

local stateEvent = Instance.new("RemoteEvent")
stateEvent.Name = Config.GameStateEvent
stateEvent.Parent = remotesFolder

local actionEvent = Instance.new("RemoteEvent")
actionEvent.Name = Config.PlayerActionEvent
actionEvent.Parent = remotesFolder

local broadcastTimer = 0
local broadcastInterval = 1 / Config.Tuning.SnapshotHz

local owner = nil

local function isFinite(v)
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function broadcastSnapshot()
	stateEvent:FireAllClients(GameState.getSnapshot())
end

local function onPlayerAdded(player)
	if owner == nil then
		owner = player
	end
	broadcastSnapshot()
end

local function onPlayerAction(player, action)
	if typeof(action) ~= "table" then
		return
	end
	if player ~= owner then
		return
	end
	local phase = GameState.getPhase()
	if action.type == "Start" or action.type == "Restart" then
		if phase == "MENU" or phase == "WIN" or phase == "LOSE" or (action.type == "Restart" and phase == "PLAYING") or (action.type == "Restart" and phase == "WAVE_CLEAR") then
			GameState.startRun()
			broadcastSnapshot()
		end
		return
	end
	if phase ~= "PLAYING" then
		return
	end
	if action.type == "Input" then
		-- Touch target mode: the client sends where the ship should go.
		-- The server moves there and stops exactly on arrival (no
		-- overshoot/oscillation). The move vector is ignored in this mode.
		local tx = tonumber(action.tx)
		local ty = tonumber(action.ty)
		if isFinite(tx) and isFinite(ty) then
			GameState.setTouchTarget(tx, ty)
		else
			-- Vector mode (keyboard, or touch released): no target.
			GameState.clearTouchTarget()
			local mx = tonumber(action.mx)
			if not isFinite(mx) then
				mx = 0
			end
			mx = math.clamp(mx, -1, 1)
			local my = tonumber(action.my)
			if not isFinite(my) then
				my = 0
			end
			my = math.clamp(my, -1, 1)
			GameState.setMove(mx, my)
		end
	elseif action.type == "Dash" then
		GameState.tryDash()
	end
end

local function startServer()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		if player == owner then
			owner = nil
			GameState.resetToMenu()
			broadcastSnapshot()
		end
	end)
	actionEvent.OnServerEvent:Connect(onPlayerAction)
	RunService.Heartbeat:Connect(function(dt)
		GameState.stepGame(dt)
		broadcastTimer += dt
		if broadcastTimer >= broadcastInterval then
			broadcastTimer = 0
			broadcastSnapshot()
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if owner == nil then
			owner = player
		end
	end
	task.spawn(GameState.loadBestScore)
end

startServer()
