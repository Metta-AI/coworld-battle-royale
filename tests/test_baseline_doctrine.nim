import
  std/[os, strutils, unittest]

const RepoRoot = currentSourcePath.parentDir.parentDir

suite "baseline FFA doctrine":
  let
    baseline = readFile(RepoRoot / "players" / "baseline" / "baseline.nim")
    demo = readFile(RepoRoot / "tools" / "run_ffa_demo.sh")

  test "unset doctrine defaults to hunter":
    check baseline.count("FfaDoctrine = FfaLegacy") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaLegacy") == 0
    check baseline.count("if requestedDoctrine.len == 0: FfaHunter") == 1
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
    check baseline.contains("FfaHunterArmTripMaxDetourRadiusDefault = 480.0")
    check baseline.contains("FfaHunterArmSafeMarginDefault = 80.0")
    check baseline.contains("FfaHunterRingMarginDefault = 0.0")
    check baseline.contains(
      "CTF_BOT_FFA_DOCTRINE must be hybrid, legacy, passive, rush, shade, hunter, or pact")

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

  test "hunter ring margin is isolated":
    check baseline.count("if FfaHunterRingMargin > 0.0:") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n      ringRadius, FfaHunterRingMargin)") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n    ringRadius, FfaShadeRingMargin)") == 1
