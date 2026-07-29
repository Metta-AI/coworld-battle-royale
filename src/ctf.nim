import
  std/[json, os, sysrand],
  bitworld/runtime,
  ctf/sim,
  ctf/server

const LegacyFixedSeed = 0xA6019
  ## The old compiled-in default seed. Hosted variant configs historically
  ## pinned this exact value, so it doubles as the "nobody chose a seed"
  ## sentinel: a config carrying it (or no seed at all) gets a fresh random
  ## seed — with a public fixed seed the GV25 random respawn draws would be
  ## pre-computable by opponents.

proc seedPinned(configJson: string): bool =
  ## True when the runtime config explicitly pins a seed other than the
  ## legacy default (fixture recordings, A/B batteries, forensic re-runs).
  if configJson.len == 0:
    return false
  try:
    let node = parseJson(configJson)
    node.kind == JObject and node.hasKey("seed") and
      node["seed"].getInt != LegacyFixedSeed
  except CatchableError:
    false  # config.update reports the real parse error.

proc randomSeed(): int =
  ## A crypto-random 31-bit seed from the OS.
  var buf: array[4, byte]
  if not urandom(buf):
    raise newException(CtfError, "OS entropy source unavailable")
  (int(buf[0]) shl 24 or int(buf[1]) shl 16 or
    int(buf[2]) shl 8 or int(buf[3])) and 0x7FFF_FFFF

proc limitText(value: int): string =
  ## Returns a readable text value for a numeric limit.
  if value > 0:
    $value
  else:
    "infinite"

proc echoStartupConfig(
  config: GameConfig,
  runtimeConfig: RuntimeConfig
) =
  ## Prints the effective startup config without token secrets.
  echo "CTF config: host=", runtimeConfig.host,
    " port=", runtimeConfig.port,
    " seed=", config.seed,
    " speed=", config.speed, "x",
    " minPlayers=", config.minPlayers,
    " slots=", config.slots.len,
    " maxTicks=", config.maxTicks.limitText(),
    " maxGames=", config.maxGames.limitText(),
    " map=", config.mapPath

when isMainModule:
  let
    runtimeConfig = readRuntimeConfig()
    localReplayPath =
      if runtimeConfig.replayUri.len > 0:
        getTempDir() / ("ctf-replay-" & $getCurrentProcessId() &
          ".bitreplay")
      else:
        ""

  var config = defaultGameConfig()
  config.update(runtimeConfig.config)
  if not seedPinned(runtimeConfig.config):
    config.seed = randomSeed()
    echo "seed not pinned; randomized"
  config.echoStartupConfig(runtimeConfig)
  echo "Using map file: " & config.mapPath

  let loadReplayPath =
    if runtimeConfig.replayMode:
      let path = getTempDir() / ("ctf-load-replay-" &
        $getCurrentProcessId() & ".bitreplay")
      writeFile(path, runtimeConfig.replay)
      path
    else:
      ""

  echo "starting ctf on ", runtimeConfig.host, ":", runtimeConfig.port
  runServerLoop(
    runtimeConfig.host,
    runtimeConfig.port,
    config,
    localReplayPath,
    loadReplayPath,
    "",
    runtimeConfig
  )
