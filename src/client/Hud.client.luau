-- Hud builds every GUI element for NOVA STRIKE
-- It owns all screen text, banners, the vignette, and the overlays.
-- The Arena frame is exposed to PlayerController through _G.NovaStrikeArena:
-- LocalScripts cannot share locals, so Hud (which builds the Arena) sets the
-- global and PlayerController polls until it appears. PlayerController only
-- reads Arena.AbsolutePosition / AbsoluteSize for its touch math.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("NovaStrikeRemotes")
local GameStateEvent = remotes:WaitForChild("GameStateEvent")
local PlayerActionEvent = remotes:WaitForChild("PlayerActionEvent")

-- Fixed design numbers for NOVA STRIKE (mirrors the shared Config).
-- All design coordinates are 1280x720-based and scaled by the single UIScale.
local Colors = {
	SCREEN_BG = Color3.fromRGB(8, 10, 24),
	ARENA_BG = Color3.fromRGB(16, 20, 44),
	ARENA_BORDER = Color3.fromRGB(0, 229, 255),
	PLAYER = Color3.fromRGB(0, 229, 255),
	DRONE = Color3.fromRGB(255, 64, 160),
	WEAVER = Color3.fromRGB(255, 150, 40),
	GUNNER = Color3.fromRGB(178, 102, 255),
	BOSS = Color3.fromRGB(255, 60, 60),
	PHASE2 = Color3.fromRGB(255, 150, 40),
	PHASE3 = Color3.fromRGB(255, 64, 160),
	BULLET = Color3.fromRGB(180, 245, 255),
	ENEMY_BOLT = Color3.fromRGB(255, 120, 60),
	POWERUP = Color3.fromRGB(255, 214, 64),
	HUD_BG = Color3.fromRGB(18, 22, 48),
	HUD_TEXT = Color3.fromRGB(235, 240, 255),
	HUD_DIM = Color3.fromRGB(150, 160, 200),
	HEART_FULL = Color3.fromRGB(255, 77, 109),
	HEART_EMPTY = Color3.fromRGB(60, 60, 90),
	BUTTON_BG = Color3.fromRGB(0, 180, 220),
	BUTTON_HOVER = Color3.fromRGB(0, 200, 240),
	BUTTON_TEXT = Color3.fromRGB(255, 255, 255),
	TITLE_GOLD = Color3.fromRGB(255, 214, 64),
	TITLE_RED = Color3.fromRGB(255, 77, 77),
	DAMAGE_RED = Color3.fromRGB(255, 40, 40),
	STAR = Color3.fromRGB(255, 255, 255),
}
local Layout = {
	ArenaWidth = 640,
	ArenaHeight = 480,
	ArenaY = 120,
	ArenaBorder = 3,
	HudWidth = 640,
	HudHeight = 44,
	HudY = 12,
	HintY = 612,
	HintHeight = 28,
	BannerWidth = 460,
	BannerHeight = 110,
	BannerCenterY = 360,
	BossBarY = 84,
	BossBarHeight = 16,
	PowerupY = 104,
	OverlayTransparency = 0.12,
	TotalWaves = 5,
	MaxHearts = 3,
}
-- Design values with no Config field, kept in two tables
local LIT = {
	HudCorner = 10,
	ArenaCorner = 6,
	BannerCorner = 12,
	HudTextSize = 18,
	HeartTextSize = 26,
	HintTextSize = 16,
	BannerTitleSize = 44,
	BannerSubSize = 20,
	BannerTitleY = 10,
	BannerTitleHeight = 60,
	BannerSubY = 66,
	BannerSubHeight = 34,
	DamageFlashTransparency = 0.55,
	DamageFlashSeconds = 0.35,
	PowerupTextSize = 16,
	ButtonCorner = 12,
	DashButtonSize = 96,
	DashButtonTextSize = 20,
}
-- Menu block: every Y below is the CENTER of its line (design coords).
local MENU = {
	Width = 760,
	TitleCenterY = 170,
	TitleHeight = 64,
	TitleSize = 56,
	SubCenterY = 228,
	SubHeight = 28,
	SubSize = 20,
	HowToKeyboardCenterY = 272,
	HowToTouchCenterY = 298,
	HowToHeight = 22,
	HowToSize = 18,
	NewCenterY = 336,
	NewHeight = 24,
	NewSize = 16,
	ButtonCenterY = 440,
	ButtonWidth = 240,
	ButtonHeight = 56,
	ButtonTextSize = 28,
	BestCenterY = 510,
	BestHeight = 22,
	BestSize = 18,
	StatsCenterY = 336,
	StatsHeight = 24,
	StatsSize = 18,
}
local HEART_OFFSETS = { 16, 48, 80 }
-- Deterministic starfield: 40 literal {x, y, size} pairs inside the 640x480
-- arena. No math.random at build time, so screenshots are identical every run.
local STARS = {
	{ 23, 41, 2 }, { 87, 112, 1 }, { 154, 67, 2 }, { 203, 189, 1 }, { 268, 34, 3 },
	{ 312, 98, 1 }, { 359, 210, 2 }, { 402, 55, 1 }, { 455, 143, 2 }, { 501, 76, 1 },
	{ 556, 201, 2 }, { 601, 44, 1 }, { 48, 233, 2 }, { 121, 301, 1 }, { 178, 265, 3 },
	{ 229, 342, 1 }, { 291, 278, 2 }, { 344, 359, 1 }, { 396, 294, 2 }, { 448, 371, 1 },
	{ 503, 318, 3 }, { 549, 402, 1 }, { 612, 287, 2 }, { 67, 421, 1 }, { 134, 448, 2 },
	{ 199, 389, 1 }, { 257, 455, 2 }, { 318, 412, 1 }, { 371, 467, 2 }, { 424, 428, 1 },
	{ 481, 461, 3 }, { 530, 395, 1 }, { 588, 443, 2 }, { 15, 150, 1 }, { 633, 170, 2 },
	{ 95, 18, 1 }, { 470, 12, 2 }, { 210, 470, 1 }, { 585, 250, 1 }, { 330, 160, 2 },
}

local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local Gui, Root, Arena, HudBar, ScoreLabel, WaveLabel, DashLabel, DashDot, HintBar, Banner, BannerTitle, BannerSub, Vignette = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
local StreakLabel, ModLabel, PowerupLabel, BossBar, BossFill, BossPhaseLabel, DashButton = nil, nil, nil, nil, nil, nil, nil
local starDrift = {}
local shakeTimer, shakeMag = 0, 0
local lastMult = 1
local Hearts = {}
local MenuOverlay, BestLabel, WinOverlay, WinSub, WinStats, LoseOverlay, LoseSub, LoseStats = nil, nil, nil, nil, nil, nil, nil, nil
local WinLines = {}
local HowToKeyboardLabel, HowToTouchLabel = nil, nil
local onStartPressed
local onRestartPressed
local lastStartAt, lastRestartAt = 0, 0

local function newFrame(parent, name, x, y, width, height, color, zIndex, cornerRadius)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Active = false
	frame.Parent = parent
	if cornerRadius ~= nil then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius)
		corner.Parent = frame
	end
	return frame
end

local function newLabel(parent, name, x, y, width, height, text, size, font, color, zIndex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.ZIndex = zIndex
	label.Active = false
	label.Parent = parent
	return label
end

local function playButtonHover(button)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Colors.BUTTON_HOVER
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Colors.BUTTON_BG
	end)
end

-- Full-screen frame: fills any viewport (scale 1,1). At 1280x720 identical
-- to the old fromOffset(1280, 720).
local function newFullFrame(parent, name, color, zIndex)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromScale(0, 0)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Active = false
	frame.Parent = parent
	return frame
end

-- Centered frame: X centered by scale (AnchorPoint 0.5,0), Y by the exact
-- same pixel offset as before. At 1280x720 identical to fromOffset(centerX, y).
local function newFrameC(parent, name, y, width, height, color, zIndex, cornerRadius)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Active = false
	frame.Parent = parent
	if cornerRadius ~= nil then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius)
		corner.Parent = frame
	end
	return frame
end

local function newLabelC(parent, name, y, width, height, text, size, font, color, zIndex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.ZIndex = zIndex
	label.Active = false
	label.Parent = parent
	return label
end

local function newButtonC(parent, name, y, width, height, text, size)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, y)
	button.Size = UDim2.fromOffset(width, height)
	button.BackgroundColor3 = Colors.BUTTON_BG
	button.BorderSizePixel = 0
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = size
	button.TextColor3 = Colors.BUTTON_TEXT
	button.ZIndex = 11
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, LIT.ButtonCorner)
	corner.Parent = button
	return button
end

-- UIScale: shrink the 1280x720 design to fit smaller viewports instead of
-- clipping. Scale = min(1, viewportX / 1280, viewportY / 720); at 1280x720
-- exactly 1 (identity). The zero-size guard keeps a pre-layout AbsoluteSize
-- from collapsing the GUI to scale 0.
local GuiScale = nil
local function updateGuiScale()
	if GuiScale == nil or Gui == nil then
		return
	end
	local size = Gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	GuiScale.Scale = math.min(1, size.X / 1280, size.Y / 720)
end

-- Start/Restart are fired from both MouseButton1Click and Activated so the
-- buttons answer on mouse and on touch. The 0.5s guard stops one physical
-- press from sending the action twice (both events fire for a mouse click).
onStartPressed = function()
	if tick() - lastStartAt < 0.5 then
		return
	end
	lastStartAt = tick()
	PlayerActionEvent:FireServer({ type = "Start" })
end
onRestartPressed = function()
	if tick() - lastRestartAt < 0.5 then
		return
	end
	lastRestartAt = tick()
	PlayerActionEvent:FireServer({ type = "Restart" })
end

local function buildArena()
	Arena = newFrameC(Root, "Arena", Layout.ArenaY, Layout.ArenaWidth, Layout.ArenaHeight, Colors.ARENA_BG, 2, LIT.ArenaCorner)
	Arena.BorderColor3 = Colors.ARENA_BORDER
	Arena.BorderSizePixel = Layout.ArenaBorder
	Arena.ClipsDescendants = true
	-- Exposed to PlayerController via the _G bridge (see header comment).
	_G.NovaStrikeArena = Arena
	-- 3 large translucent nebulae (soft purple/blue, deep-space backdrop).
	local nebulae = {
		{ 40, 60, 220, 150, Color3.fromRGB(120, 80, 200), 60 },
		{ 400, 280, 200, 130, Color3.fromRGB(60, 110, 220), 50 },
		{ 250, 170, 160, 100, Color3.fromRGB(150, 90, 220), 40 },
	}
	for _, n in ipairs(nebulae) do
		local neb = Instance.new("Frame")
		neb.Name = "Nebula"
		neb.Position = UDim2.fromOffset(n[1], n[2])
		neb.Size = UDim2.fromOffset(n[3], n[4])
		neb.BackgroundColor3 = n[5]
		neb.BackgroundTransparency = 0.87
		neb.BorderSizePixel = 0
		neb.ZIndex = 1
		local nebCorner = Instance.new("UICorner")
		nebCorner.CornerRadius = UDim.new(0, n[6])
		nebCorner.Parent = neb
		neb.Parent = Arena
	end
	-- Faint grid: thin lines every 80px at high transparency.
	for gx = 80, 560, 80 do
		local line = Instance.new("Frame")
		line.Name = "GridV"
		line.Position = UDim2.fromOffset(gx, 0)
		line.Size = UDim2.fromOffset(1, Layout.ArenaHeight)
		line.BackgroundColor3 = Color3.fromRGB(90, 110, 170)
		line.BackgroundTransparency = 0.92
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = Arena
	end
	for gy = 80, 400, 80 do
		local line = Instance.new("Frame")
		line.Name = "GridH"
		line.Position = UDim2.fromOffset(0, gy)
		line.Size = UDim2.fromOffset(Layout.ArenaWidth, 1)
		line.BackgroundColor3 = Color3.fromRGB(90, 110, 170)
		line.BackgroundTransparency = 0.92
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = Arena
	end
	-- Parallax starfield: TWO layers drifting down at different speeds and
	-- wrapping. Initial positions come from the deterministic STARS table
	-- (no math.random at build); layer A (first 24) drifts at 12 px/s,
	-- layer B (last 16) at 30 px/s.
	for i, star in ipairs(STARS) do
		local speed = 12
		if i > 24 then
			speed = 30
		end
		local starFrame = Instance.new("Frame")
		starFrame.Name = "Star" .. tostring(i)
		starFrame.Position = UDim2.fromOffset(star[1], star[2])
		starFrame.Size = UDim2.fromOffset(star[3], star[3])
		if i % 2 == 0 then
			starFrame.BackgroundColor3 = Colors.STAR
		else
			starFrame.BackgroundColor3 = Colors.HUD_DIM
		end
		starFrame.BorderSizePixel = 0
		starFrame.ZIndex = 2
		starFrame.Parent = Arena
		table.insert(starDrift, { frame = starFrame, speed = speed, x = star[1], y = star[2] })
	end
end

local function driftStars(dt)
	for _, s in ipairs(starDrift) do
		s.y = s.y + s.speed * dt
		if s.y > Layout.ArenaHeight then
			s.y = s.y - Layout.ArenaHeight
		end
		s.frame.Position = UDim2.fromOffset(s.x, math.floor(s.y))
	end
end

local function buildHud()
	Gui = Instance.new("ScreenGui")
	Gui.Name = "NovaStrikeGui"
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	Gui.Parent = PlayerGui
	-- Full-screen backdrop under the ScreenGui itself (never scaled by
	-- the Root UIScale): on viewports wider than 16:9 the centered Root
	-- left the baseplate sky visible at the edges. ZIndex 1, behind all.
	local Background = newFullFrame(Gui, "Background", Colors.SCREEN_BG, 1)
	-- Static backdrop stars (deterministic fromScale spots, no random):
	-- visible only outside the arena, which covers them (ZIndex 2).
	local bgStars = {
		{ 0.02, 0.10, 2 }, { 0.05, 0.55, 3 }, { 0.07, 0.85, 2 }, { 0.10, 0.30, 2 },
		{ 0.15, 0.70, 3 }, { 0.25, 0.20, 2 }, { 0.35, 0.60, 2 }, { 0.45, 0.15, 3 },
		{ 0.55, 0.80, 2 }, { 0.65, 0.35, 2 }, { 0.75, 0.65, 3 }, { 0.85, 0.25, 2 },
		{ 0.90, 0.75, 2 }, { 0.93, 0.40, 3 }, { 0.96, 0.90, 2 }, { 0.98, 0.12, 2 },
		{ 0.30, 0.90, 2 }, { 0.60, 0.05, 2 }, { 0.80, 0.50, 3 }, { 0.40, 0.45, 2 },
	}
	for i, s in ipairs(bgStars) do
		local starFrame = Instance.new("Frame")
		starFrame.Name = "BgStar" .. tostring(i)
		starFrame.Position = UDim2.fromScale(s[1], s[2])
		starFrame.Size = UDim2.fromOffset(s[3], s[3])
		if i % 2 == 0 then starFrame.BackgroundColor3 = Colors.STAR else starFrame.BackgroundColor3 = Colors.HUD_DIM end
		starFrame.BorderSizePixel = 0
		starFrame.ZIndex = 1
		starFrame.Parent = Background
	end
	-- Centered root: ALL UI lives under this one 1280x720 design frame,
	-- centered in the viewport with the UIScale applied to it. At 1280x720
	-- this is pixel-identical to building directly under the ScreenGui; on
	-- 844x390 or 1024x768 the design centers instead of leaving dead space
	-- on one side. The Arena's runtime AbsolutePosition/AbsoluteSize still
	-- drive the touch math, so nothing else changes.
	Root = Instance.new("Frame")
	Root.Name = "Root"
	Root.AnchorPoint = Vector2.new(0.5, 0.5)
	Root.Position = UDim2.fromScale(0.5, 0.5)
	Root.Size = UDim2.fromOffset(1280, 720)
	Root.BackgroundTransparency = 1
	Root.BorderSizePixel = 0
	Root.Active = false
	Root.Parent = Gui
	GuiScale = Instance.new("UIScale")
	GuiScale.Parent = Root
	Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGuiScale)
	updateGuiScale()
	buildArena()

	HudBar = newFrameC(Root, "HudBar", Layout.HudY, Layout.HudWidth, Layout.HudHeight, Colors.HUD_BG, 5, LIT.HudCorner)
	-- HUD bar row (bar-local x, all left-aligned, 18px): hearts 16..112,
	-- score x120 (worst case "SCORE 12,400" ends x263), wave x290 (worst
	-- case "WAVE 5/5 · 03:45" ends x463), dash label x472, dash dot x548.
	-- Measured with DejaVu Bold (wider than Gotham, so a conservative
	-- bound): score/wave gap 27px, wave/dash gap 9px, dash-text/dot gap
	-- 6px, and even a 6-digit "SCORE 123,456" ends x276 < 290. The old
	-- 22px layout overlapped: "SCORE 4,820" ended x288 past WaveLabel x216.
	ScoreLabel = newLabel(HudBar, "ScoreLabel", 120, 0, 160, Layout.HudHeight, "SCORE 0", LIT.HudTextSize, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	ScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	WaveLabel = newLabel(HudBar, "WaveLabel", 290, 0, 180, Layout.HudHeight, "WAVE 1/5", LIT.HudTextSize, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	WaveLabel.TextXAlignment = Enum.TextXAlignment.Left
	DashLabel = newLabel(HudBar, "DashLabel", 472, 0, 72, 44, "DASH", 16, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	DashLabel.TextXAlignment = Enum.TextXAlignment.Left
	DashDot = newFrame(HudBar, "DashDot", 548, 15, 14, 14, Colors.HUD_DIM, 5, 7)
	for i = 1, Layout.MaxHearts do
		Hearts[i] = newLabel(HudBar, "Heart" .. i, HEART_OFFSETS[i], 0, 32, Layout.HudHeight, "♥", LIT.HeartTextSize, Enum.Font.GothamBold, Colors.HEART_FULL, 5)
	end
	-- Streak label is UPPER-CENTER (full bar width, centered text) on the
	-- row below the bar; the modifier label sits at the right of the same
	-- row. Both live under HudBar so they stay glued to its edges on any
	-- viewport; at 1280x720 their absolute position is y 60..80, BELOW
	-- the bar (ends y 56) — proven non-overlapping, never inside the bar row.
	StreakLabel = newLabel(HudBar, "StreakLabel", 0, Layout.HudHeight + 4, Layout.HudWidth, 20, "", 16, Enum.Font.GothamBold, Colors.TITLE_GOLD, 5)
	StreakLabel.TextXAlignment = Enum.TextXAlignment.Center
	StreakLabel.Visible = false
	ModLabel = newLabel(HudBar, "ModLabel", 440, Layout.HudHeight + 4, 200, 20, "", 16, Enum.Font.Gotham, Colors.HUD_DIM, 5)
	ModLabel.TextXAlignment = Enum.TextXAlignment.Right
	ModLabel.Visible = false

	-- Boss HP bar (visible only while a boss is alive) with the phase
	-- indicator beside it, and the active power-up line below it.
	BossBar = newFrameC(Root, "BossBar", Layout.BossBarY, Layout.HudWidth, Layout.BossBarHeight, Colors.HUD_BG, 5, 8)
	BossBar.Visible = false
	BossFill = newFrame(BossBar, "BossFill", 0, 0, 0, Layout.BossBarHeight, Colors.BOSS, 5, 8)
	BossPhaseLabel = newLabel(Root, "BossPhaseLabel", 968, Layout.BossBarY, 200, Layout.BossBarHeight, "", 14, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	BossPhaseLabel.TextXAlignment = Enum.TextXAlignment.Left
	BossPhaseLabel.Visible = false
	PowerupLabel = newLabelC(Root, "PowerupLabel", Layout.PowerupY, Layout.HudWidth, 20, "", LIT.PowerupTextSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 5)
	PowerupLabel.Visible = false

	-- Keyboard text wins when both a keyboard and touch are present.
	local hintText = "DRAG — FLY · TAP DASH — DASH · AUTO-FIRE ON"
	if UserInputService.KeyboardEnabled then
		hintText = "WASD / ARROWS — MOVE · SHIFT — DASH · R — RESTART · AUTO-FIRE ON"
	end
	HintBar = newLabelC(Root, "HintBar", Layout.HintY, Layout.HudWidth, Layout.HintHeight, hintText, LIT.HintTextSize, Enum.Font.Gotham, Colors.HUD_DIM, 5)
	HintBar.Visible = false
	HudBar.Visible = false

	Banner = newFrameC(Root, "Banner", Layout.BannerCenterY - Layout.BannerHeight / 2, Layout.BannerWidth, Layout.BannerHeight, Colors.HUD_BG, 8, LIT.BannerCorner)
	Banner.Visible = false
	BannerTitle = newLabel(Banner, "BannerTitle", 0, LIT.BannerTitleY, Layout.BannerWidth, LIT.BannerTitleHeight, "", LIT.BannerTitleSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 8)
	BannerSub = newLabel(Banner, "BannerSub", 0, LIT.BannerSubY, Layout.BannerWidth, LIT.BannerSubHeight, "", LIT.BannerSubSize, Enum.Font.Gotham, Colors.HUD_TEXT, 8)
	Vignette = newFullFrame(Root, "Vignette", Colors.DAMAGE_RED, 9)
	Vignette.BackgroundTransparency = 1

	-- Touch DASH button: bottom-right of the screen, OUTSIDE the arena, so
	-- arena-rect touch-drag gating in PlayerController never mistakes a dash
	-- tap for a drag. Visible only on touch devices.
	DashButton = Instance.new("TextButton")
	DashButton.Name = "DashButton"
	DashButton.AnchorPoint = Vector2.new(1, 1)
	DashButton.Position = UDim2.new(1, -20, 1, -20)
	DashButton.Size = UDim2.fromOffset(LIT.DashButtonSize, LIT.DashButtonSize)
	DashButton.BackgroundColor3 = Colors.BUTTON_BG
	DashButton.BorderSizePixel = 0
	DashButton.Text = "DASH"
	DashButton.Font = Enum.Font.GothamBold
	DashButton.TextSize = LIT.DashButtonTextSize
	DashButton.TextColor3 = Colors.BUTTON_TEXT
	DashButton.ZIndex = 12
	DashButton.Visible = UserInputService.TouchEnabled
	DashButton.Parent = Root
	local dashCorner = Instance.new("UICorner")
	dashCorner.CornerRadius = UDim.new(0, 48)
	dashCorner.Parent = DashButton
	DashButton.Activated:Connect(function()
		PlayerActionEvent:FireServer({ type = "Dash" })
	end)
end

local function buildMenu()
	local block = MENU
	MenuOverlay = newFullFrame(Root, "MenuOverlay", Colors.SCREEN_BG, 10)
	MenuOverlay.BackgroundTransparency = Layout.OverlayTransparency
	newLabelC(MenuOverlay, "MenuTitle", block.TitleCenterY - block.TitleHeight / 2, block.Width, block.TitleHeight, "NOVA STRIKE", block.TitleSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 11)
	newLabelC(MenuOverlay, "MenuSub", block.SubCenterY - block.SubHeight / 2, block.Width, block.SubHeight, "Blast the swarm. Survive 5 waves. Beat the cruiser.", block.SubSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	HowToKeyboardLabel = newLabelC(MenuOverlay, "MenuHowToKeyboard", block.HowToKeyboardCenterY - block.HowToHeight / 2, block.Width, block.HowToHeight, "WASD / ARROWS — MOVE · SHIFT — DASH · AUTO-FIRE ON", block.HowToSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	HowToKeyboardLabel.Visible = UserInputService.KeyboardEnabled
	HowToTouchLabel = newLabelC(MenuOverlay, "MenuHowToTouch", block.HowToTouchCenterY - block.HowToHeight / 2, block.Width, block.HowToHeight, "TOUCH — DRAG TO FLY · TAP DASH · AUTO-FIRE ON", block.HowToSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	HowToTouchLabel.Visible = UserInputService.TouchEnabled
	newLabelC(MenuOverlay, "MenuNew", block.NewCenterY - block.NewHeight / 2, block.Width, block.NewHeight, "NEW: BOSS CRUISER · POWER-UPS · KILL STREAKS ×3", block.NewSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 11)
	local button = newButtonC(MenuOverlay, "StartButton", block.ButtonCenterY - block.ButtonHeight / 2, block.ButtonWidth, block.ButtonHeight, "LAUNCH", block.ButtonTextSize)
	playButtonHover(button)
	button.MouseButton1Click:Connect(onStartPressed)
	button.Activated:Connect(onStartPressed)
	BestLabel = newLabelC(MenuOverlay, "BestLabel", block.BestCenterY - block.BestHeight / 2, block.Width, block.BestHeight, "BEST SCORE: 0", block.BestSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
end

local function buildEndOverlay(name, titleText, titleColor, buttonName, buttonText, buttonCenterY)
	local block = MENU
	local overlay = newFullFrame(Root, name .. "Overlay", Colors.SCREEN_BG, 10)
	overlay.BackgroundTransparency = Layout.OverlayTransparency
	overlay.Visible = false
	newLabelC(overlay, name .. "Title", block.TitleCenterY - block.TitleHeight / 2, block.Width, block.TitleHeight, titleText, block.TitleSize, Enum.Font.GothamBold, titleColor, 11)
	local sub = newLabelC(overlay, name .. "Sub", block.SubCenterY - block.SubHeight / 2, block.Width, block.SubHeight, "", block.SubSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	local stats = newLabelC(overlay, name .. "Stats", block.StatsCenterY - block.StatsHeight / 2, block.Width, block.StatsHeight, "", block.StatsSize, Enum.Font.Gotham, Colors.HUD_TEXT, 11)
	local button = newButtonC(overlay, buttonName, (buttonCenterY or block.ButtonCenterY) - block.ButtonHeight / 2, block.ButtonWidth, block.ButtonHeight, buttonText, block.ButtonTextSize)
	playButtonHover(button)
	button.MouseButton1Click:Connect(onRestartPressed)
	button.Activated:Connect(onRestartPressed)
	return overlay, sub, stats
end

local function buildEndScreens()
	-- Win button center y542: the breakdown block runs y292..482, so the
	-- button sits below it (top y514), not at the menu's y440.
	WinOverlay, WinSub, WinStats = buildEndOverlay("Win", "YOU WIN!", Colors.TITLE_GOLD, "PlayAgainButton", "PLAY AGAIN", 542)
	WinSub.Text = "The cruiser is destroyed. Nova secured."
	-- The single-line stats label would sit inside the breakdown block
	-- (y336), so it stays hidden on the win screen; the seven breakdown
	-- lines below replace it. Each entry: {topY, height, size, font, color}.
	WinStats.Visible = false
	local defs = {
		{ 281, 22, 20, Enum.Font.Gotham, Colors.HUD_TEXT }, -- KILL POINTS, center y292
		{ 311, 22, 20, Enum.Font.Gotham, Colors.HUD_TEXT }, -- WAVE BONUSES, center y322
		{ 341, 22, 20, Enum.Font.Gotham, Colors.HUD_TEXT }, -- DANGER BONUS, center y352
		{ 371, 22, 20, Enum.Font.Gotham, Colors.HUD_TEXT }, -- PICKUP BONUS, center y382
		{ 404, 28, 24, Enum.Font.GothamBold, Colors.TITLE_GOLD }, -- TOTAL, center y418
		{ 443, 22, 20, Enum.Font.Gotham, Colors.HUD_TEXT }, -- TIME, center y454
		{ 471, 22, 20, Enum.Font.GothamBold, Colors.TITLE_GOLD }, -- BEST, center y482
	}
	for i, def in ipairs(defs) do
		WinLines[i] = newLabelC(WinOverlay, "WinLine" .. i, def[1], MENU.Width, def[2], "", def[3], def[4], def[5], 11)
	end
	LoseOverlay, LoseSub, LoseStats = buildEndOverlay("Lose", "GAME OVER", Colors.TITLE_RED, "RetryButton", "RETRY")
end

-- Thousands commas: 12400 -> "12,400". Every score display uses it, so the
-- game formats scores exactly as the dossier screenshots show.
local function formatNumber(n)
	local s = tostring(math.floor(n))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

local function formatTime(totalSeconds)
	local minutes = math.floor(totalSeconds / 60)
	local seconds = math.floor(totalSeconds % 60)
	return string.format("%02d:%02d", minutes, seconds)
end

local PHASE_ROMAN = { "I", "II", "III" }
local function phaseColor(phase)
	if phase == 2 or phase == "II" then
		return Colors.PHASE2
	end
	if phase == 3 or phase == "III" then
		return Colors.PHASE3
	end
	return Colors.BOSS
end
local function phaseRoman(phase)
	if type(phase) == "number" and PHASE_ROMAN[phase] ~= nil then
		return PHASE_ROMAN[phase]
	end
	return tostring(phase)
end

local function showWaveBanner(title, sub)
	BannerTitle.Text = title
	BannerSub.Text = sub
	Banner.Visible = true
end

local function hideBanner()
	Banner.Visible = false
end

local function showDamageFlash()
	Vignette.BackgroundTransparency = LIT.DamageFlashTransparency
	local tween = TweenService:Create(Vignette, TweenInfo.new(LIT.DamageFlashSeconds, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 })
	tween:Play()
end

-- Screen shake: offset the centered Root by a few px with decaying magnitude
-- for 0.25s on a damage event. Root's base position is (0.5, 0.5) scale.
local function triggerShake()
	shakeTimer = 0.25
	shakeMag = 6
end
local function updateShake(dt)
	if shakeTimer <= 0 then
		return
	end
	shakeTimer = shakeTimer - dt
	if shakeTimer <= 0 then
		Root.Position = UDim2.fromScale(0.5, 0.5)
		return
	end
	local k = shakeTimer / 0.25
	local dx = math.sin(tick() * 90) * shakeMag * k
	local dy = math.cos(tick() * 77) * shakeMag * k
	Root.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(dx, dy)
end

local function showMenu(best)
	MenuOverlay.Visible = true
	WinOverlay.Visible = false
	LoseOverlay.Visible = false
	BestLabel.Text = "BEST SCORE: " .. formatNumber(best)
end

local function showWin(snap)
	MenuOverlay.Visible = false
	WinOverlay.Visible = true
	LoseOverlay.Visible = false
	-- Component lines are live from the snapshot (server-tracked
	-- killPoints / waveBonuses / dangerBonus / pickupPoints). The
	-- verified achievable split of the 12,400 run is
	-- 8,050 + 3,750 + 600 + 0 = 12,400 (canonical run picks up no
	-- power-up). TOTAL / TIME / BEST come from the snapshot,
	-- comma-formatted like every other score display.
	WinLines[1].Text = "KILL POINTS  " .. formatNumber(snap.killPoints or 0)
	WinLines[2].Text = "WAVE BONUSES  " .. formatNumber(snap.waveBonuses or 0)
	WinLines[3].Text = "DANGER BONUS  " .. formatNumber(snap.dangerBonus or 0)
	WinLines[4].Text = "PICKUP BONUS  " .. formatNumber(snap.pickupPoints or 0)
	WinLines[5].Text = "TOTAL  " .. formatNumber(snap.score)
	WinLines[6].Text = "TIME  " .. formatTime(snap.time)
	local bestText = "BEST  " .. formatNumber(snap.best)
	if snap.score >= snap.best and snap.score > 0 then
		bestText = bestText .. "  * NEW BEST!"
	end
	WinLines[7].Text = bestText
end

local function showLose(snap)
	MenuOverlay.Visible = false
	WinOverlay.Visible = false
	LoseOverlay.Visible = true
	LoseSub.Text = string.format("The swarm got you on Wave %d", snap.wave)
	LoseStats.Text = "SCORE " .. formatNumber(snap.score) .. " · TIME " .. formatTime(snap.time) .. " · BEST " .. formatNumber(snap.best) .. " · WAVE " .. snap.wave .. "/" .. Layout.TotalWaves
end

local function updateHud(snap)
	local playing = snap.phase == "PLAYING" or snap.phase == "WAVE_CLEAR"
	local mult = 1
	if snap.mult ~= nil then
		mult = snap.mult
	end
	HudBar.Visible = playing
	HintBar.Visible = playing
	StreakLabel.Text = "STREAK ×" .. tostring(mult)
	StreakLabel.Visible = playing and mult >= 2
	if playing and mult > lastMult and mult >= 2 then
		-- Streak pulse: the label briefly grows ~4px on each increment.
		StreakLabel.TextSize = 20
		local pulse = TweenService:Create(StreakLabel, TweenInfo.new(0.15, Enum.EasingStyle.Linear), { TextSize = 16 })
		pulse:Play()
	end
	lastMult = mult
	if snap.modifier ~= nil then
		ModLabel.Text = "MODIFIER: " .. snap.modifier
	else
		ModLabel.Text = "MODIFIER: STANDARD"
	end
	ModLabel.Visible = playing and snap.modifier ~= nil and snap.modifier ~= "STANDARD"
	ScoreLabel.Text = "SCORE " .. formatNumber(snap.score)
	WaveLabel.Text = string.format("WAVE %d/%d · %s", snap.wave, Layout.TotalWaves, formatTime(snap.time))
	if snap.dashReady == true then
		DashDot.BackgroundColor3 = Colors.PLAYER
		DashLabel.Text = "DASH"
		DashButton.BackgroundTransparency = 0
	else
		DashDot.BackgroundColor3 = Colors.HUD_DIM
		-- No cooldown-seconds field exists in the snapshot contract, so the
		-- label shows the cooling state (not a seconds countdown) and the
		-- touch DASH button dims until the dash is ready again.
		DashLabel.Text = "DASH X"
		DashButton.BackgroundTransparency = 0.5
	end
	for i = 1, Layout.MaxHearts do
		if i <= snap.hearts then
			Hearts[i].TextColor3 = Colors.HEART_FULL
		else
			Hearts[i].TextColor3 = Colors.HEART_EMPTY
		end
	end
	-- Active power-up: snapshot carries powerup = {name = "Rapid", seconds = 5.2}
	-- or nil when none is active.
	local powerup = snap.powerup
	if playing and powerup ~= nil then
		if type(powerup) == "table" then
			PowerupLabel.Text = string.upper(tostring(powerup.name or "")) .. " " .. tostring(math.ceil(powerup.seconds or 0)) .. "s"
		elseif type(powerup) == "string" then
			PowerupLabel.Text = string.upper(powerup)
		end
		PowerupLabel.Visible = true
	else
		PowerupLabel.Visible = false
	end
	-- Boss HP bar: snapshot carries boss = {x, y, hp, maxHp} or nil.
	if snap.boss ~= nil then
		local maxHp = snap.boss.maxHp
		local ratio = 0
		if maxHp ~= nil and maxHp > 0 then
			ratio = math.clamp(snap.boss.hp / maxHp, 0, 1)
		end
		BossFill.Size = UDim2.fromOffset(Layout.HudWidth * ratio, Layout.BossBarHeight)
		BossFill.BackgroundColor3 = phaseColor(snap.boss.phase)
		BossPhaseLabel.Text = "BOSS — PHASE " .. phaseRoman(snap.boss.phase)
		BossPhaseLabel.Visible = true
		BossBar.Visible = true
	else
		BossBar.Visible = false
		BossPhaseLabel.Visible = false
	end
	if snap.phase == "MENU" then
		showMenu(snap.best)
	elseif snap.phase == "WIN" then
		showWin(snap)
	elseif snap.phase == "LOSE" then
		showLose(snap)
	else
		MenuOverlay.Visible = false
		WinOverlay.Visible = false
		LoseOverlay.Visible = false
	end
end

local function onStateSnapshot(snap)
	updateHud(snap)
	if snap.banner ~= nil then
		showWaveBanner(snap.banner.title, snap.banner.sub)
	else
		hideBanner()
	end
	if snap.events ~= nil then
		for _, event in ipairs(snap.events) do
			if event.type == "damage" then
				showDamageFlash()
				triggerShake()
			end
		end
	end
end

buildHud()
buildMenu()
buildEndScreens()
RunService.Heartbeat:Connect(function(dt)
	driftStars(dt)
	updateShake(dt)
end)
GameStateEvent.OnClientEvent:Connect(onStateSnapshot)
