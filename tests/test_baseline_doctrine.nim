import
  std/[os, strutils, unittest]

const RepoRoot = currentSourcePath.parentDir.parentDir

suite "baseline FFA doctrine":
  let
    baseline = readFile(RepoRoot / "players" / "baseline" / "baseline.nim")
    demo = readFile(RepoRoot / "tools" / "run_ffa_demo.sh")

  test "unset doctrine defaults to hunter":
    check baseline.count("FfaDoctrine = FfaHunter") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaHunter") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaPassive") == 0
    check baseline.count("if requestedDoctrine.len == 0: FfaHybrid") == 0
    check demo.count(
      "CTF_BOT_FFA_DOCTRINE=\"${CTF_BOT_FFA_DOCTRINE:-hunter}\"") == 1

  test "legacy doctrine remains an explicit opt-out":
    check baseline.count("requestedDoctrine == \"legacy\"") == 1
    check baseline.count("elif requestedDoctrine == \"legacy\": FfaLegacy") == 1

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
      "CTF_BOT_FFA_DOCTRINE must be hybrid, legacy, passive, rush, shade, or hunter")

  test "hunter ring margin is opt-in and isolated":
    check baseline.count("if FfaHunterRingMargin > 0.0:") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n      ringRadius, FfaHunterRingMargin)") == 1
    check baseline.count(
      "ffaBandRadiusWithRingMargin(result.bandRadius,\n    ringRadius, FfaShadeRingMargin)") == 1
