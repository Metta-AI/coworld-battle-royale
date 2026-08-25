## Throwaway ship-prep probe (2026-08-21, v60 image-prep lane): print the
## RESOLVED shippedCombatTune() booleans directly, with NO env set, so
## "armed in the image" is a one-line fact instead of an inference from
## full-game grabprobe output. Mirrors the v58 LEVERSTATE idea (-d:wuffprobe)
## but as a standalone dump covering the v60 bundle's new fields. Never
## baked into /bin/baseline (same untracked-eval-file contract as
## grabprobe.nim/harness.nim): the shipped image only ever compiles
## baseline.nim itself with NIM_DEFINES="".
import std/os
include "../baseline.nim"

let t = shippedCombatTune()
echo "=== v60 SHIPPED TUNE, no env set ==="
echo "tradeGate=", t.tradeGate, " tradeGateSquare=", t.tradeGateSquare,
     " tradeGateContest=", t.tradeGateContest, " tradeGateSelfHp=", t.tradeGateSelfHp,
     " tradeGateShadow=", t.tradeGateShadow
echo "raidFrame=", t.raidFrame
echo "lockOne=", t.lockOne
echo "windupLead=", t.windupLead, " windupSelfLead=", t.windupSelfLead
echo "sprayConeFire=", t.sprayConeFire, " sprayFireFirst=", t.sprayFireFirst
echo "--- v59-bundle opt-IN levers, must stay OFF with no env ---"
echo "kitSel=", t.kitSel, " shieldAddr=", t.shieldAddr, " medEncum=", t.medEncum,
     " koRelease=", t.koRelease
echo "mateKoAim=", t.mateKoAim, " mateKoWatch=", t.mateKoWatch,
     " mateKoDoor=", t.mateKoDoor, " mateKoStale=", t.mateKoStale
echo "--- v58 FF vetoes (must remain armed, unaffected by v59) ---"
echo "windupFf=", t.windupFf, " windupFfUnion=", t.windupFfUnion,
     " nadeFfVeto=", t.nadeFfVeto, " sprayFfVeto=", t.sprayFfVeto
