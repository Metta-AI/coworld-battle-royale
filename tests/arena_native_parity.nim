## Native side of the Arena component determinism proof.

import std/[os, sequtils, strutils]
import arena/game_runtime
import baseline
import ctf/[replays, sim]

const
  ParitySeed = 0xfedcba9876543210'u64
  ParityTicks = 13
  ParityConfig = """{
    "players": [{"name": "alpha"}, {"name": "beta"}],
    "minPlayers": 2,
    "maxTicks": 12,
    "maxGames": 1
  }"""
  FfaSeats = 12
  FfaTicks = 8641

proc inputPacket(mask: uint8): string =
  result = newString(2)
  result[0] = char(0x84)
  result[1] = char(mask)

proc scriptedMask(seat, tick: int): uint8 =
  const masks = [8'u8, 0'u8, 4'u8, 0'u8, 16'u8, 0'u8]
  masks[(tick + seat) mod masks.len]

let
  ffaMode = paramCount() >= 2 and paramStr(1) == "ffa"
  outputDir = if ffaMode: paramStr(2) else: paramStr(1)
  configText =
    if ffaMode: readFile(joinPath(parentDir(currentSourcePath), "..", "config.br.json"))
    else: ParityConfig
  seats = if ffaMode: FfaSeats else: 2
  ticks = if ffaMode: FfaTicks else: ParityTicks

createDir(outputDir)
var
  game = initArenaGame(configText, seats, ParitySeed)
  replayBytes = game.takeReplayChunks().join()
  playerFrames: seq[string]
  completed = false
for tick in 0 ..< ticks:
  var actions = newSeq[SeatMessage](seats)
  for seat in 0 ..< seats:
    actions[seat] = SeatMessage(
      seat: seat,
      payload: inputPacket(
        if ffaMode: scriptedMask(seat, tick)
        elif seat == 0: uint8([8, 8, 0, 16, 0, 2][tick mod 6])
        else: uint8([4, 4, 0, 32, 0, 1][tick mod 6])))
  let output = game.step(actions)
  if output.done:
    doAssert ffaMode or tick == ticks - 1
  playerFrames.add(output.messages[0].payload)
  replayBytes.add(game.takeReplayChunks().join())
  if output.done:
    completed = true
    break
doAssert completed
let nativeResults = game.finish()
let replay = parseReplayBytes(replayBytes)
doAssert replay.joins.len == seats
doAssert replay.inputs.len > 0
doAssert replay.hashes.mapIt(it.hash) == game.hashes

var
  replayConfig = defaultGameConfig()
  replaySim: SimServer
  replayPlayer = initReplayPlayer(replay)
replayConfig.update(replay.configJson)
replaySim = initSimServer(replayConfig)
replayPlayer.mismatchQuit = true
while replayPlayer.hashIndex < replay.hashes.len:
  replayPlayer.stepReplay(replaySim)
doAssert not replayPlayer.hashValidationFailed

var
  player = initBaselineComponent(0)
  playerMasks: seq[int]
for frame in playerFrames:
  let replies = player.onMessage(frame)
  doAssert replies.len <= 1
  playerMasks.add(if replies.len == 0: -1 else: int(replies[0][1].uint8))

writeFile(joinPath(outputDir, "hashes"), game.hashes.mapIt($it).join(","))
writeFile(joinPath(outputDir, "player_masks"), playerMasks.mapIt($it).join(","))
writeFile(joinPath(outputDir, "results"), nativeResults)
