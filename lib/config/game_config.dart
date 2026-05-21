// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

// ── Territory constants ───────────────────────────────────────────────────────

/// Minimum territory unit in metres. Lassos enclosing less are ignored.
const double kMinTerritoryM = 500.0;

/// Lasso closure trigger: proximity to any earlier trail point.
const double kClosureSensitivityM = 250.0;

/// Max influence level per zone.
const int kMaxInfluenceLevel = 15;

/// Influence lost per conquest lasso.
const int kConquestLossPerLasso = 1;

/// Grace period (no activity) before passive decay starts.
const Duration kDecayGracePeriod = Duration(hours: 72);

/// Influence levels drained per day after grace period expires (level 15 → 1 in 365 days).
const double kDecayPerDay = 14.0 / 365.0;

// ── Credits economy ───────────────────────────────────────────────────────────

/// Passive income formula: level × area_km² credits/hour per owned zone.
/// See TerritoryService.accruePassiveIncome.

/// Bonus credits earned on each successful zone claim.
const double kCreditsPerClaim = 100.0;

/// Bonus credits earned on each conquest (rival zone taken).
const double kCreditsPerConquest = 250.0;

/// Bonus credits earned on completing a run regardless of outcome.
const double kCreditsPerRun = 25.0;

// ── Superpower / boost tiers ──────────────────────────────────────────────────

enum PowerTier { common, rare, epic, legendary }

enum PowerCategory { attack, defense, economy, intelligence, apocalyptic }

class PowerDef {
  const PowerDef({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.category,
    required this.creditCost,
    required this.maxCharges,
    required this.duration,
    required this.icon,
    this.earnableFromRuns = true,
    this.dropsEnabled = true,
  });

  final String id;
  final String name;
  final String description;
  final PowerTier tier;
  final PowerCategory category;

  /// Credit cost to purchase one charge in the store.
  final double creditCost;

  /// Max charges a player can hold at once.
  final int maxCharges;

  /// How long the effect lasts (Duration.zero = instant).
  final Duration duration;

  final IconData icon;

  /// Whether this power can be earned through running milestones.
  final bool earnableFromRuns;

  /// Whether this power can appear as a map drop.
  final bool dropsEnabled;
}

// ── ATTACK POWERS ─────────────────────────────────────────────────────────────

/// RUSH — next lasso closure deals 2× influence drain on target zone.
const PowerDef kPowerRush = PowerDef(
  id: 'rush',
  name: 'RUSH',
  description: 'Your next lasso drains 2× influence from the enemy zone.',
  tier: PowerTier.common,
  category: PowerCategory.attack,
  creditCost: 150,
  maxCharges: 3,
  duration: Duration.zero,
  icon: Icons.flash_on,
);

/// BLITZ — instantly reduce a target zone's influence by 3 levels.
const PowerDef kPowerBlitz = PowerDef(
  id: 'blitz',
  name: 'BLITZ',
  description: 'Instantly strip 3 influence levels from a rival zone you are standing in.',
  tier: PowerTier.rare,
  category: PowerCategory.attack,
  creditCost: 400,
  maxCharges: 2,
  duration: Duration.zero,
  icon: Icons.bolt,
);

/// SIEGE — for 60 minutes every lasso on rival zones drains 3× influence.
const PowerDef kPowerSiege = PowerDef(
  id: 'siege',
  name: 'SIEGE',
  description: 'For 1 hour, every lasso you close deals triple influence damage to rivals.',
  tier: PowerTier.epic,
  category: PowerCategory.attack,
  creditCost: 1200,
  maxCharges: 1,
  duration: Duration(hours: 1),
  icon: Icons.whatshot,
);

/// HYPERSONIC — while active, every 1000m run in a consistent direction extends
/// your claimed zone 2× in that direction. Direction is computed from the
/// net displacement vector of each 1000m segment.
/// Example: running 1km north → zone boundary pushes 2km north from your start point.
const PowerDef kPowerHypersonic = PowerDef(
  id: 'hypersonic',
  name: 'HYPERSONIC',
  description:
      'Every 1000m you run, your lasso territory extends 2× in that direction. '
      'The harder you run in one direction, the further your empire stretches.',
  tier: PowerTier.epic,
  category: PowerCategory.attack,
  creditCost: 1600,
  maxCharges: 1,
  duration: Duration(minutes: 30),
  icon: Icons.multiple_stop,
);

// ── DEFENSE POWERS ────────────────────────────────────────────────────────────

/// SHIELD — your zones are immune to influence loss for 30 minutes.
const PowerDef kPowerShield = PowerDef(
  id: 'shield',
  name: 'SHIELD',
  description: 'All your zones are immune to influence loss for 30 minutes.',
  tier: PowerTier.common,
  category: PowerCategory.defense,
  creditCost: 150,
  maxCharges: 3,
  duration: Duration(minutes: 30),
  icon: Icons.shield,
);

/// FORTIFY — instantly add +3 influence to a zone you are standing in.
const PowerDef kPowerFortify = PowerDef(
  id: 'fortify',
  name: 'FORTIFY',
  description: 'Instantly reinforce a zone you are inside with +3 influence.',
  tier: PowerTier.rare,
  category: PowerCategory.defense,
  creditCost: 350,
  maxCharges: 2,
  duration: Duration.zero,
  icon: Icons.security,
);

/// CITADEL — all your zones are fully invulnerable for 2 hours.
const PowerDef kPowerCitadel = PowerDef(
  id: 'citadel',
  name: 'CITADEL',
  description: 'All your zones in the city become invulnerable for 2 hours. No attack can reduce them.',
  tier: PowerTier.epic,
  category: PowerCategory.defense,
  creditCost: 2000,
  maxCharges: 1,
  duration: Duration(hours: 2),
  icon: Icons.fort,
);

// ── ECONOMY / INCOME POWERS ───────────────────────────────────────────────────

/// OVERCLOCK — double passive income from all owned zones for 24 hours.
const PowerDef kPowerOverclock = PowerDef(
  id: 'overclock',
  name: 'OVERCLOCK',
  description: 'Double credits/hour from all your owned zones for 24 hours.',
  tier: PowerTier.rare,
  category: PowerCategory.economy,
  creditCost: 500,
  maxCharges: 2,
  duration: Duration(hours: 24),
  icon: Icons.speed,
);

/// TIME WARP — reset the decay timer on all your zones to now (no decay for 72h).
const PowerDef kPowerTimeWarp = PowerDef(
  id: 'time_warp',
  name: 'TIME WARP',
  description: 'Resets the decay clock on all your zones — as if you just ran every one of them.',
  tier: PowerTier.epic,
  category: PowerCategory.economy,
  creditCost: 1500,
  maxCharges: 1,
  duration: Duration.zero,
  icon: Icons.history,
);

// ── INTELLIGENCE POWERS ───────────────────────────────────────────────────────

/// GHOST RUN — your GPS trail is hidden from rivals for your next lasso.
const PowerDef kPowerGhostRun = PowerDef(
  id: 'ghost_run',
  name: 'GHOST RUN',
  description: 'Your trail is invisible to all rivals during your next lasso closure.',
  tier: PowerTier.rare,
  category: PowerCategory.intelligence,
  creditCost: 300,
  maxCharges: 3,
  duration: Duration.zero,
  icon: Icons.visibility_off,
  dropsEnabled: false,
);

/// SATELLITE — lift fog of war for the entire city for 1 hour. See all rival activity.
const PowerDef kPowerSatellite = PowerDef(
  id: 'satellite',
  name: 'SATELLITE',
  description: 'Full city visibility for 1 hour — all rival positions, trails, and zones revealed.',
  tier: PowerTier.epic,
  category: PowerCategory.intelligence,
  creditCost: 1800,
  maxCharges: 1,
  duration: Duration(hours: 1),
  icon: Icons.satellite_alt,
);

// ── APOCALYPTIC POWERS ────────────────────────────────────────────────────────

/// EARTHQUAKE — halve the influence of ALL rival zones in the city simultaneously.
/// Cannot be purchased. Earned by collecting 10 Temporal Shards from map drops,
/// OR via a one-time $9.99 in-app purchase unlock.
const PowerDef kPowerEarthquake = PowerDef(
  id: 'earthquake',
  name: 'EARTHQUAKE',
  description:
      'Halves the influence of every rival-owned zone in the city at once. '
      'Cannot be blocked by Shield or Citadel.',
  tier: PowerTier.legendary,
  category: PowerCategory.apocalyptic,
  creditCost: 50000,
  maxCharges: 1,
  duration: Duration.zero,
  icon: Icons.crisis_alert,
  earnableFromRuns: false,
  dropsEnabled: false,
);

/// DOMINION — for 1 hour, every lasso you close instantly conquers the full zone
/// regardless of influence level. No lasso attack needed — first closure = ownership.
const PowerDef kPowerDominion = PowerDef(
  id: 'dominion',
  name: 'DOMINION',
  description:
      'For 1 hour, a single lasso closure over any rival zone flips it to you instantly, '
      'regardless of influence level. Maximum 3 zones.',
  tier: PowerTier.legendary,
  category: PowerCategory.apocalyptic,
  creditCost: 75000,
  maxCharges: 1,
  duration: Duration(hours: 1),
  icon: Icons.public,
  earnableFromRuns: false,
  dropsEnabled: false,
);

/// BLACKOUT — disable all active superpowers of every rival in the city for 2 hours.
const PowerDef kPowerBlackout = PowerDef(
  id: 'blackout',
  name: 'BLACKOUT',
  description:
      'Immediately cancels and disables all active rival superpowers in the city for 2 hours. '
      'No attack power, no shield, no income boost.',
  tier: PowerTier.legendary,
  category: PowerCategory.apocalyptic,
  creditCost: 60000,
  maxCharges: 1,
  duration: Duration(hours: 2),
  icon: Icons.power_off,
  earnableFromRuns: false,
  dropsEnabled: false,
);

/// NUKE — completely destroys a single rival zone, returning it to neutral.
/// The most targeted apocalyptic power. Deletes the zone from the map.
const PowerDef kPowerNuke = PowerDef(
  id: 'nuke',
  name: 'NUKE',
  description:
      'Obliterates a single rival zone. Returns it to neutral instantly, destroying all '
      'accumulated influence and any active bonuses. Cannot target zones with Citadel active.',
  tier: PowerTier.legendary,
  category: PowerCategory.apocalyptic,
  creditCost: 100000,
  maxCharges: 1,
  duration: Duration.zero,
  icon: Icons.local_fire_department,
  earnableFromRuns: false,
  dropsEnabled: false,
);

/// All powers in catalog order.
const List<PowerDef> kAllPowers = [
  kPowerRush,
  kPowerBlitz,
  kPowerSiege,
  kPowerHypersonic,
  kPowerShield,
  kPowerFortify,
  kPowerCitadel,
  kPowerOverclock,
  kPowerTimeWarp,
  kPowerGhostRun,
  kPowerSatellite,
  kPowerEarthquake,
  kPowerDominion,
  kPowerBlackout,
  kPowerNuke,
];

// ── MAP OBJECT DROPS ──────────────────────────────────────────────────────────

enum DropType { influenceCrystal, creditsCache, powerCore, ancientRelic, temporalShard }

class DropDef {
  const DropDef({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.spawnWeightPercent,
    this.creditsValue = 0,
    this.influenceBonus = 0,
    this.powerId,
  });

  final DropType type;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  /// Relative spawn frequency (sum across all drops = 100).
  final int spawnWeightPercent;

  final double creditsValue;
  final int influenceBonus;

  /// If set, collecting this drop grants 1 charge of the named power.
  final String? powerId;
}

const DropDef kDropInfluenceCrystal = DropDef(
  type: DropType.influenceCrystal,
  name: 'Influence Crystal',
  description: '+1 influence to your nearest owned zone on pickup.',
  icon: Icons.diamond,
  color: Color(0xFF74BCFF),
  spawnWeightPercent: 50,
  influenceBonus: 1,
);

const DropDef kDropCreditsCache = DropDef(
  type: DropType.creditsCache,
  name: 'Credits Cache',
  description: 'Instant 500 credits.',
  icon: Icons.toll,
  color: Color(0xFFFFE566),
  spawnWeightPercent: 30,
  creditsValue: 500,
);

const DropDef kDropPowerCore = DropDef(
  type: DropType.powerCore,
  name: 'Power Core',
  description: 'Grants 1 charge of a random rare power.',
  icon: Icons.circle,
  color: Color(0xFF9B59B6),
  spawnWeightPercent: 15,
);

const DropDef kDropAncientRelic = DropDef(
  type: DropType.ancientRelic,
  name: 'Ancient Relic',
  description: 'Grants 1 charge of a random epic power.',
  icon: Icons.auto_awesome,
  color: Color(0xFFFF5533),
  spawnWeightPercent: 4,
);

/// Collect 10 to assemble EARTHQUAKE.
const DropDef kDropTemporalShard = DropDef(
  type: DropType.temporalShard,
  name: 'Temporal Shard',
  description: 'Fragment of city-altering power. Collect 10 to unlock EARTHQUAKE.',
  icon: Icons.hexagon,
  color: Color(0xFFFF9A3C),
  spawnWeightPercent: 1,
);

/// All drop types. Weights sum to 100.
const List<DropDef> kAllDrops = [
  kDropInfluenceCrystal,
  kDropCreditsCache,
  kDropPowerCore,
  kDropAncientRelic,
  kDropTemporalShard,
];

/// Proximity radius for pickup (metres).
const double kDropPickupRadiusM = 50.0;

/// How many drops can exist simultaneously per city.
const int kMaxDropsPerCity = 20;

/// Temporal Shards needed to assemble EARTHQUAKE.
const int kEarthquakeShardsRequired = 10;

// ── In-app purchase SKUs (prices set in App Store / Play Store) ───────────────

const String kSkuCredits500   = 'credits_500';    // $0.99
const String kSkuCredits2500  = 'credits_2500';   // $3.99
const String kSkuCredits7500  = 'credits_7500';   // $9.99
const String kSkuEarthquakeUnlock = 'unlock_earthquake'; // $9.99 one-time
const String kSkuWarlordsPass = 'warlords_pass';  // $4.99/month — 2× income, exclusive cosmetics
