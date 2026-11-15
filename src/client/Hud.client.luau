-- Hud builds every GUI element for EMBER ARENA from Config
-- It owns all screen text, banners, the vignette, and the overlays
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild(Config.RemotesFolder)
local GameStateEvent = remotes:WaitForChild(Config.GameStateEvent)
local PlayerActionEvent = remotes:WaitForChild(Config.PlayerActionEvent)
local Colors = Config.Colors
local Layout = Config.Layout
local Tuning = Config.Tuning
-- Design values with no Config field yet, kept in two tables
local LIT = { HudCorner = 10, ArenaCorner = 6, BannerCorner = 12, HudTextSize = 22,
	HeartTextSize = 26, HintTextSize = 16, BannerTitleSize = 44, BannerSubSize = 20,
	BannerTitleY = 10, BannerTitleHeight = 60, BannerSubY = 66, BannerSubHeight = 34,
	DamageFlashTransparency = 0.55 }
local TITLE = { Width = 700, TitleHeight = 90, TitleY = 270, SubHeight = 30, SubY = 330,
	LineHeight = 28, LineY = 378, ButtonY = 440, BestY = 528, TitleSize = 64, SubSize = 20,
	LineSize = 18, BestSize = 18, ButtonWidth = 260, ButtonHeight = 64, ButtonTextSize = 28, ButtonCorner = 12 }
local HEART_OFFSETS = { 528, 560, 592 }
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local Gui, HudBar, ScoreLabel, WaveLabel, DashDot, HintBar, Banner, BannerTitle, BannerSub, Vignette = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
local Hearts = {}
local MenuOverlay, BestLabel, WinOverlay, WinSub, WinStats, LoseOverlay, LoseSub, LoseStats = nil, nil, nil, nil, nil, nil, nil, nil
local onStartPressed
local onRestartPressed
local function newFrame(parent, name, x, y, width, height, color, zIndex, cornerRadius)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0; frame.ZIndex = zIndex; frame.Parent = parent
	if cornerRadius ~= nil then
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, cornerRadius); corner.Parent = frame
	end
	return frame
end
local function newLabel(parent, name, x, y, width, height, text, size, font, color, zIndex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1; label.Text = text
	label.Font = font; label.TextSize = size
	label.TextColor3 = color; label.ZIndex = zIndex; label.Parent = parent
	return label
end
local function newButton(parent, name, x, y, width, height, text, size)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(width, height)
	button.BackgroundColor3 = Colors.BUTTON_BG
	button.BorderSizePixel = 0; button.Text = text
	button.Font = Enum.Font.GothamBold; button.TextSize = size
	button.TextColor3 = Colors.BUTTON_TEXT; button.ZIndex = 11; button.Parent = parent
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, TITLE.ButtonCorner); corner.Parent = button
	return button
end
local function playButtonHover(button)
	button.MouseEnter:Connect(function() button.BackgroundColor3 = Colors.BUTTON_HOVER end)
	button.MouseLeave:Connect(function() button.BackgroundColor3 = Colors.BUTTON_BG end)
end
onStartPressed = function()
	PlayerActionEvent:FireServer({ type = "Start" })
end
onRestartPressed = function()
	PlayerActionEvent:FireServer({ type = "Restart" })
end
local function buildArena()
	newFrame(Gui, "Background", 0, 0, Layout.ScreenWidth, Layout.ScreenHeight, Colors.SCREEN_BG, 1, nil)
	local arenaFrame = newFrame(Gui, "Arena", Layout.ArenaX, Layout.ArenaY, Layout.ArenaWidth, Layout.ArenaHeight, Colors.ARENA_BG, 2, LIT.ArenaCorner)
	arenaFrame.BorderColor3 = Colors.ARENA_BORDER
	arenaFrame.BorderSizePixel = Layout.ArenaBorder
end
local function buildHud()
	Gui = Instance.new("ScreenGui")
	Gui.Name = "EmberArenaGui"
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	Gui.Parent = PlayerGui
	buildArena()
	HudBar = newFrame(Gui, "HudBar", Layout.HudX, Layout.HudY, Layout.HudWidth, Layout.HudHeight, Colors.HUD_BG, 5, LIT.HudCorner)
	ScoreLabel = newLabel(HudBar, "ScoreLabel", 16, 0, 190, Layout.HudHeight, "SCORE 0", LIT.HudTextSize, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	ScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	WaveLabel = newLabel(HudBar, "WaveLabel", 216, 0, 208, Layout.HudHeight, "WAVE 1/5", LIT.HudTextSize, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	newLabel(HudBar, "DashLabel", 432, 0, 48, 44, "DASH", 16, Enum.Font.GothamBold, Colors.HUD_TEXT, 5)
	DashDot = newFrame(HudBar, "DashDot", 484, 15, 14, 14, Colors.HUD_DIM, 5, 7)
	for i = 1, Config.MaxHearts do
		Hearts[i] = newLabel(HudBar, "Heart" .. i, HEART_OFFSETS[i], 0, 32, Layout.HudHeight, "♥", LIT.HeartTextSize, Enum.Font.GothamBold, Colors.HEART_FULL, 5)
	end
	HintBar = newLabel(Gui, "HintBar", Layout.HudX, Layout.HintY, Layout.HudWidth, Layout.HintHeight, "WASD / ARROWS — MOVE · CLICK — SHOOT · SHIFT — DASH · R — RESTART", LIT.HintTextSize, Enum.Font.Gotham, Colors.HUD_DIM, 5)
	Banner = newFrame(Gui, "Banner", Layout.BannerCenterX - Layout.BannerWidth / 2, Layout.BannerCenterY - Layout.BannerHeight / 2, Layout.BannerWidth, Layout.BannerHeight, Colors.HUD_BG, 8, LIT.BannerCorner)
	Banner.Visible = false
	BannerTitle = newLabel(Banner, "BannerTitle", 0, LIT.BannerTitleY, Layout.BannerWidth, LIT.BannerTitleHeight, "", LIT.BannerTitleSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 8)
	BannerSub = newLabel(Banner, "BannerSub", 0, LIT.BannerSubY, Layout.BannerWidth, LIT.BannerSubHeight, "", LIT.BannerSubSize, Enum.Font.Gotham, Colors.HUD_TEXT, 8)
	Vignette = newFrame(Gui, "Vignette", 0, 0, Layout.ScreenWidth, Layout.ScreenHeight, Colors.DAMAGE_RED, 9, nil)
	Vignette.BackgroundTransparency = 1
end
local function buildMenu()
	local block = TITLE
	local centerX = (Layout.ScreenWidth - block.Width) / 2
	MenuOverlay = newFrame(Gui, "MenuOverlay", 0, 0, Layout.ScreenWidth, Layout.ScreenHeight, Colors.SCREEN_BG, 10, nil)
	MenuOverlay.BackgroundTransparency = Layout.OverlayTransparency
	newLabel(MenuOverlay, "MenuTitle", centerX, block.TitleY - block.TitleHeight / 2, block.Width, block.TitleHeight, "EMBER ARENA", block.TitleSize, Enum.Font.GothamBold, Colors.TITLE_GOLD, 11)
	newLabel(MenuOverlay, "MenuSub", centerX, block.SubY - block.SubHeight / 2, block.Width, block.SubHeight, "Survive 5 waves of embers. Shoot, dash, collect orbs.", block.SubSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	newLabel(MenuOverlay, "MenuHowTo", centerX, block.LineY - block.LineHeight / 2, block.Width, block.LineHeight, "WASD — MOVE · CLICK — SHOOT · SHIFT — DASH", block.LineSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	local button = newButton(MenuOverlay, "StartButton", (Layout.ScreenWidth - block.ButtonWidth) / 2, block.ButtonY - block.ButtonHeight / 2, block.ButtonWidth, block.ButtonHeight, "▶  START GAME", block.ButtonTextSize)
	playButtonHover(button)
	button.MouseButton1Click:Connect(onStartPressed)
	BestLabel = newLabel(MenuOverlay, "BestLabel", centerX, block.BestY - block.LineHeight / 2, block.Width, block.LineHeight, "BEST SCORE: 0", block.BestSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
end
local function buildEndOverlay(name, titleText, titleColor, buttonName, buttonText)
	local block = TITLE
	local centerX = (Layout.ScreenWidth - block.Width) / 2
	local overlay = newFrame(Gui, name .. "Overlay", 0, 0, Layout.ScreenWidth, Layout.ScreenHeight, Colors.SCREEN_BG, 10, nil)
	overlay.BackgroundTransparency = Layout.OverlayTransparency
	overlay.Visible = false
	newLabel(overlay, name .. "Title", centerX, block.TitleY - block.TitleHeight / 2, block.Width, block.TitleHeight, titleText, block.TitleSize, Enum.Font.GothamBold, titleColor, 11)
	local sub = newLabel(overlay, name .. "Sub", centerX, block.SubY - block.SubHeight / 2, block.Width, block.SubHeight, "", block.SubSize, Enum.Font.Gotham, Colors.HUD_DIM, 11)
	local stats = newLabel(overlay, name .. "Stats", centerX, block.LineY - block.LineHeight / 2, block.Width, block.LineHeight, "", block.LineSize, Enum.Font.Gotham, Colors.HUD_TEXT, 11)
	local button = newButton(overlay, buttonName, (Layout.ScreenWidth - block.ButtonWidth) / 2, block.ButtonY - block.ButtonHeight / 2, block.ButtonWidth, block.ButtonHeight, buttonText, block.ButtonTextSize)
	playButtonHover(button)
	button.MouseButton1Click:Connect(onRestartPressed)
	return overlay, sub, stats
end
local function buildEndScreens()
	WinOverlay, WinSub, WinStats = buildEndOverlay("Win", "YOU WIN!", Colors.TITLE_GOLD, "PlayAgainButton", "↻  PLAY AGAIN")
	WinSub.Text = "All 5 waves cleared!"
	LoseOverlay, LoseSub, LoseStats = buildEndOverlay("Lose", "GAME OVER", Colors.TITLE_RED, "RetryButton", "↻  RETRY")
end
local function formatTime(totalSeconds)
	local minutes, seconds = math.floor(totalSeconds / 60), math.floor(totalSeconds % 60)
	return string.format("%02d:%02d", minutes, seconds)
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
	local tween = TweenService:Create(Vignette, TweenInfo.new(Tuning.DamageFlashSeconds, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }); tween:Play()
end
local function showMenu(best)
	MenuOverlay.Visible, WinOverlay.Visible, LoseOverlay.Visible = true, false, false
	BestLabel.Text = string.format("BEST SCORE: %d", best)
end
local function showWin(snap)
	MenuOverlay.Visible, WinOverlay.Visible, LoseOverlay.Visible = false, true, false
	WinStats.Text = string.format("SCORE %d · TIME %s · BEST %d", snap.score, formatTime(snap.time), snap.best)
end
local function showLose(snap)
	MenuOverlay.Visible, WinOverlay.Visible, LoseOverlay.Visible = false, false, true
	LoseSub.Text = string.format("The embers got you on Wave %d", snap.wave)
	LoseStats.Text = string.format("SCORE %d · TIME %s · BEST %d", snap.score, formatTime(snap.time), snap.best)
end
local function updateHud(snap)
	local playing = snap.phase == "PLAYING" or snap.phase == "WAVE_CLEAR"
	HudBar.Visible = playing
	HintBar.Visible = playing
	ScoreLabel.Text = string.format("SCORE %d", snap.score)
	WaveLabel.Text = string.format("WAVE %d/%d · %s", snap.wave, Config.TotalWaves, formatTime(snap.time))
	DashDot.BackgroundColor3 = if snap.dashReady == true then Colors.ORB else Colors.HUD_DIM
	for i = 1, Config.MaxHearts do
		Hearts[i].TextColor3 = Colors[if i <= snap.hearts then "HEART_FULL" else "HEART_EMPTY"]
	end
	if snap.phase == "MENU" then
		showMenu(snap.best)
	elseif snap.phase == "WIN" then
		showWin(snap)
	elseif snap.phase == "LOSE" then
		showLose(snap)
	else
		MenuOverlay.Visible, WinOverlay.Visible, LoseOverlay.Visible = false, false, false
	end
end
local function onStateSnapshot(snap)
	updateHud(snap)
	if snap.banner ~= nil then showWaveBanner(snap.banner.title, snap.banner.sub) else hideBanner() end
	if snap.events ~= nil then
		for _, event in ipairs(snap.events) do
			if event.type == "damage" then showDamageFlash() end
		end
	end
end
buildHud()
buildMenu()
buildEndScreens()
GameStateEvent.OnClientEvent:Connect(onStateSnapshot)
