-- PlayerController renders the arena world and polls player input for NOVA STRIKE
-- It owns no score, wave, heart, or enemy state, it only shows snapshots.
-- Auto-fire is server-side and always on: this script never shoots, it only
-- moves the ship (keyboard or relative touch drag) and dashes. The Hud owns
-- banners, the damage flash, HUD text, overlays, and buttons.
--
-- TOUCH (pure relative drag): the ship never snaps to the finger and the
-- target never jumps. The target starts at the ship's current position,
-- and each accepted finger move shifts it by exactly that finger
-- displacement, clamped to the arena.
-- If the finger leaves the arena the last valid target is held until touch
-- end. A translucent ring marks the current target.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("NovaStrikeRemotes")
local GameStateEvent = remotes:WaitForChild("GameStateEvent")
local PlayerActionEvent = remotes:WaitForChild("PlayerActionEvent")

-- Fixed design numbers for NOVA STRIKE (mirrors the shared Config).
local Colors = {
	PLAYER = Color3.fromRGB(0, 229, 255),
	PLAYER_OUTLINE = Color3.fromRGB(140, 245, 255),
	PLAYER_CORE = Color3.fromRGB(255, 255, 255),
	DRONE = Color3.fromRGB(255, 64, 160),
	DRONE_CORE = Color3.fromRGB(255, 150, 40),
	WEAVER = Color3.fromRGB(255, 150, 40),
	WEAVER_CORE = Color3.fromRGB(255, 255, 255),
	GUNNER = Color3.fromRGB(178, 102, 255),
	GUNNER_RING = Color3.fromRGB(200, 160, 255),
	BOSS = Color3.fromRGB(255, 60, 60),
	BOSS_CORE = Color3.fromRGB(140, 20, 20),
	BULLET = Color3.fromRGB(200, 250, 255),
	ENEMY_BOLT = Color3.fromRGB(255, 120, 60),
	POWERUP = Color3.fromRGB(255, 214, 64),
	POWERUP_TEXT = Color3.fromRGB(16, 20, 44),
	TITLE_GOLD = Color3.fromRGB(255, 214, 64),
	DAMAGE_RED = Color3.fromRGB(255, 40, 40),
	FLASH_YELLOW = Color3.fromRGB(255, 220, 80),
	DIVING = Color3.fromRGB(255, 120, 60),
	PHASE2 = Color3.fromRGB(255, 150, 40),
	PHASE3 = Color3.fromRGB(255, 64, 160),
}
-- Design values with no Config field yet, kept in one table.
-- Entity sizes are client-chosen render sizes (not in the brief): the player
-- diamond 28px (+34px outline), Drone/Weaver 26px, Gunner 30px, Boss 90px
-- (per the brief), bullets 4x16 and bolts 4x14 tapered streaks.
local LIT = {
	LerpRate = 18,
	InputHz = 10,
	ArenaWidth = 640,
	ArenaHeight = 480,
	PlayerSize = 28,
	PlayerOutlineSize = 34,
	PlayerCoreSize = 12,
	DroneSize = 26,
	DroneCoreSize = 10,
	WeaverSize = 26,
	WeaverCoreSize = 10,
	GunnerSize = 30,
	GunnerCoreSize = 12,
	GunnerRingSize = 36,
	BossSize = 90,
	BossCoreSize = 54,
	BulletSizeX = 4,
	BulletSizeY = 16,
	BoltSizeX = 4,
	BoltSizeY = 14,
	PowerupSize = 28,
	PowerupOuterSize = 34,
	PowerupTextSize = 18,
	BodyCorner = 8,
	CoreCorner = 4,
	BoltCorner = 2,
	PowerupCorner = 14,
	PopupWidth = 120,
	PopupHeight = 28,
	PopupTextSize = 20,
	PopupRise = 40,
	PopupTime = 0.7,
	InvulnBlinkSeconds = 0.12,
	TouchDeadZone = 8,
	JitterPx = 6,
	ClampMin = 14,
	ClampMaxX = 626,
	ClampMaxY = 466,
	RingSize = 40,
	BurstCount = 6,
	BurstDistance = 26,
	BurstTime = 0.4,
	GhostCount = 3,
	GhostStep = 14,
	GhostTime = 0.35,
	RecoilTime = 0.15,
	RecoilDistance = 10,
	TrailSize = 16,
	SpinSpeed = 60,
	GunnerRingSpeed = 180,
}

-- The Hud builds the Arena and publishes it through _G.NovaStrikeArena (see
-- Hud.client.luau). Poll until it appears; LocalScript start order is not
-- guaranteed, so a direct read here could run before Hud builds it.
local Arena = nil
while Arena == nil do
	Arena = _G.NovaStrikeArena
	if Arena == nil then
		task.wait(0.1)
	end
end

local snapshot, playerFrame = nil, nil
local tracked, enemyFrames, boltFrames, bulletFrames, powerupFrames, bossFrames = {}, {}, {}, {}, {}, {}
local gunnerRings, spinFrames, chargingFrames = {}, {}, {}
local trailFrames = {}
local lastMove, lastSentMove = Vector2.zero, Vector2.zero
local inputTimer, blinkTimer = 0, 0
local blinkOn = false
-- touchInput is the live InputObject for the drag touch. Typed `any`: the
-- analyzer has no Roblox InputObject type here, and a plain nil-initialized
-- local infers a union that strict mode refuses to compare/assign.
local touchInput: any = nil
local touchTarget: any = nil
local lastSentTarget: any = nil
local targetDirty = false -- accepted touch-target change not yet sent
-- Run tracking for stale-drag cleanup: the server bumps runId on every
-- startRun, and the client drops its drag state when the id changes.
local lastRunId = -1
local lastPhase = ""
-- Last finger position accepted by the jitter gate (design coords).
local lastAcceptedFinger: any = nil
local recoilOffset, recoilTimer = Vector2.zero, 0

-- Touch target ring: a translucent ring at the current drag target so the
-- player sees where the ship is going.
local ringFrame = Instance.new("Frame")
ringFrame.Name = "TouchRing"
ringFrame.Size = UDim2.fromOffset(LIT.RingSize, LIT.RingSize)
ringFrame.BackgroundTransparency = 1
ringFrame.BorderSizePixel = 2
ringFrame.BorderColor3 = Colors.PLAYER
ringFrame.ZIndex = 4
ringFrame.Visible = false
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0, 8)
ringCorner.Parent = ringFrame
ringFrame.Parent = Arena

-- Engine flame: a small orange frame below the ship, flickering in size.
local flameFrame = Instance.new("Frame")
flameFrame.Name = "EngineFlame"
flameFrame.Size = UDim2.fromOffset(8, 10)
flameFrame.BackgroundColor3 = Colors.WEAVER
flameFrame.BorderSizePixel = 0
flameFrame.ZIndex = 3
flameFrame.Visible = false
local flameCorner = Instance.new("UICorner")
flameCorner.CornerRadius = UDim.new(0, 4)
flameCorner.Parent = flameFrame
flameFrame.Parent = Arena

-- Targeting reticle: 4 corner brackets (8 thin frames) around the enemy the
-- auto-fire is currently aiming at (snapshot.targetId).
local reticleFrames = {}
for i = 1, 8 do
	local bracket = Instance.new("Frame")
	bracket.Name = "Reticle" .. tostring(i)
	bracket.BackgroundColor3 = Colors.TITLE_GOLD
	bracket.BorderSizePixel = 0
	bracket.ZIndex = 4
	bracket.Visible = false
	bracket.Parent = Arena
	reticleFrames[i] = bracket
end

local function round(frame, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end

local function makeEntity(width, height, color, coreSize, coreColor, radius, rotation)
	local body = Instance.new("Frame")
	body.Size = UDim2.fromOffset(width, height)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.ZIndex = 3
	if rotation ~= nil and rotation ~= 0 then
		body.Rotation = rotation
	end
	round(body, radius)
	if coreSize > 0 then
		local core = Instance.new("Frame")
		core.Size = UDim2.fromOffset(coreSize, coreSize)
		core.Position = UDim2.fromOffset((width - coreSize) / 2, (height - coreSize) / 2)
		core.BackgroundColor3 = coreColor
		core.BorderSizePixel = 0
		round(core, LIT.CoreCorner)
		core.Parent = body
	end
	return body
end

-- kind -> {w, h, core, color, coreColor, corner, rotation}.
-- Every entry carries the same fields so strict mode infers one table shape.
local SPECS = {
	Player = { w = LIT.PlayerOutlineSize, h = LIT.PlayerOutlineSize, core = 0, color = "PLAYER_OUTLINE", coreColor = "PLAYER_CORE", corner = LIT.BodyCorner, rotation = 45 },
	Drone = { w = LIT.DroneSize, h = LIT.DroneSize, core = LIT.DroneCoreSize, color = "DRONE", coreColor = "DRONE_CORE", corner = LIT.BodyCorner, rotation = 45 },
	Weaver = { w = LIT.WeaverSize, h = LIT.WeaverSize, core = LIT.WeaverCoreSize, color = "WEAVER", coreColor = "WEAVER_CORE", corner = 13, rotation = 30 },
	Gunner = { w = LIT.GunnerSize, h = LIT.GunnerSize, core = LIT.GunnerCoreSize, color = "GUNNER", coreColor = "PLAYER_CORE", corner = LIT.BodyCorner, rotation = 45 },
	Boss = { w = LIT.BossSize, h = LIT.BossSize, core = LIT.BossCoreSize, color = "BOSS", coreColor = "BOSS_CORE", corner = 12, rotation = 0 },
	Bullet = { w = LIT.BulletSizeX, h = LIT.BulletSizeY, core = 0, color = "BULLET", coreColor = "BULLET", corner = LIT.BoltCorner, rotation = 0 },
	Bolt = { w = LIT.BoltSizeX, h = LIT.BoltSizeY, core = 0, color = "ENEMY_BOLT", coreColor = "ENEMY_BOLT", corner = LIT.BoltCorner, rotation = 0 },
	Powerup = { w = LIT.PowerupOuterSize, h = LIT.PowerupOuterSize, core = 0, color = "POWERUP", coreColor = "POWERUP", corner = 4, rotation = 0 },
}
-- Power-up letter by server kind: Shield -> S, Rapid -> R, Spread -> P.
local POWERUP_LETTERS = { Shield = "S", Rapid = "R", Spread = "P" }

local function phaseColor(phase)
	if phase == 2 or phase == "II" then
		return Colors.PHASE2
	end
	if phase == 3 or phase == "III" then
		return Colors.PHASE3
	end
	return Colors.BOSS
end

local function buildEntity(item, kind)
	local spec = SPECS[kind]
	local width, height = spec.w, spec.h
	local frame = makeEntity(width, height, Colors[spec.color], spec.core, Colors[spec.coreColor], spec.corner, spec.rotation)
	if kind == "Player" then
		-- Angular interceptor: bright cyan outline diamond (the frame) with
		-- the cyan ship body + white core nested inside, centered.
		local body = makeEntity(LIT.PlayerSize, LIT.PlayerSize, Colors.PLAYER, LIT.PlayerCoreSize, Colors.PLAYER_CORE, LIT.BodyCorner, 0)
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.5)
		body.Parent = frame
	elseif kind == "Gunner" then
		-- Hexagonal ship (rotated square) + a rotating weapon ring.
		local ring = Instance.new("Frame")
		ring.Name = "WeaponRing"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromOffset(LIT.GunnerRingSize, LIT.GunnerRingSize)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 2
		ring.BorderColor3 = Colors.GUNNER_RING
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(0, 6)
		ringCorner.Parent = ring
		ring.Parent = frame
		gunnerRings[frame] = ring
	elseif kind == "Boss" then
		-- Asymmetric cruiser: 3 glowing weak points (bright yellow dots).
		local weakPoints = { { 14, 20 }, { 64, 20 }, { 39, 60 } }
		for i, pt in ipairs(weakPoints) do
			local dot = Instance.new("Frame")
			dot.Name = "WeakPoint" .. tostring(i)
			dot.Position = UDim2.fromOffset(pt[1], pt[2])
			dot.Size = UDim2.fromOffset(12, 12)
			dot.BackgroundColor3 = Colors.FLASH_YELLOW
			dot.BorderSizePixel = 0
			dot.ZIndex = 4
			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(0, 6)
			dotCorner.Parent = dot
			dot.Parent = frame
		end
	elseif kind == "Powerup" then
		-- Gold icon inside a slowly rotating geometric frame: the outer
		-- frame spins (via spinFrames) and the inner circle + letter ride
		-- along, so the whole pickup reads as a rotating gold token.
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 2
		frame.BorderColor3 = Colors.POWERUP
		local inner = Instance.new("Frame")
		inner.Name = "Icon"
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromOffset(LIT.PowerupSize, LIT.PowerupSize)
		inner.BackgroundColor3 = Colors.POWERUP
		inner.BorderSizePixel = 0
		inner.ZIndex = 3
		local innerCorner = Instance.new("UICorner")
		innerCorner.CornerRadius = UDim.new(0, LIT.PowerupCorner)
		innerCorner.Parent = inner
		inner.Parent = frame
		local letter = POWERUP_LETTERS[item.kind] or "?"
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(LIT.PowerupSize, LIT.PowerupSize)
		label.Position = UDim2.fromOffset(0, 0)
		label.BackgroundTransparency = 1
		label.Text = letter
		label.Font = Enum.Font.GothamBold
		label.TextSize = LIT.PowerupTextSize
		label.TextColor3 = Colors.POWERUP_TEXT
		label.ZIndex = 4
		label.Parent = inner
		spinFrames[frame] = LIT.SpinSpeed
	end
	tracked[frame] = { x = item.x, y = item.y, tx = item.x, ty = item.y, halfX = width / 2, halfY = height / 2 }
	frame.Position = UDim2.fromOffset(item.x - width / 2, item.y - height / 2)
	frame.Parent = Arena
	return frame
end

local function lerpEntity(frame, dt)
	local state = tracked[frame]
	if state == nil then
		return
	end
	local step = math.min(1, dt * LIT.LerpRate)
	state.x = state.x + (state.tx - state.x) * step
	state.y = state.y + (state.ty - state.y) * step
	frame.Position = UDim2.fromOffset(state.x - state.halfX, state.y - state.halfY)
end

local function reconcile(items, frames, kind)
	local seen = {}
	for _, item in ipairs(items) do
		seen[item.id] = true
		local frame = frames[item.id]
		if frame == nil then
			frame = buildEntity(item, kind or item.kind)
			frames[item.id] = frame
		end
		local state = tracked[frame]
		if state ~= nil then
			state.tx = item.x
			state.ty = item.y
		end
		if item.angle ~= nil then
			frame.Rotation = math.deg(item.angle)
		end
	end
	for id, frame in pairs(frames) do
		if seen[id] == nil then
			frames[id] = nil
			tracked[frame] = nil
			gunnerRings[frame] = nil
			spinFrames[frame] = nil
			chargingFrames[frame] = nil
			frame:Destroy()
		end
	end
end

-- Weaver trails come from the server (snapshot.trails = {{id, x, y}}).
-- Points are rendered oldest-first: the oldest point is the most faded.
-- Rendered size is 16 px (Config TrailSize): edge contact with the 28 px player happens at (28+16)/2 = 22 px, exactly the server damage radius.
local function renderTrails(trails)
	local byId = {}
	for _, t in ipairs(trails or {}) do
		if byId[t.id] == nil then
			byId[t.id] = {}
		end
		table.insert(byId[t.id], t)
	end
	for id, points in pairs(byId) do
		local frames = trailFrames[id]
		if frames == nil then
			frames = {}
			trailFrames[id] = frames
		end
		local n = #points
		if n > 8 then
			n = 8
		end
		for i = 1, n do
			local f = frames[i]
			if f == nil then
				f = Instance.new("Frame")
				f.Size = UDim2.fromOffset(LIT.TrailSize, LIT.TrailSize)
				f.BackgroundColor3 = Colors.WEAVER
				f.BorderSizePixel = 0
				f.ZIndex = 2
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, LIT.TrailSize / 2)
				c.Parent = f
				f.Parent = Arena
				frames[i] = f
			end
			local pt = points[i]
			f.Position = UDim2.fromOffset(pt.x - LIT.TrailSize / 2, pt.y - LIT.TrailSize / 2)
			f.BackgroundTransparency = 0.9 - (i - 1) * (0.35 / math.max(1, n - 1))
			f.Visible = true
		end
		for i = n + 1, #frames do
			frames[i].Visible = false
		end
	end
	for id, frames in pairs(trailFrames) do
		if byId[id] == nil then
			for _, f in ipairs(frames) do
				f:Destroy()
			end
			trailFrames[id] = nil
		end
	end
end

local function updateReticle(snap)
	local tx, ty = nil, nil
	local halfW, halfH = 15, 15
	if snap.targetId ~= nil then
		for _, e in ipairs(snap.enemies or {}) do
			if e.id == snap.targetId then
				tx, ty = e.x, e.y
				local spec = SPECS[e.kind]
				if spec ~= nil then
					halfW = spec.w / 2
					halfH = spec.h / 2
				end
				break
			end
		end
		-- The boss is not in snap.enemies: its server id is "boss" and
		-- its snapshot carries x/y, so aim the reticle at it directly.
		if tx == nil and snap.targetId == "boss" and snap.boss ~= nil then
			tx, ty = snap.boss.x, snap.boss.y
			halfW = SPECS.Boss.w / 2
			halfH = SPECS.Boss.h / 2
		end
	end
	if tx == nil or ty == nil then
		for _, f in ipairs(reticleFrames) do
			f.Visible = false
		end
		return
	end
	local xl = tx - halfW - 4
	local xr = tx + halfW + 4
	local yt = ty - halfH - 4
	local yb = ty + halfH + 4
	local len, thick = 12, 2
	-- 1 TL-h, 2 TL-v, 3 TR-h, 4 TR-v, 5 BL-h, 6 BL-v, 7 BR-h, 8 BR-v
	local rects = {
		{ xl, yt - thick, len, thick }, { xl - thick, yt, thick, len },
		{ xr - len, yt - thick, len, thick }, { xr, yt, thick, len },
		{ xl, yb, len, thick }, { xl - thick, yb - len, thick, len },
		{ xr - len, yb, len, thick }, { xr, yb - len, thick, len },
	}
	for i, r in ipairs(rects) do
		local f = reticleFrames[i]
		f.Position = UDim2.fromOffset(r[1], r[2])
		f.Size = UDim2.fromOffset(r[3], r[4])
		f.Visible = true
	end
end

local function renderWorld(snap)
	if snap.player ~= nil then
		if playerFrame == nil then
			playerFrame = buildEntity(snap.player, "Player")
		end
		local state = tracked[playerFrame]
		if state ~= nil then
			state.tx = snap.player.x
			state.ty = snap.player.y
		end
	end
	reconcile(snap.enemies or {}, enemyFrames, nil)
	reconcile(snap.bolts or {}, boltFrames, "Bolt")
	reconcile(snap.bullets or {}, bulletFrames, "Bullet")
	reconcile(snap.powerups or {}, powerupFrames, "Powerup")
	-- The boss is not in snap.enemies: reconcile its own frame from
	-- snap.boss (created on spawn, destroyed on death).
	if snap.boss ~= nil then
		-- angle = 0 keeps reconcile's item shape (bolts/bullets carry an
		-- angle); the boss frame rotation stays 0 either way.
		reconcile({ { id = "boss", kind = "Boss", x = snap.boss.x, y = snap.boss.y, angle = 0 } }, bossFrames, "Boss")
	else
		reconcile({}, bossFrames, "Boss")
	end
	renderTrails(snap.trails)
	updateReticle(snap)
	-- Live enemy styling from the snapshot: charging enemies get a bright
	-- flashing outline (gunner telegraph), diving drones get a warning tint,
	-- and the boss body takes its phase color.
	local newCharging = {}
	for _, enemy in ipairs(snap.enemies or {}) do
		local frame = enemyFrames[enemy.id]
		if frame ~= nil then
			if enemy.charging == true then
				newCharging[frame] = true
				frame.BorderSizePixel = 2
			else
				frame.BorderSizePixel = 0
			end
			if enemy.kind == "Drone" then
				if enemy.diving == true then
					frame.BackgroundColor3 = Colors.DIVING
				else
					frame.BackgroundColor3 = Colors.DRONE
				end
			end
		end
	end
	-- Boss phase color: the boss body takes its phase color. (The old
	-- branch for kind == "Boss" inside the enemies loop above was dead
	-- code — the boss is never in snap.enemies.)
	if snap.boss ~= nil then
		local bossFrame = bossFrames["boss"]
		if bossFrame ~= nil then
			bossFrame.BackgroundColor3 = phaseColor(snap.boss.phase)
		end
	end
	chargingFrames = newCharging
end

local function flashPlayer()
	blinkTimer = 0
	blinkOn = false
	if playerFrame ~= nil then
		playerFrame.Visible = false
	end
end

local function updatePlayerFlash(dt)
	if playerFrame == nil or snapshot == nil or snapshot.player == nil then
		return
	end
	if snapshot.player.invuln == true then
		blinkTimer = blinkTimer + dt
		if blinkTimer >= LIT.InvulnBlinkSeconds then
			blinkTimer = 0
			blinkOn = not blinkOn
			playerFrame.Visible = blinkOn
		end
	elseif playerFrame.Visible == false then
		playerFrame.Visible = true
	end
end

local function updateRecoil(dt)
	if playerFrame == nil or recoilTimer <= 0 then
		return
	end
	recoilTimer = recoilTimer - dt
	local state = tracked[playerFrame]
	if state == nil then
		return
	end
	local k = math.max(0, recoilTimer / LIT.RecoilTime)
	playerFrame.Position = UDim2.fromOffset(state.x - state.halfX + recoilOffset.X * k, state.y - state.halfY + recoilOffset.Y * k)
end

local function updateFlame()
	if playerFrame == nil or snapshot == nil or snapshot.phase ~= "PLAYING" then
		flameFrame.Visible = false
		return
	end
	local state = tracked[playerFrame]
	if state == nil then
		flameFrame.Visible = false
		return
	end
	local h = 8 + 4 * math.abs(math.sin(tick() * 25))
	flameFrame.Size = UDim2.fromOffset(8, h)
	flameFrame.Position = UDim2.fromOffset(state.x - 4, state.y + state.halfY + 2)
	flameFrame.Visible = true
end

local function updateTouchRing()
	if touchTarget == nil then
		ringFrame.Visible = false
		return
	end
	ringFrame.Position = UDim2.fromOffset(touchTarget.X - LIT.RingSize / 2, touchTarget.Y - LIT.RingSize / 2)
	ringFrame.Visible = true
end

local function showScorePopup(x, y, text, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(LIT.PopupWidth, LIT.PopupHeight)
	label.Position = UDim2.fromOffset(x - LIT.PopupWidth / 2, y - LIT.PopupHeight / 2)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextSize = LIT.PopupTextSize
	if color ~= nil then
		label.TextColor3 = color
	else
		label.TextColor3 = Colors.TITLE_GOLD
	end
	label.ZIndex = 4
	label.Parent = Arena
	local tween = TweenService:Create(label, TweenInfo.new(LIT.PopupTime, Enum.EasingStyle.Linear), {
		Position = UDim2.fromOffset(x - LIT.PopupWidth / 2, y - LIT.PopupHeight / 2 - LIT.PopupRise),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

local BURST_COLORS = { Colors.TITLE_GOLD, Colors.PLAYER, Colors.DRONE }
local function spawnBurst(x, y)
	for i = 1, LIT.BurstCount do
		local angle = math.rad((i - 1) * 60)
		local dx = math.cos(angle) * LIT.BurstDistance
		local dy = math.sin(angle) * LIT.BurstDistance
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(8, 8)
		f.Position = UDim2.fromOffset(x - 4, y - 4)
		f.BackgroundColor3 = BURST_COLORS[((i - 1) % 3) + 1]
		f.BorderSizePixel = 0
		f.ZIndex = 4
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = f
		f.Parent = Arena
		local tween = TweenService:Create(f, TweenInfo.new(LIT.BurstTime, Enum.EasingStyle.Linear), {
			Position = UDim2.fromOffset(x - 4 + dx, y - 4 + dy),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			f:Destroy()
		end)
	end
end

local function spawnAfterimages()
	local center = nil
	if snapshot ~= nil and snapshot.player ~= nil then
		center = Vector2.new(snapshot.player.x, snapshot.player.y)
	end
	if center == nil then
		return
	end
	local dir = lastMove
	if dir.Magnitude < 0.1 then
		dir = Vector2.new(0, 1)
	end
	for i = 1, LIT.GhostCount do
		local pos = center - dir * (LIT.GhostStep * i)
		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.fromOffset(LIT.PlayerSize, LIT.PlayerSize)
		ghost.Position = UDim2.fromOffset(pos.X - LIT.PlayerSize / 2, pos.Y - LIT.PlayerSize / 2)
		ghost.BackgroundColor3 = Colors.PLAYER
		ghost.BackgroundTransparency = 0.55
		ghost.BorderSizePixel = 0
		ghost.Rotation = 45
		ghost.ZIndex = 3
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, LIT.BodyCorner)
		c.Parent = ghost
		ghost.Parent = Arena
		local tween = TweenService:Create(ghost, TweenInfo.new(LIT.GhostTime, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			ghost:Destroy()
		end)
	end
end

local function sendInput(move, target: any)
	lastSentMove = move
	inputTimer = 0
	-- Touch mode also sends the target: the server moves toward it and
	-- stops exactly on arrival. Keyboard mode sends no target, so the
	-- server uses the move vector as before.
	local payload = { type = "Input", mx = move.X, my = move.Y }
	if target ~= nil then
		payload.tx = target.X
		payload.ty = target.Y
	end
	PlayerActionEvent:FireServer(payload)
end

-- Convert a touch screen position to DESIGN arena coords. Same math as the
-- v2 aim conversion: divide by the Arena's scale (AbsoluteSize / design
-- size). No inset subtraction: the GUI ignores the inset
-- (IgnoreGuiInset=true), so touch and GUI share the screen origin.
-- Returns nil until the Arena has been laid out (zero-size guard).
local function touchToArena(position)
	if Arena.AbsoluteSize.X <= 0 or Arena.AbsoluteSize.Y <= 0 then
		return nil
	end
	local scaleX = Arena.AbsoluteSize.X / LIT.ArenaWidth
	local scaleY = Arena.AbsoluteSize.Y / LIT.ArenaHeight
	if scaleX <= 0 or scaleY <= 0 then
		return nil
	end
	local x = (position.X - Arena.AbsolutePosition.X) / scaleX
	local y = (position.Y - Arena.AbsolutePosition.Y) / scaleY
	return Vector2.new(x, y)
end

local function clampTarget(target)
	return Vector2.new(math.clamp(target.X, LIT.ClampMin, LIT.ClampMaxX), math.clamp(target.Y, LIT.ClampMin, LIT.ClampMaxY))
end

local function pointInArena(position)
	local origin = Arena.AbsolutePosition
	local size = Arena.AbsoluteSize
	return position.X >= origin.X and position.X <= origin.X + size.X and position.Y >= origin.Y and position.Y <= origin.Y + size.Y
end

local function pollInput(dt)
	if snapshot == nil or snapshot.phase ~= "PLAYING" then
		return
	end
	local move = Vector2.zero
	local usingTouch = false
	if touchTarget ~= nil and snapshot.player ~= nil then
		usingTouch = true
		local delta = touchTarget - Vector2.new(snapshot.player.x, snapshot.player.y)
		if delta.Magnitude > LIT.TouchDeadZone then
			move = delta.Unit
		end
	else
		local mx, my = 0, 0
		for _, key in ipairs({
			{ Enum.KeyCode.W, 0, -1 }, { Enum.KeyCode.S, 0, 1 },
			{ Enum.KeyCode.A, -1, 0 }, { Enum.KeyCode.D, 1, 0 },
			{ Enum.KeyCode.Up, 0, -1 }, { Enum.KeyCode.Down, 0, 1 },
			{ Enum.KeyCode.Left, -1, 0 }, { Enum.KeyCode.Right, 1, 0 },
		}) do
			if UserInputService:IsKeyDown(key[1]) then
				mx = mx + key[2]
				my = my + key[3]
			end
		end
		move = Vector2.new(mx, my)
		if move.Magnitude > 1 then
			move = move.Unit
		end
	end
	lastMove = move
	-- Jitter gate: while dragging, skip the resend when the target barely
	-- moved (< 6 design px since the last sent input) and the direction is
	-- unchanged. A changed direction (e.g. arriving at the target) still sends.
	if usingTouch and lastSentTarget ~= nil and not targetDirty and move == lastSentMove and (touchTarget - lastSentTarget).Magnitude < LIT.JitterPx then
		return
	end
	inputTimer = inputTimer + dt
	if move ~= lastSentMove or inputTimer >= 1 / LIT.InputHz then
		if usingTouch then
			lastSentTarget = touchTarget
		end
		sendInput(move, usingTouch and touchTarget or nil)
		targetDirty = false
	end
end

local function onDash()
	if snapshot == nil or snapshot.phase ~= "PLAYING" then
		return
	end
	-- No client-side cooldown: the server validates dash readiness.
	PlayerActionEvent:FireServer({ type = "Dash" })
end

local function onStateSnapshot(snap)
	-- New run (or run over): drop any drag held over from the old run,
	-- or pollInput would re-send its stale target into the fresh run.
	-- WIN/LOSE/MENU end the run too; WAVE_CLEAR does NOT clear, so a
	-- finger held through the intermission keeps its drag.
	if snap.runId ~= nil and snap.runId ~= lastRunId then
		lastRunId = snap.runId
		touchInput = nil
		touchTarget = nil
		lastSentTarget = nil
		lastAcceptedFinger = nil
		targetDirty = false
	end
	if (snap.phase == "WIN" or snap.phase == "LOSE" or snap.phase == "MENU") and lastPhase ~= snap.phase then
		touchInput = nil
		touchTarget = nil
		lastSentTarget = nil
		lastAcceptedFinger = nil
		targetDirty = false
	end
	-- Wave-clear resend: the server clears its touch target at clearWave,
	-- but this client keeps lastSentTarget, so the jitter gate in pollInput
	-- would swallow a held drag until the finger moves >= 6 px (the gate
	-- returns before inputTimer can accumulate). Reset only the sent
	-- baseline — not the drag itself — so the held target is re-sent on
	-- the first PLAYING tick of the new wave.
	if lastPhase == "WAVE_CLEAR" and snap.phase == "PLAYING" then
		lastSentTarget = nil
		inputTimer = 1 / LIT.InputHz
	end
	lastPhase = snap.phase
	snapshot = snap
	renderWorld(snap)
	if snap.events ~= nil then
		for _, event in ipairs(snap.events) do
			if event.type == "kill" then
				spawnBurst(event.x, event.y)
				showScorePopup(event.x, event.y, event.text, Colors.TITLE_GOLD)
			elseif event.type == "pickup" then
				showScorePopup(event.x, event.y, event.text, Colors.TITLE_GOLD)
			elseif event.type == "damage" then
				flashPlayer()
				if snapshot.player ~= nil and event.x ~= nil and event.y ~= nil then
					local dir = Vector2.new(snapshot.player.x - event.x, snapshot.player.y - event.y)
					if dir.Magnitude > 0.01 then
						recoilOffset = dir.Unit * LIT.RecoilDistance
					else
						recoilOffset = Vector2.new(0, LIT.RecoilDistance)
					end
					recoilTimer = LIT.RecoilTime
				end
			elseif event.type == "dash" then
				spawnAfterimages()
			elseif event.type == "CLOSE!" then
				showScorePopup(event.x, event.y, event.text, Colors.TITLE_GOLD)
			elseif event.type == "DANGER!" then
				showScorePopup(event.x, event.y, event.text, Colors.DAMAGE_RED)
			end
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	-- Ignore input already consumed by another UI (e.g. a menu button or
	-- a focused text box): R must not restart a run while typing, and a
	-- tap on a button must not also start a drag.
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		if touchInput ~= nil then
			return
		end
		-- Arena-rect gating: a drag only starts when the touch begins INSIDE
		-- the Arena. The DASH button sits outside the arena (bottom-right of
		-- the screen, in the control strip), so its taps never start a drag,
		-- and drags never steal button taps.
		if not pointInArena(input.Position) then
			return
		end
		local designPos = touchToArena(input.Position)
		if designPos == nil then
			return
		end
		-- RELATIVE drag, pure: the ship never snaps to the finger and the
		-- target never jumps to finger + offset. Touch-down alone never
		-- moves the ship: the target starts at the ship's current
		-- position, and each accepted finger move shifts the target by
		-- exactly that finger displacement (InputChanged below), so the
		-- ship follows the finger 1:1 from where it was touched.
		local shipPos = designPos
		if snapshot ~= nil and snapshot.player ~= nil then
			shipPos = Vector2.new(snapshot.player.x, snapshot.player.y)
		end
		touchInput = input
		-- The touch-down position is also the jitter gate's baseline:
		-- the finger must move 6 px from here before the target moves.
		lastAcceptedFinger = designPos
		touchTarget = clampTarget(shipPos)
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onDash()
	elseif input.KeyCode == Enum.KeyCode.R then
		if snapshot ~= nil and (snapshot.phase == "PLAYING" or snapshot.phase == "WAVE_CLEAR" or snapshot.phase == "WIN" or snapshot.phase == "LOSE") then
			PlayerActionEvent:FireServer({ type = "Restart" })
		end
	elseif input.KeyCode == Enum.KeyCode.Return then
		if snapshot ~= nil and snapshot.phase == "MENU" then
			PlayerActionEvent:FireServer({ type = "Start" })
		end
		if snapshot ~= nil and (snapshot.phase == "WIN" or snapshot.phase == "LOSE") then
			PlayerActionEvent:FireServer({ type = "Restart" })
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if touchInput ~= nil and input == touchInput then
		-- Hold the last valid target when the finger leaves the arena.
		if pointInArena(input.Position) then
			local designPos = touchToArena(input.Position)
			if designPos ~= nil then
				-- Jitter gate on FINGER displacement, not on the target
				-- or the normalized move direction: ignore sub-6px
				-- finger wiggles so the target does not crawl.
				if lastAcceptedFinger == nil or (designPos - lastAcceptedFinger).Magnitude >= LIT.JitterPx then
					-- Pure relative drag: shift the target by the finger
					-- displacement itself, then re-baseline. No offset
					-- snap, so the first accepted move cannot teleport
					-- the ship away from where it was touched.
					if lastAcceptedFinger ~= nil and touchTarget ~= nil then
						touchTarget = clampTarget(touchTarget + (designPos - lastAcceptedFinger))
						targetDirty = true
					end
					lastAcceptedFinger = designPos
				end
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if touchInput ~= nil and input == touchInput then
		touchInput = nil
		touchTarget = nil
		lastSentTarget = nil
		lastAcceptedFinger = nil
		targetDirty = false
		sendInput(Vector2.zero, nil)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	pollInput(dt)
	updatePlayerFlash(dt)
	for frame in pairs(tracked) do
		lerpEntity(frame, dt)
	end
	updateRecoil(dt)
	updateFlame()
	updateTouchRing()
	for _, ring in pairs(gunnerRings) do
		ring.Rotation = ring.Rotation + dt * LIT.GunnerRingSpeed
	end
	for frame, speed in pairs(spinFrames) do
		frame.Rotation = frame.Rotation + dt * speed
	end
	for frame in pairs(chargingFrames) do
		if math.floor(tick() * 8) % 2 == 0 then
			frame.BorderColor3 = Colors.FLASH_YELLOW
		else
			frame.BorderColor3 = Colors.PLAYER_CORE
		end
	end
end)
GameStateEvent.OnClientEvent:Connect(onStateSnapshot)
