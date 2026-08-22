import
  std/[os, strutils, unittest]

const RepoRoot = currentSourcePath.parentDir.parentDir

suite "baseline FFA doctrine":
  test "unset doctrine defaults to passive":
    let
      baseline = readFile(RepoRoot / "players" / "baseline" / "baseline.nim")
      demo = readFile(RepoRoot / "tools" / "run_ffa_demo.sh")
    check baseline.count("FfaDoctrine = FfaPassive") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaPassive") == 1
    check baseline.count("if requestedDoctrine.len == 0: FfaHybrid") == 0
    check demo.count(
      "CTF_BOT_FFA_DOCTRINE=\"${CTF_BOT_FFA_DOCTRINE:-passive}\"") == 1
