## The league manifest's config_schema is the platform's contract for what a
## league operator may configure — and nothing type-checks it against
## GameConfig. This suite makes drift impossible: every schema property must be
## PROVABLY consumed by config.update (a non-default sample for the key must
## change the parsed config). A GameConfig field added without a schema entry
## stays a local-only knob by design; a schema entry the game stopped reading
## fails here instead of becoming a dead platform knob.

import helpers, std/[json, os, strutils, unittest], ctf/sim

const
  ManifestName = "coworld_manifest_battleroyale.json"
  PlatformOnlyKeys = ["num_agents"]
  ## Schema keys the game deliberately never reads: documented as consumed by
  ## the platform (ladder seating) in the schema description itself, which
  ## this suite asserts so the exemption stays honest.

proc findConfigSchema(node: JsonNode): JsonNode =
  ## Depth-first search for the "config_schema" object in a manifest.
  if node.kind == JObject:
    if node.hasKey("config_schema"):
      return node["config_schema"]
    for _, value in node:
      let found = findConfigSchema(value)
      if found != nil:
        return found
  elif node.kind == JArray:
    for value in node:
      let found = findConfigSchema(value)
      if found != nil:
        return found
  nil

proc manifestSchema(name: string): JsonNode =
  result = findConfigSchema(parseFile(GameDir / name))
  doAssert result != nil, name & " has no config_schema"

proc manifestVariant(variantId: string): JsonNode =
  let manifest = parseFile(GameDir / ManifestName)
  for variant in manifest["variants"]:
    if variant["id"].getStr() == variantId:
      return variant
  doAssert false, ManifestName & " has no " & variantId & " variant"

# One payload per schema property, each carrying a NON-DEFAULT value for its
# key (plus companion keys where update()'s cross-field validation demands
# them — the whole-object inequality below still proves the target key
# landed, since companions only ever change the object further).
const SampleJson = """{
  "aimTurnRate": {"aimTurnRate": 7},
  "barrageMaxPerSec": {"barrageMaxPerSec": 15},
  "barrageStartPerSec": {"barrageStartPerSec": 9},
  "barrageStartSec": {"barrageStartSec": 45},
  "barrageSaturateSec": {"barrageSaturateSec": 45},
  "carrierSpeedPct": {"carrierSpeedPct": 55},
  "closedRoster": {"closedRoster": true, "minPlayers": 1,
                   "slots": [{"token": "tok1"}],
                   "players": [{"name": "tester"}]},
  "fastMode": {"fastMode": false},
  "fireCooldownTicks": {"fireCooldownTicks": 20},
  "fireWindupTicks": {"fireWindupTicks": 9},
  "gameOverTicks": {"gameOverTicks": 100},
  "gunRange": {"gunRange": 500},
  "handicaps": {"handicaps": {"red": 0.5}},
  "barrierPickups": {"barrierPickups": 1},
  "perks": {"perks": {"red": [["armor"], ["scope", "luck"]]}},
  "perkMods": {"perkMods": {"luckChance": 0.25}},
  "hitPoints": {"hitPoints": 5},
  "lives": {"lives": 2},
  "lobbyJoinTimeoutTicks": {"lobbyJoinTimeoutTicks": 50},
  "mapLayout": {"mapLayout": "corners", "teams": 4, "mapPath": "gen"},
  "mapPath": {"mapPath": "gen"},
  "mapSeed": {"mapSeed": 12345, "mapPath": "gen"},
  "mapSize": {"mapSize": "small", "mapPath": "gen"},
  "maxGames": {"maxGames": 3},
  "maxTicks": {"maxTicks": 777},
  "minPlayers": {"minPlayers": 4},
  "players": {"players": [{"name": "tester"}]},
  "respawnTicks": {"respawnTicks": 33},
  "scoring": {"scoring": "pot"},
  "seed": {"seed": 42},
  "showPlayerLabels": {"showPlayerLabels": false},
  "slots": {"slots": [{"token": "tok1"}]},
  "startWaitTicks": {"startWaitTicks": 60},
  "teams": {"teams": 4, "mapPath": "gen"},
  "tokens": {"tokens": ["tokA"]},
  "visionBubble": {"visionBubble": 50},
  "mode": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4},
  "numPlayers": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4},
  "ringEnabled": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                  "ringEnabled": true},
  "ringShrinkSec": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                    "ringShrinkSec": 100},
  "ringFloorAreaPct": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                       "ringFloorAreaPct": 40},
  "ringDamageTicks": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                      "ringDamageTicks": 48},
  "ringRecoveryTicks": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                        "ringRecoveryTicks": 2},
  "ffaLootCount": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                   "ffaLootCount": 8},
  "ffaLootRadius": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                    "ffaLootRadius": 400},
  "ffaLootRespawnTicks": {"mode": "ffa", "numPlayers": 4, "minPlayers": 4,
                          "ffaLootRespawnTicks": 480},
  "mapSymmetry": {"mapSymmetry": "mirror", "mapPath": "gen"},
  "mapColumns": {"mapColumns": 18, "mapPath": "gen"},
  "mapWindows": {"mapWindows": 4, "mapPath": "gen"},
  "mapPits": {"mapPits": 18, "mapPath": "gen"},
  "mapCenterFeature": {"mapCenterFeature": "ring", "mapPath": "gen"},
  "mapEndzone": {"mapEndzone": "disc", "mapPath": "gen"},
  "mapEndzoneRadius": {"mapEndzoneRadius": 100, "mapEndzone": "disc",
                       "mapPath": "gen"},
  "visionConeDeg": {"visionConeDeg": 45}
}"""

suite "league manifest config_schema vs GameConfig":
  let
    schema = manifestSchema(ManifestName)
    samples = block:
      # mapSpec's payload must be a FULL, valid map object — config.update
      # resolves it (mapFromSpecJson) rather than storing it blind — so build
      # one from a generated map instead of inlining a huge literal.
      var s = parseJson(SampleJson)
      let spec = mapSpecJson(generateMapAttempt(
        1, MapGenOverrides(size: "small", windows: -1, pits: -1, pitDensity: -1)))
      s["mapSpec"] = %*{"mapSpec": parseJson(spec)}
      s

  test "every schema property is consumed by config.update":
    for key, _ in schema["properties"]:
      if key in PlatformOnlyKeys:
        continue
      check samples.hasKey(key)  # every schema key needs a payload below
      if not samples.hasKey(key):
        continue
      let payload = samples[key]
      check payload.hasKey(key)  # the payload must exercise its own key
      var config = defaultGameConfig()
      config.minPlayers = 1
      config.update($payload)
      # A consumed key must change SOMETHING relative to the defaults.
      check config != defaultGameConfig()

  test "every sample corresponds to a schema property (no stale samples)":
    for key, _ in samples:
      check schema["properties"].hasKey(key)

  test "perks schema declares the engine's perk vocabulary, in sync with its prose":
    # The platform's campaign perk picker reads the machine-readable
    # perkVocabulary block (falling back to parsing the description's
    # "Vocabulary: name (effect), …" sentence), so the block must exist,
    # cover EXACTLY the engine's perk names, and restate what the prose
    # says — a perk added to the engine, or an edit to a perk's "name
    # (effect)" phrase in the description, fails here instead of silently
    # desyncing the picker.
    let
      perksSchema = schema["properties"]["perks"]
      vocabulary = perksSchema["perkVocabulary"]
      description = perksSchema["description"].getStr
    # require, not check: a short block must abort here with the length
    # mismatch, not fall into an IndexDefect on the per-perk loop below.
    require vocabulary.len == PerkNames.len
    for perk in Perk:
      let entry = vocabulary[ord(perk)]
      check entry["id"].getStr == PerkNames[perk]
      let effect = entry["effect"].getStr
      check effect.len > 0
      check (entry["id"].getStr & " (" & effect & ")") in description

  test "platform-only keys are documented as such in the schema":
    for key in PlatformOnlyKeys:
      let description = schema["properties"][key]["description"].getStr
      check "platform" in description

  test "the repo's local config.json loads and validates":
    # update() runs the full field validation internally and raises on any
    # rejected value, so a clean call IS the validation.
    var config = defaultGameConfig()
    config.update(readFile(GameDir / "config.json"))

  test "published variants are the battle-royale identities":
    var variantIds: seq[string]
    for variant in parseFile(GameDir / ManifestName)["variants"]:
      variantIds.add variant["id"].getStr()
    check variantIds == @["br-12", "br-16"]
    for variant in parseFile(GameDir / ManifestName)["variants"]:
      let gameConfig = variant["game_config"]
      check gameConfig["mode"].getStr() == "ffa"
      check gameConfig["numPlayers"].getInt() in [12, 16]
      check gameConfig["num_agents"].getInt() == gameConfig["numPlayers"].getInt()
      check gameConfig["minPlayers"].getInt() == gameConfig["numPlayers"].getInt()
      check gameConfig["mapPath"].getStr() == "gen"
      var config = defaultGameConfig()
      config.update($gameConfig)
      check config.mode == FfaMode
      check config.numPlayers == gameConfig["numPlayers"].getInt()
      check config.minPlayers == config.numPlayers
