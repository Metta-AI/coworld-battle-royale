import
  std/[os, strutils, unittest]

const RepoRoot = currentSourcePath.parentDir.parentDir

suite "baseline FFA doctrine":
  let
    baseline = readFile(RepoRoot / "players" / "baseline" / "baseline.nim")
    demo = readFile(RepoRoot / "tools" / "run_ffa_demo.sh")

  test "unset doctrine defaults to legacy":
    check baseline.count("FfaDoctrine = FfaLegacy") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaLegacy") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaPact") == 0
    check baseline.count("if requestedDoctrine.len == 0: FfaPassive") == 0
    check baseline.count("if requestedDoctrine.len == 0: FfaHybrid") == 0
    check demo.count(
      "CTF_BOT_FFA_DOCTRINE=\"${CTF_BOT_FFA_DOCTRINE:-legacy}\"") == 1

  test "hunter doctrine is selectable":
    check baseline.count("FfaHunter") >= 4
    check baseline.count("requestedDoctrine == \"hunter\"") == 1
    check baseline.count("of FfaHunter: \"hunter\"") == 1
    check baseline.contains("CTF_BOT_FFA_HUNTER_ARM")
    check baseline.contains("CTF_BOT_FFA_HUNTER_FIRE_RANGE")
    check baseline.contains("CTF_BOT_FFA_HUNTER_PURSUIT")
    check baseline.contains("CTF_BOT_FFA_HUNTER_PURSUIT_MIN_HP")
    check baseline.contains("CTF_BOT_FFA_HUNTER_SUPPORT_RADIUS")
    check baseline.contains("CTF_BOT_FFA_HUNTER_ARM_TRIP_MAX_SEC")
    check baseline.contains("CTF_BOT_FFA_HUNTER_ARM_TRIP_MAX_DETOUR_RADIUS")
    check baseline.contains("CTF_BOT_FFA_HUNTER_ARM_SAFE_MARGIN")
    check baseline.contains("CTF_BOT_FFA_HUNTER_RING_MARGIN")
    check baseline.contains("FfaHunterArmDefault = true")
    check baseline.contains("FfaHunterFireRangeDefault = true")
    check baseline.contains("FfaHunterPursuitDefault = true")
    check baseline.contains("FfaHunterPursuitMinHpDefault = 6")
    check baseline.contains("FfaHunterSupportRadiusDefault = 300.0")
    check baseline.contains("FfaHunterArmTripMaxSecDefault = 30")
    check baseline.contains("FfaHunterArmTripMaxDetourRadiusDefault = 240.0")
    check baseline.contains("FfaHunterArmSafeMarginDefault = 80.0")
    check baseline.contains("FfaHunterRingMarginDefault = 0.0")
    check baseline.contains(
      "CTF_BOT_FFA_DOCTRINE must be hybrid, legacy, passive, rush, shade, hunter, or pact")

  test "FFA orbit lead preserves the default and rotates the band target":
    check baseline.contains("FfaOrbitLeadDegDefault = 0.0")
    check baseline.contains(
      "FfaOrbitLeadDeg = clamp(parseEnvFloat(\"CTF_BOT_FFA_ORBIT_LEAD_DEG\",")
    check baseline.contains("FfaOrbitLeadDegDefault), 0.0, 90.0)")
    check baseline.contains("angle = float(FfaOrbitLeadDeg) * PI / 180.0")
    check baseline.contains(
      "(if bot.slot mod 2 == 0: 1.0 else: -1.0)")
    check baseline.contains("if FfaOrbitLeadDeg == 0.0:")
    check baseline.contains("bearing.x * cosAngle - bearing.y * sinAngle")
    check baseline.contains("bearing.x * sinAngle + bearing.y * cosAngle")
    check baseline.contains("bearing = ffaOrbitBearing(bot, rawBearing)")
    check baseline.count("bearing = ffaOrbitBearing(bot, rawBearing)") == 2
    check baseline.contains("else: norm(ffaSeatBearing(bot.slot))")
    check baseline.contains("ffaOrbitLeadDeg=\", FfaOrbitLeadDeg")

  test "pact doctrine is selectable":
    check baseline.count("requestedDoctrine == \"pact\"") == 1
    check baseline.count("of FfaPact: \"pact\"") == 1
    check baseline.contains("CTF_BOT_FFA_PACT_WINDOW_FRACTION")
    check baseline.contains("CTF_BOT_FFA_PACT_WINDOW_SEC")
    check baseline.contains("CTF_BOT_FFA_PACT_BRAWL_RADIUS")
    check baseline.contains("CTF_BOT_FFA_PACT_CONVERGE_RANGE")
    check baseline.contains("CTF_BOT_FFA_PACT_ENGAGE_RANGE")
    check baseline.contains("CTF_BOT_FFA_PACT_MEMORY_SEC")
    check baseline.contains("CTF_BOT_FFA_PACT_PARTNER_MATCH_RADIUS")
    check baseline.contains("FfaPactWindowFractionDefault = 0.35")
    check baseline.contains("FfaPactWindowSecDefault = 0")
    check baseline.contains("FfaPactBrawlRadiusDefault = 220.0")
    check baseline.contains("FfaPactMinBrawlSeparationDefault = 8.0")
    check baseline.contains(
      "d >= FfaPactMinBrawlSeparationDefault and")
    check baseline.contains("FfaPactConvergeRangeDefault = 520.0")
    check baseline.contains("FfaPactEngageRangeDefault = 220.0")
    check baseline.contains("FfaPactMemorySecDefault = 3")
    check baseline.contains("FfaPactPartnerMatchRadiusDefault = 60.0")
    check baseline.contains(
      "CTF_BOT_FFA_DOCTRINE must be hybrid, legacy, passive, rush, shade, hunter, or pact")

  test "pact is never the default":
    check baseline.contains("FfaDoctrineKind = enum\n    FfaHybrid")
    check baseline.count("FfaDoctrine = FfaLegacy") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaPact") == 0

  test "per-seat doctrine override is opt-in":
    check baseline.contains(
      "let doctrineSlots = getEnv(\"CTF_BOT_FFA_DOCTRINE_SLOTS\")")
    check baseline.contains("if doctrineSlots.len > 0:")
    check baseline.contains("slotNumber = parseInt(fields[0].strip())")
    check baseline.contains(
      "except ValueError:\n        continue\n      if slotNumber == slot:\n        FfaDoctrine = ffaDoctrineFor")

  test "hunter ring margin is opt-in and isolated":
    check baseline.count("if FfaHunterRingMargin > 0.0:") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n      ringRadius, FfaHunterRingMargin)") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n    ringRadius, FfaShadeRingMargin)") == 1
  test "hunter weapon upgrade is dormant by default":
    check baseline.contains("FfaHunterUpgradeDefault = false")
    check baseline.contains(
      "if not unarmed and\n      (not FfaHunterUpgrade or weaponTier >= FfaWeaponHeavy):")
    check baseline.contains(
      "bot.ffaLootUpgradeTrip = false\n    if targetIndex >= 0")
    check baseline.contains("FfaHunterUpgrade = parseEnvBool")

  test "hunter upgrade knobs are clamped and logged":
    check baseline.contains("CTF_BOT_FFA_HUNTER_UPGRADE")
    check baseline.contains("CTF_BOT_FFA_HUNTER_UPGRADE_DETOUR")
    check baseline.contains("CTF_BOT_FFA_HUNTER_UPGRADE_TRIP_MAX_SEC")
    check baseline.contains(
      "FfaHunterUpgradeDetourDefault = 240.0")
    check baseline.contains(
      "FfaHunterUpgradeTripMaxSecDefault = 30")
    check baseline.contains(
      "FfaHunterUpgradeDetourDefault), 0.0, 1200.0")
    check baseline.contains(
      "FfaHunterUpgradeTripMaxSecDefault), 0, 300)")
    check baseline.contains("ffaHunterUpgrade=",)
    check baseline.contains("ffaHunterUpgradeDetour=",)
    check baseline.contains("ffaHunterUpgradeTripMaxSec=",)

  test "loot contest knobs preserve the default veto":
    check baseline.contains("FfaLootContestMarginDefault = 0.0")
    check baseline.contains("FfaLootContestIgnoreDefault = false")
    check baseline.contains(
      "FfaLootContestMargin = FfaLootContestMarginDefault")
    check baseline.contains(
      "FfaLootContestIgnore = FfaLootContestIgnoreDefault")
    check baseline.contains("CTF_BOT_FFA_LOOT_CONTEST_MARGIN")
    check baseline.contains("CTF_BOT_FFA_LOOT_CONTEST_IGNORE")
    check baseline.contains(
      "FfaLootContestMarginDefault),\n    0.0, 2000.0")
    check baseline.contains(
      "CTF_BOT_FFA_LOOT_CONTEST_IGNORE\", FfaLootContestIgnoreDefault)")
    check baseline.contains(
      "ffaLootContestMargin=",)
    check baseline.contains(
      "ffaLootContestIgnore=",)
    let
      contestStart = baseline.find("var opponentCloser = false")
      contestEnd = baseline.find("if opponentCloser:", contestStart)
      contestBlock = baseline[contestStart ..< contestEnd]
    check contestStart >= 0
    check contestEnd > contestStart
    check contestBlock.contains("if not FfaLootContestIgnore:")
    check contestBlock.contains(
      "dist(actor.pos, gun) < d - FfaLootContestMargin")

  test "hunter upgrade trips select better guns and expose telemetry":
    check baseline.contains(
      "maxDetour = if upgradeTrip: FfaHunterUpgradeDetour else:")
    check baseline.contains("FfaHunterArmTripMaxDetourRadius")
    check baseline.contains(
      "FfaHunterArmSafeMargin, maxDetour, actors)")
    check baseline.contains(
      "objective = if upgradeTrip: \"upgrade_trip\" else: \"loot_trip\"")
    check baseline.contains(
      "action = if upgradeTrip: \"move_upgrade\" else: \"move_gun\"")
    check baseline.contains(
      "bot.ffaLootUpgradeTrip = upgradeTrip")
    check baseline.contains(
      "maxDetour = if bot.ffaLootUpgradeTrip:\n      FfaHunterUpgradeDetour")

  test "hunter upgrade keeps trip bounds and fire-range telemetry":
    check baseline.contains(
      "maxTripSec = if bot.ffaLootUpgradeTrip:\n      FfaHunterUpgradeTripMaxSec")
    check baseline.contains(
      "ffaGameTicksSince(bot.tick, bot.ffaLootStartedTick) >\n        maxTripSec * TargetFps")
    check baseline.contains(
      "if d > maxDetour or")
    check baseline.contains(
      "if upgradeTrip and targetIndex >= 0 and")
    check baseline.contains(
      "result.engageReason = \"fire_range\"")
    let
      fireRangeStart = baseline.find(
        "if upgradeTrip and targetIndex >= 0 and")
      fireRangeEnd = baseline.find(
        "if not upgradeTrip and not FfaHunterArm:", fireRangeStart)
      fireRangeBlock = baseline[fireRangeStart ..< fireRangeEnd]
    check fireRangeStart >= 0
    check fireRangeEnd > fireRangeStart
    check fireRangeBlock.contains(
      "result.engageReason = \"fire_range\"")
    check not fireRangeBlock.contains("bot.ffaLootTrip = false")
    check not fireRangeBlock.contains("return")
    check baseline.contains(
      "let upgradeTrip = not unarmed")
    check baseline.contains(
      "if not upgradeTrip and not FfaHunterArm:")
    check baseline.find("if pursue:") < baseline.find(
      "if not unarmed and\n      (not FfaHunterUpgrade")
    check baseline.contains(
      "if unarmed and (result.lootTripStarted or result.objective == \"loot_trip\"):")
  test "hunter healing is dormant and preserves the gate-off path":
    check baseline.contains("FfaHunterHealDefault = false")
    check baseline.contains("FfaHunterHealSearchDefault = false")
    check baseline.contains("FfaHunterHeal = FfaHunterHealDefault")
    check baseline.contains("FfaHunterHealSearch = FfaHunterHealSearchDefault")
    check baseline.contains("ffaKitPos: seq[Vec]")
    check baseline.contains("ffaKitAbsentAt: seq[int]")
    check baseline.contains("ffaHealTrip: bool")
    check baseline.contains("ffaHealTarget: Vec")
    check baseline.contains("ffaHealStartedTick: int")
    check baseline.contains("if FfaHunterHeal:\n    trackFfaMedKits")
    check baseline.contains("if FfaHunterHeal:\n    if bot.ffaHealTrip")
    check baseline.find("if FfaHunterHeal:") < baseline.find("if pursue:")

  test "hunter healing knobs are clamped and logged":
    check baseline.contains("CTF_BOT_FFA_HUNTER_HEAL")
    check baseline.contains("CTF_BOT_FFA_HUNTER_HEAL_HP")
    check baseline.contains("CTF_BOT_FFA_HUNTER_HEAL_DETOUR")
    check baseline.contains("CTF_BOT_FFA_HUNTER_HEAL_TRIP_MAX_SEC")
    check baseline.contains("CTF_BOT_FFA_HUNTER_HEAL_SEARCH")
    check baseline.contains("FfaHunterHealHpDefault = 12")
    check baseline.contains("FfaHunterHealDetourDefault = 700.0")
    check baseline.contains("FfaHunterHealTripMaxSecDefault = 45")
    check baseline.contains("FfaHunterHealSearchDefault = false")
    check baseline.contains(
      "FfaHunterHealHpDefault), 1, 20)")
    check baseline.contains(
      "FfaHunterHealDetourDefault),\n    0.0, 4000.0)")
    check baseline.contains(
      "FfaHunterHealTripMaxSecDefault), 0, 300)")
    check baseline.contains("ffaHunterHeal=")
    check baseline.contains("ffaHunterHealHp=")
    check baseline.contains("ffaHunterHealDetour=")
    check baseline.contains("ffaHunterHealTripMaxSec=")
    check baseline.contains("ffaHunterHealSearch=")

  test "hunter healing remembers kits and selects the nearest valid target":
    check baseline.contains("proc trackFfaMedKits")
    check baseline.contains("LabelMedKit")
    check baseline.contains("dist(bot.ffaKitPos[i], p) < 24.0")
    check baseline.contains("dist(bot.ffaKitPos[i], me) <= MedKitSeenClear")
    check baseline.contains("bot.ffaKitAbsentAt[i] = bot.tick")
    check baseline.contains("proc nearestFfaKit")
    check baseline.contains("d <= FfaHunterHealDetour and d < bestDist")
    check baseline.contains(
      "dist(bot.ffaKitPos[i], center) > float(max(1, ringRadius))")
    check baseline.contains("proc ffaKitAvailable")
    check baseline.contains(
      "bot.tick - bot.ffaKitAbsentAt[i] > MedKitRespawn + 48")

  test "hunter healing trips expire, skip absent kits, and clear after healing":
    check baseline.contains("proc ffaHealTripStillValid")
    check baseline.contains("if not bot.ffaHealTrip or hp > FfaHunterHealHp:")
    check baseline.contains(
      "ffaGameTicksSince(bot.tick, bot.ffaHealStartedTick) >")
    check baseline.contains("bot.ffaKitAvailable(targetIndex)")
    check baseline.contains(
      "dist(bot.ffaHealTarget, center) <= float(max(1, ringRadius))")
    check baseline.contains("bot.ffaHealTrip = false")
    check baseline.contains("bot.ffaHealStartedTick = 0")
    check baseline.contains("result.phase = \"HEAL\"")
    check baseline.contains("result.objective = \"heal_trip\"")
    check baseline.contains("result.action = \"move_kit\"")
    check baseline.contains("bot.ffaHealTarget = bot.ffaKitPos[kit]")
    check baseline.contains("bot.ffaHealStartedTick = bot.tick")

  test "hunter healing search targets the center until a kit is remembered":
    check baseline.contains(
      "if FfaHunterHealSearch:\n        bot.ffaHealTrip = true")
    check baseline.contains("bot.ffaHealTarget = center")
    check baseline.contains("result.objective = \"heal_search\"")
    check baseline.contains("result.action = \"move_center_kit\"")
    check baseline.contains(
      "if bot.ffaHealTargetIndex() >= 0:\n          result.objective = \"heal_trip\"")
    check baseline.contains(
      "FfaHunterHealSearch and dist(bot.ffaHealTarget, center) < 24.0")
    check baseline.contains(
      "let kit = bot.nearestFfaKit(me, center, ringRadius)")

  test "hunter healing outranks pursuit and pact convergence":
    check baseline.find("if FfaHunterHeal:") < baseline.find("if pursue:")
    check baseline.contains(
      "if result.objective == \"heal_trip\":\n    return")
    check baseline.contains(
      "hunterFfaIntent(bot, client, actors, me, center, ringRadius,\n    targetIndex, targetDist, weaponTier, unarmed, hp, pursue)")

  test "hunter fire gate is independent of heal intent":
    check baseline.contains(
      "hunterRangeGate = FfaDoctrine in {FfaHunter, FfaPact} and")
    check baseline.contains(
      "if (engage or fireWhileHurt or hunterRangeGate) and targetDist < fireRange:")
    check baseline.contains(
      "desiredAim = bradsOf(aimTarget - me)")
    check not baseline.contains(
      "if objective == \"heal_trip\" and hunterRangeGate")
