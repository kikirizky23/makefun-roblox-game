-- PlayerController renders the arena world and polls player input
-- It owns no score, wave, heart, or enemy state, it only shows snapshots
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild(Config.RemotesFolder)
local GameStateEvent = remotes:WaitForChild(Config.GameStateEvent)
local PlayerActionEvent = remotes:WaitForChild(Config.PlayerActionEvent)
local Colors = Config.Colors
local Layout = Config.Layout
local Tuning = Config.Tuning
-- Design values with no Config field yet, kept in one table
local LIT = { LerpRate = 18, InputHz = 10, AimFallback = 100, BodyCorner = 8,
	CoreCorner = 4, BoltCorner = 3, OrbCorner = 8, PopupWidth = 120, PopupHeight = 28,
	PopupTextSize = 20, PopupRise = 40, PopupTime = 0.7 }
local LocalPlayer = Players.LocalPlayer
local Arena = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("EmberArenaGui"):WaitForChild("Arena")
local snapshot, playerFrame = nil, nil
local tracked, enemyFrames, boltFrames, orbFrames = {}, {}, {}, {}
local lastMove, lastSentMove = Vector2.zero, Vector2.zero
local inputTimer, lastShotAt, lastDashAt, blinkTimer = 0, 0, 0, 0
local blinkOn = false
local function round(frame, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end
local function makeEntity(width, height, color, coreSize, coreColor, radius)
	local body = Instance.new("Frame")
	body.Size = UDim2.fromOffset(width, height)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0; body.ZIndex = 3
	round(body, radius)
	if coreSize > 0 then
		local core = Instance.new("Frame")
		core.Size = UDim2.fromOffset(coreSize, coreSize); core.Position = UDim2.fromOffset((width - coreSize) / 2, (height - coreSize) / 2)
		core.BackgroundColor3 = coreColor; core.BorderSizePixel = 0
		round(core, LIT.CoreCorner)
		core.Parent = body
	end
	return body
end
local SPECS = {
	Player = { "PlayerSize", "PlayerSize", "PlayerCoreSize", "PLAYER", "PLAYER_CORE", "BodyCorner" },
	Chaser = { "ChaserSize", "ChaserSize", "ChaserCoreSize", "CHASER", "CHASER_CORE", "BodyCorner" },
	Drifter = { "DrifterSize", "DrifterSize", "DrifterCoreSize", "DRIFTER", "DRIFTER_CORE", "BodyCorner" },
	Bolt = { "BoltSizeX", "BoltSizeY", nil, "BOLT", "BOLT", "BoltCorner" },
	Orb = { "OrbSize", "OrbSize", "OrbCoreSize", "ORB", "ORB_CORE", "OrbCorner" },
}
local function buildEntity(item, kind)
	local spec = SPECS[kind]; local width, height = Tuning[spec[1]], Tuning[spec[2]]
	local coreSize = 0
	if spec[3] ~= nil then coreSize = Tuning[spec[3]] end
	local frame = makeEntity(width, height, Colors[spec[4]], coreSize, Colors[spec[5]], LIT[spec[6]])
	tracked[frame] = { x = item.x, y = item.y, tx = item.x, ty = item.y, halfX = width / 2, halfY = height / 2 }
	frame.Position = UDim2.fromOffset(item.x - width / 2, item.y - height / 2); frame.Parent = Arena
	return frame
end
local function lerpEntity(frame, dt)
	local state = tracked[frame]; if state == nil then return end
	local step = math.min(1, dt * LIT.LerpRate)
	state.x = state.x + (state.tx - state.x) * step
	state.y = state.y + (state.ty - state.y) * step
	frame.Position = UDim2.fromOffset(state.x - state.halfX, state.y - state.halfY)
end
local function reconcile(items, frames, kind)
	local seen = {}
	for _, item in ipairs(items) do
		seen[item.id] = true
		local frame = frames[item.id]; if frame == nil then frame = buildEntity(item, kind or item.kind); frames[item.id] = frame end
		local state = tracked[frame]; if state ~= nil then state.tx = item.x; state.ty = item.y end
		if item.angle ~= nil then frame.Rotation = math.deg(item.angle) end
	end
	for id, frame in pairs(frames) do
		if seen[id] == nil then frames[id] = nil; tracked[frame] = nil; frame:Destroy() end
	end
end
local function renderWorld(snap)
	if snap.player ~= nil then
		if playerFrame == nil then playerFrame = buildEntity(snap.player, "Player") end
		local state = tracked[playerFrame]; if state ~= nil then state.tx = snap.player.x; state.ty = snap.player.y end
	end
	reconcile(snap.enemies or {}, enemyFrames, nil)
	reconcile(snap.bolts or {}, boltFrames, "Bolt")
	reconcile(snap.orbs or {}, orbFrames, "Orb")
end
local function flashPlayer()
	blinkTimer = 0; blinkOn = false; if playerFrame ~= nil then playerFrame.Visible = false end
end
local function updatePlayerFlash(dt)
	if playerFrame == nil or snapshot == nil or snapshot.player == nil then return end
	if snapshot.player.invuln == true then
		blinkTimer = blinkTimer + dt
		if blinkTimer >= Tuning.InvulnBlinkSeconds then blinkTimer = 0; blinkOn = not blinkOn; playerFrame.Visible = blinkOn end
	elseif playerFrame.Visible == false then
		playerFrame.Visible = true
	end
end
local function showScorePopup(x, y, text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(LIT.PopupWidth, LIT.PopupHeight)
	label.Position = UDim2.fromOffset(x - LIT.PopupWidth / 2, y - LIT.PopupHeight / 2)
	label.BackgroundTransparency = 1; label.Text = text
	label.Font = Enum.Font.GothamBold; label.TextSize = LIT.PopupTextSize
	label.TextColor3 = Colors.TITLE_GOLD; label.ZIndex = 4; label.Parent = Arena
	local tween = TweenService:Create(label, TweenInfo.new(LIT.PopupTime, Enum.EasingStyle.Linear), {
		Position = UDim2.fromOffset(x - LIT.PopupWidth / 2, y - LIT.PopupHeight / 2 - LIT.PopupRise),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function() label:Destroy() end)
end
local function sendInput(move)
	lastSentMove = move; inputTimer = 0
	PlayerActionEvent:FireServer({ type = "Input", mx = move.X, my = move.Y })
end
local function pollInput(dt)
	if snapshot == nil or snapshot.phase ~= "PLAYING" then return end
	local mx, my = 0, 0
	for _, key in ipairs({ { Enum.KeyCode.W, 0, -1 }, { Enum.KeyCode.S, 0, 1 }, { Enum.KeyCode.A, -1, 0 }, { Enum.KeyCode.D, 1, 0 }, { Enum.KeyCode.Up, 0, -1 }, { Enum.KeyCode.Down, 0, 1 }, { Enum.KeyCode.Left, -1, 0 }, { Enum.KeyCode.Right, 1, 0 } }) do
		if UserInputService:IsKeyDown(key[1]) then mx = mx + key[2]; my = my + key[3] end
	end
	local move = Vector2.new(mx, my)
	if move.Magnitude > 1 then move = move.Unit end
	lastMove = move; inputTimer = inputTimer + dt
	if move ~= lastSentMove or inputTimer >= 1 / LIT.InputHz then sendInput(move) end
end
local function fireAt(tx, ty)
	if snapshot == nil or snapshot.phase ~= "PLAYING" or tick() - lastShotAt < Tuning.FireCooldown then return false end
	lastShotAt = tick()
	PlayerActionEvent:FireServer({ type = "Shoot", tx = tx, ty = ty })
	return true
end
local function onShoot()
	local mouse = LocalPlayer:GetMouse()
	local origin = Arena.AbsolutePosition
	fireAt(math.clamp(mouse.X - origin.X, 0, Layout.ArenaWidth), math.clamp(mouse.Y - origin.Y, 0, Layout.ArenaHeight))
end
local function onShootKey()
	if snapshot == nil or snapshot.player == nil then return end
	local tx, ty, best = nil, nil, nil
	for _, enemy in ipairs(snapshot.enemies or {}) do
		local dist = (Vector2.new(enemy.x, enemy.y) - Vector2.new(snapshot.player.x, snapshot.player.y)).Magnitude
		if best == nil or dist < best then best, tx, ty = dist, enemy.x, enemy.y end
	end
	if tx == nil then
		tx = math.clamp(snapshot.player.x + lastMove.X * LIT.AimFallback, 0, Layout.ArenaWidth); ty = math.clamp(snapshot.player.y + lastMove.Y * LIT.AimFallback, 0, Layout.ArenaHeight)
	end
	fireAt(tx, ty)
end
local function onDash()
	if snapshot == nil or snapshot.phase ~= "PLAYING" or tick() - lastDashAt < Tuning.DashCooldown then return end
	lastDashAt = tick()
	PlayerActionEvent:FireServer({ type = "Dash" })
end
local function onStateSnapshot(snap)
	snapshot = snap
	renderWorld(snap)
	if snap.events ~= nil then
		for _, event in ipairs(snap.events) do
			if event.type == "kill" or event.type == "pickup" then showScorePopup(event.x, event.y, event.text) elseif event.type == "damage" then flashPlayer() end
		end
	end
end
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed == false then onShoot() end
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		onShootKey()
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		onDash()
	elseif input.KeyCode == Enum.KeyCode.R then
		if snapshot ~= nil and (snapshot.phase == "PLAYING" or snapshot.phase == "WAVE_CLEAR" or snapshot.phase == "WIN" or snapshot.phase == "LOSE") then PlayerActionEvent:FireServer({ type = "Restart" }) end
	elseif input.KeyCode == Enum.KeyCode.Return then
		if snapshot ~= nil and snapshot.phase == "MENU" then PlayerActionEvent:FireServer({ type = "Start" }) end
		if snapshot ~= nil and (snapshot.phase == "WIN" or snapshot.phase == "LOSE") then PlayerActionEvent:FireServer({ type = "Restart" }) end
	end
end)
RunService.RenderStepped:Connect(function(dt)
	pollInput(dt)
	updatePlayerFlash(dt)
	for frame in pairs(tracked) do
		lerpEntity(frame, dt)
	end
end)
GameStateEvent.OnClientEvent:Connect(onStateSnapshot)
