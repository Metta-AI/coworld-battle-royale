import std/unittest, ctf/sim

suite "FFA roster-derived seat count":
  test "derives numPlayers and minPlayers from players":
    var config = defaultGameConfig()
    config.update("""{
      "mode": "ffa",
      "players": [{"name": "one"}, {"name": "two"}, {"name": "three"}, {"name": "four"}],
      "tokens": ["one", "two"]
    }""")
    check config.numPlayers == 4
    check config.minPlayers == 4

  test "derives numPlayers and minPlayers from tokens":
    var config = defaultGameConfig()
    config.update("""{
      "mode": "ffa",
      "tokens": ["one", "two", "three"]
    }""")
    check config.numPlayers == 3
    check config.minPlayers == 3

  test "explicit numPlayers wins over the roster":
    var config = defaultGameConfig()
    config.update("""{
      "mode": "ffa",
      "players": [{"name": "one"}, {"name": "two"}, {"name": "three"}],
      "numPlayers": 4
    }""")
    check config.numPlayers == 4
    check config.minPlayers == 4

  test "rejects an out-of-bounds derived seat count":
    var config = defaultGameConfig()
    expect CtfError:
      config.update("""{
        "mode": "ffa",
        "players": [{"name": "only"}]
      }""")

  test "does not derive an FFA seat count in CTF mode":
    var config = defaultGameConfig()
    config.update("""{
      "players": [{"name": "one"}, {"name": "two"}, {"name": "three"}],
      "tokens": ["one", "two", "three"]
    }""")
    check config.mode == CtfMode
    check config.numPlayers == 0
    check config.minPlayers == MinPlayers
