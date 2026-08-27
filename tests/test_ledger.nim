import std/[os, unittest]

import ../tools/ledger

suite "episode ledger weapon pickups":
  test "combined tier pickups count and distinguish fixed spawns from drops":
    let path = getTempDir() / "weapon-drop-ledger-test.jsonl"
    if fileExists(path):
      removeFile(path)
    try:
      writeFile(path, """
{"kind":"item_pickup","tick":10,"source":0,"item":"low gun","x":100,"y":100}
{"kind":"item_pickup","tick":20,"source":0,"item":"dropped heavy gun","x":200,"y":200}
{"kind":"item_pickup","tick":30,"source":0,"item":"med_kit","x":300,"y":300}
{"type":"summary","ticks":40,"events":3,"slot_address":["seat-0"]}
""")
      let ledger = loadLedger(path)
      let all = ledger.tierPickups(0)
      let fixed = ledger.fixedTierPickups(0)
      let dropped = ledger.droppedTierPickups(0)
      check all.len == 2
      check fixed.len == 1
      check fixed[0].item == "low gun"
      check dropped.len == 1
      check dropped[0].item == "dropped heavy gun"
    finally:
      if fileExists(path):
        removeFile(path)
