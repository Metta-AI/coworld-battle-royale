import std/unittest

include ../src/ctf/server

suite "human seat client":
  test "player-client aliases serve the human-seat page":
    for route in [
      bitworldClient.PlayerClientRoute,
      bitworldClient.PlayerClientHtmlRoute,
      "/client/player_client.html",
      bitworldClient.CoworldPlayerClientRoute
    ]:
      # A route falling through to the global client silently gives a human
      # spectator vision instead of the seat's fog-gated observation.
      let servedBody = humanSeatClientBody(route, "GET")
      check servedBody.len > 0
      check servedBody.contains("Battle Royale — live play")
      check servedBody.contains("window.__humanSeat")
      # A non-GET request must not silently turn into an HTML player page.
      check humanSeatClientBody(route, "POST") == ""

  test "served page receives engine wire constants":
    # Missing splicing silently leaves browser timing and sprite IDs out of
    # sync with the engine that produced the stream.
    check EmbeddedHumanSeatHtml.contains("window.CTF_WIRE")

  test "input packets preserve all eight input bits":
    # Masking to seven bits silently disables C, the grenade/barrier action.
    check EmbeddedHumanSeatHtml.contains("mask & 255")
    check not EmbeddedHumanSeatHtml.contains("&127")
    check not EmbeddedHumanSeatHtml.contains("& 127")
    check EmbeddedHumanSeatHtml.contains(
      "const IN_UP = 1, IN_DOWN = 2, IN_LEFT = 4, IN_RIGHT = 8,"
    )
    check EmbeddedHumanSeatHtml.contains(
      "IN_SELECT = 16, IN_A = 32, IN_B = 64, IN_C = 128;"
    )
    check EmbeddedHumanSeatHtml.contains("CLIENT_INPUT = 0x84")
    check EmbeddedHumanSeatHtml.contains(
      "new Uint8Array([CLIENT_INPUT, mask & 255])"
    )

  test "chat packets retain the in-sim shout path and cap":
    # Dropping the chat packet or its cap silently changes recorded gameplay
    # and permits messages outside the protocol's ten-character contract.
    check EmbeddedHumanSeatHtml.contains("CLIENT_CHAT = 0x81")
    check EmbeddedHumanSeatHtml.contains("SHOUT_MAX = 10")
    check EmbeddedHumanSeatHtml.contains("bytes[0] = CLIENT_CHAT")

  test "page never opens the spectator stream":
    # Referencing the global stream silently bypasses the player's fog-of-war
    # and exposes information unavailable to a policy seat.
    check not EmbeddedHumanSeatHtml.contains("/global")
