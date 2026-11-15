-- NOVA STRIKE shared constants
-- Every number in the design lives here and nowhere else
-- No logic, no state, server and client both require this module
-- Amended tuning (Codex design pass): faster player, slower base enemies,
-- boss HP 40, 20% power-up drops, DENSE replaces SCARCE

local Config = {}

Config.GameName = "NOVA STRIKE"
Config.TotalWaves = 5
Config.MaxHearts = 3
Config.StartHearts = 3

Config.Colors = {
	SCREEN_BG = Color3.fromRGB(8, 10, 24),
	ARENA_BG = Color3.fromRGB(16, 20, 44),
	ARENA_BORDER = Color3.fromRGB(0, 229, 255),
	PLAYER = Color3.fromRGB(0, 229, 255),
	PLAYER_CORE = Color3.fromRGB(255, 255, 255),
	DRONE = Color3.fromRGB(255, 64, 160),
	WEAVER = Color3.fromRGB(255, 150, 40),
	GUNNER = Color3.fromRGB(178, 102, 255),
	BOSS = Color3.fromRGB(255, 60, 60),
	BULLET = Color3.fromRGB(180, 245, 255),
	ENEMY_BOLT = Color3.fromRGB(255, 120, 60),
	POWERUP = Color3.fromRGB(255, 214, 64),
	HUD_BG = Color3.fromRGB(18, 22, 48),
	HUD_TEXT = Color3.fromRGB(235, 240, 255),
	HUD_DIM = Color3.fromRGB(150, 160, 200),
	HEART_FULL = Color3.fromRGB(255, 77, 109),
	HEART_EMPTY = Color3.fromRGB(60, 60, 90),
	BUTTON_BG = Color3.fromRGB(0, 180, 220),
	BUTTON_TEXT = Color3.fromRGB(255, 255, 255),
	TITLE_GOLD = Color3.fromRGB(255, 214, 64),
	TITLE_RED = Color3.fromRGB(255, 77, 77),
	DAMAGE_RED = Color3.fromRGB(255, 40, 40),
}

Config.Layout = {
	ArenaY = 120,
	ArenaWidth = 640,
	ArenaHeight = 480,
	HudY = 12,
	HudWidth = 640,
	HudHeight = 44,
	HintY = 612,
	HintHeight = 28,
	BannerWidth = 460,
	BannerHeight = 110,
	BannerCenterY = 360,
	OverlayTransparency = 0.12,
}

Config.Tuning = {
	PlayerSize = 28,
	PlayerSpeed = 360,
	PlayerSpawnX = 320,
	PlayerSpawnY = 440,
	PlayerMinX = 14,
	PlayerMaxX = 626,
	PlayerMinY = 14,
	PlayerMaxY = 466,
	InvulnSeconds = 1.2,
	DashMultiplier = 2.4,
	DashSeconds = 0.22,
	DashCooldown = 3.5,
	DashInvulnSeconds = 0.25,
	FireInterval = 0.35,
	RapidFireInterval = 0.175,
	BulletSpeed = 560,
	BulletSizeX = 6,
	BulletSizeY = 14,
	BulletLifetime = 1.2,
	SpreadAngleDegrees = 18,
	DroneHp = 1,
	DroneSpeed = 90,
	DroneSize = 24,
	DroneScore = 100,
	DroneDiveSpeed = 320,
	DroneTelegraphSeconds = 0.5,
	DroneDiveTriggerDistance = 220,
	WeaverHp = 2,
	WeaverSpeed = 75,
	WeaverSize = 24,
	WeaverScore = 150,
	WeaverAmplitude = 70,
	WeaverFrequency = 2.5,
	WeaverTrailInterval = 0.15,
	WeaverTrailLifetime = 1.0,
	TrailSize = 16,
	GunnerHp = 2,
	GunnerSpeed = 55,
	GunnerSize = 28,
	GunnerScore = 200,
	GunnerHoverY = 90,
	GunnerFireSeconds = 2.2,
	GunnerChargeSeconds = 0.6,
	FanSpreadHalfAngle = 0.28,
	EnemyBoltSpeed = 240,
	EnemyBoltSize = 10,
	EnemyBoltLifetime = 3.0,
	BossBoltSpeed = 280,
	BossHp = 40,
	BossSize = 90,
	BossScore = 1000,
	BossSpeed = 70,
	BossSpawnX = 320,
	BossSpawnY = 70,
	BossFireSecondsP1 = 2.2,
	BossFireSecondsP2 = 1.8,
	BossFireSecondsP3 = 1.1,
	BossPhase3Speed = 100,
	BossSweepHalfAngle = 1.05, -- ~60 deg each way: 120-degree P3 sweep arc
	BossSweepStep = 0.35, -- radians the P3 sweep advances per shot
	BossDroneSpawnSeconds = 6,
	WaveSpeedBonus = 8,
	SwiftMultiplier = 1.15,
	DenseSpawnFactor = 0.7,
	TightArenaInset = 60,
	StreakWindowSeconds = 3.0,
	StreakMaxMult = 3,
	NearMissRadius = 30,
	NearMissBonus = 25,
	DangerKillBonus = 50,
	DangerKillWindowSeconds = 1.5,
	PowerupDropChance = 0.20,
	PowerupPickupRadius = 26,
	PowerupLifetime = 9,
	PowerupMaxOnField = 3,
	PowerupScore = 50,
	ShieldSeconds = 12,
	RapidSeconds = 8,
	SpreadSeconds = 8,
	SpawnInterval = 0.6,
	SpawnMinPlayerDistance = 120,
	SpawnEdgeInset = 20,
	WaveClearBannerSeconds = 2.5,
	NextWaveBannerSeconds = 1.5,
	FreezeSeconds = 0.6,
	DamageFlashSeconds = 0.4,
	SnapshotHz = 20,
}

-- Wave table: bonus = 250 x wave. SWARM counts already include the +2/+2;
-- Spawner adds nothing extra. Score baseline (mult x1, no power-ups,
-- every scheduled enemy killed): kills 600+1050+1500+1600+2750 = 7500,
-- bonuses 3750, baseline = 11,250. It is a baseline, not a guaranteed
-- floor: drones and weavers can escape without points and the wave
-- still completes, so a winning run can score below 11,250.
Config.Waves = {
	{ Drones = 6, Weavers = 0, Gunners = 0, Boss = 0, Bonus = 250, Modifier = "STANDARD" },
	{ Drones = 6, Weavers = 3, Gunners = 0, Boss = 0, Bonus = 500, Modifier = "SWIFT" },
	{ Drones = 5, Weavers = 4, Gunners = 2, Boss = 0, Bonus = 750, Modifier = "DENSE" },
	{ Drones = 6, Weavers = 4, Gunners = 2, Boss = 0, Bonus = 1000, Modifier = "TIGHT" },
	{ Drones = 6, Weavers = 5, Gunners = 2, Boss = 1, Bonus = 1250, Modifier = "SWARM" },
}

Config.Phases = { "MENU", "PLAYING", "WAVE_CLEAR", "WIN", "LOSE" }

Config.RemotesFolder = "NovaStrikeRemotes"
Config.GameStateEvent = "GameStateEvent"
Config.PlayerActionEvent = "PlayerActionEvent"
Config.DataStoreName = "NovaStrikeBest"
Config.DataStoreKey = "BestScore"

return Config
