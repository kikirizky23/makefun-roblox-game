-- EMBER ARENA shared constants
-- Every number in the design lives here and nowhere else
-- No logic, no state, server and client both require this module

local Config = {}

Config.GameName = "EMBER ARENA"
Config.TotalWaves = 5
Config.MaxHearts = 3
Config.StartHearts = 3

Config.Colors = {
	SCREEN_BG = Color3.fromRGB(14, 11, 22),
	ARENA_BG = Color3.fromRGB(27, 22, 38),
	ARENA_BORDER = Color3.fromRGB(255, 107, 53),
	PLAYER = Color3.fromRGB(255, 214, 64),
	PLAYER_CORE = Color3.fromRGB(255, 255, 255),
	CHASER = Color3.fromRGB(255, 77, 77),
	CHASER_CORE = Color3.fromRGB(255, 150, 150),
	DRIFTER = Color3.fromRGB(178, 102, 255),
	DRIFTER_CORE = Color3.fromRGB(216, 180, 255),
	BOLT = Color3.fromRGB(255, 240, 170),
	ORB = Color3.fromRGB(80, 227, 194),
	ORB_CORE = Color3.fromRGB(230, 255, 248),
	HUD_BG = Color3.fromRGB(24, 18, 36),
	HUD_TEXT = Color3.fromRGB(235, 235, 245),
	HUD_DIM = Color3.fromRGB(170, 160, 190),
	HEART_FULL = Color3.fromRGB(255, 77, 109),
	HEART_EMPTY = Color3.fromRGB(74, 60, 92),
	BUTTON_BG = Color3.fromRGB(255, 107, 53),
	BUTTON_HOVER = Color3.fromRGB(255, 140, 90),
	BUTTON_TEXT = Color3.fromRGB(255, 255, 255),
	TITLE_GOLD = Color3.fromRGB(255, 214, 64),
	TITLE_RED = Color3.fromRGB(255, 77, 77),
	DAMAGE_RED = Color3.fromRGB(255, 40, 40),
}

Config.Layout = {
	ScreenWidth = 1280,
	ScreenHeight = 720,
	ArenaX = 320,
	ArenaY = 120,
	ArenaWidth = 640,
	ArenaHeight = 480,
	ArenaBorder = 3,
	HudX = 320,
	HudY = 12,
	HudWidth = 640,
	HudHeight = 44,
	HintY = 612,
	HintHeight = 28,
	BannerWidth = 460,
	BannerHeight = 110,
	BannerCenterX = 640,
	BannerCenterY = 360,
	OverlayTransparency = 0.12,
}

Config.Tuning = {
	PlayerSize = 28,
	PlayerCoreSize = 14,
	PlayerSpeed = 260,
	PlayerSpawnX = 320,
	PlayerSpawnY = 240,
	PlayerMinX = 14,
	PlayerMaxX = 626,
	PlayerMinY = 14,
	PlayerMaxY = 466,
	InvulnSeconds = 1.2,
	InvulnBlinkSeconds = 0.1,
	DashMultiplier = 2.2,
	DashSeconds = 0.18,
	DashCooldown = 1.5,
	FireCooldown = 0.25,
	BoltSizeX = 14,
	BoltSizeY = 6,
	BoltSpeed = 520,
	BoltLifetime = 0.8,
	ChaserSize = 26,
	ChaserCoreSize = 12,
	ChaserScore = 100,
	DrifterSize = 22,
	DrifterCoreSize = 10,
	DrifterScore = 150,
	OrbSize = 16,
	OrbCoreSize = 8,
	OrbSpawnSeconds = 4,
	OrbMaxOnField = 3,
	OrbLifetime = 8,
	OrbPickupRadius = 24,
	OrbScore = 50,
	OrbHealChance = 0.25,
	OrbMinPlayerDistance = 80,
	SpawnInterval = 0.6,
	SpawnMinPlayerDistance = 120,
	SpawnEdgeInset = 20,
	WaveClearBannerSeconds = 2.5,
	NextWaveBannerSeconds = 1.5,
	DamageFlashSeconds = 0.4,
	SnapshotHz = 20,
}

-- Wave table: chasers = 2 + wave, drifters = 1 + wave, bonus = 250 x wave
Config.Waves = {
	{ Chasers = 3, Drifters = 2, ChaserSpeed = 110, DrifterSpeed = 140, Bonus = 250 },
	{ Chasers = 4, Drifters = 3, ChaserSpeed = 122, DrifterSpeed = 150, Bonus = 500 },
	{ Chasers = 5, Drifters = 4, ChaserSpeed = 134, DrifterSpeed = 160, Bonus = 750 },
	{ Chasers = 6, Drifters = 5, ChaserSpeed = 146, DrifterSpeed = 170, Bonus = 1000 },
	{ Chasers = 7, Drifters = 6, ChaserSpeed = 158, DrifterSpeed = 180, Bonus = 1250 },
}

Config.Phases = { "MENU", "PLAYING", "WAVE_CLEAR", "WIN", "LOSE" }

Config.RemotesFolder = "EmberArenaRemotes"
Config.GameStateEvent = "GameStateEvent"
Config.PlayerActionEvent = "PlayerActionEvent"
Config.DataStoreName = "EmberArenaBest"
Config.DataStoreKey = "BestScore"

return Config
