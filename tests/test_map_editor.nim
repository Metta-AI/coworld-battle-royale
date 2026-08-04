import
  std/[base64, json, strutils, unittest],
  ctf/[map_pool, sim],
  "../tools/map_editor"

proc responseJson(response: EditorResponse): JsonNode =
  check response.contentType.startsWith("application/json")
  try:
    result = parseJson(response.body)
  except JsonParsingError:
    check false
    result = newJNull()

proc smallMapSpec(): JsonNode =
  let gameMap = generateMapAttempt(
    1001,
    MapGenOverrides(
      size: "small",
      windows: -1,
      pits: -1,
      pitDensity: -1,
    ),
  )
  parseJson(mapSpecJson(gameMap))

proc mapRequest(spec: JsonNode, overlays: seq[string] = @[]): string =
  var overlayNodes = newJArray()
  for overlay in overlays:
    overlayNodes.add %overlay
  $(%*{
    "spec": spec,
    "render": {
      "maxDimension": 160,
      "overlays": overlayNodes,
    },
  })

suite "map editor service":
  test "POST /api/map returns the complete map response":
    let
      spec = smallMapSpec()
      response = handleEditorRequest(
        "POST",
        "/api/map",
        mapRequest(spec, @[
          "protected", "pickups", "spin", "seedRegion",
          "sightlines", "reachability",
        ]),
      )
      body = response.responseJson()
    check response.status == 200
    check body["ok"].getBool()
    check body["renderScale"].getFloat() > 0
    let png = decode(body["png"].getStr())
    check png.len > 8
    check png[0 .. 7] == "\x89PNG\r\n\x1a\n"

    let validation = body["validation"]
    check validation["valid"].kind == JBool
    check validation["reason"].kind == JString
    check validation["coverPermille"].kind == JInt
    check validation["minCoverPermille"].kind == JInt
    check validation["coverPermilleMin"].getInt() == 40
    check validation["coverPermilleMax"].getInt() == 170
    check validation["openSightlineRows"].kind == JArray
    check validation["unreachableTeams"].kind == JArray
    check validation["centerReachable"].kind == JBool
    check validation["endzoneGates"].kind == JArray

    let
      gameMap = mapFromSpecJson($spec)
      derived = body["derived"]
      expanded = buildArenaObstacles(gameMap)
    check derived["teamCount"].getInt() == gameMap.teamCount()
    for field in ["x", "y", "w", "h"]:
      check derived["seedRegion"][field].kind == JInt
    check derived["anchors"].len == gameMap.teamCount()
    check derived["captureZones"].len == gameMap.teamCount()
    check derived["pickups"]["grenade"].len == 4
    check derived["pickups"]["shield"].len == gameMap.teamCount()
    check derived["pickups"]["plasmaArc"].len == gameMap.teamCount()
    check derived["pickups"]["medKitActive"].len ==
      gameMap.medKitSpawns.len
    check derived["pickups"]["medKitCandidate"].len ==
      gameMap.medKitCandidates.len
    check derived["authoredObstacleCount"].getInt() ==
      gameMap.leftObstacles.len
    check derived["expandedObstacleCount"].getInt() == expanded.len

    for zoneNode in derived["captureZones"]:
      for field in [
        "xLo", "xHi", "yLo", "yHi", "diag", "cornerX", "cornerY",
        "diagLimit", "disc", "anchorX", "anchorY", "radius",
      ]:
        check zoneNode.hasKey(field)

  test "map requests never install request geometry into process globals":
    let
      widthBefore = MapWidth
      heightBefore = MapHeight
      obstaclesBefore = ArenaObstacles
      response = handleEditorRequest(
        "POST", "/api/map", mapRequest(smallMapSpec())
      )
    check response.status == 200
    check response.responseJson()["ok"].getBool()
    check MapWidth == widthBefore
    check MapHeight == heightBefore
    check ArenaObstacles == obstaclesBefore

  test "POST /api/map reports malformed editing states as JSON":
    for requestBody in [
      "not json",
      "{}",
      $(%*{"spec": "not an object"}),
      $(%*{"spec": {"name": "missing the required fields"}}),
    ]:
      let
        response = handleEditorRequest("POST", "/api/map", requestBody)
        body = response.responseJson()
      check response.status == 200
      check not body["ok"].getBool()
      check body["error"].getStr().len > 0

  test "map request enforces render and allocation limits":
    var spec = smallMapSpec()
    spec["width"] = %(MapEditorMaxDimension + 1)
    var response = handleEditorRequest("POST", "/api/map", mapRequest(spec))
    check response.status == 200
    check not response.responseJson()["ok"].getBool()

    response = handleEditorRequest(
      "POST",
      "/api/map",
      $(%*{
        "spec": smallMapSpec(),
        "render": {"maxDimension": -1, "overlays": []},
      }),
    )
    check response.status == 200
    check not response.responseJson()["ok"].getBool()

    response = handleEditorRequest(
      "POST",
      "/api/map",
      $(%*{
        "spec": smallMapSpec(),
        "render": {"overlays": ["browserGeometry"]},
      }),
    )
    check response.status == 200
    check not response.responseJson()["ok"].getBool()

  test "POST /api/generate supports validated and raw generation":
    for validated in [false, true]:
      let
        response = handleEditorRequest(
          "POST",
          "/api/generate",
          $(%*{
            "seed": 1001,
            "teams": 2,
            "overrides": {"size": "small"},
            "validated": validated,
          }),
        )
        body = response.responseJson()
      check response.status == 200
      check body["ok"].getBool()
      check body["spec"].kind == JObject
      check body["spec"]["width"].getInt() == 1050

  test "POST /api/generate validates request fields":
    for requestBody in [
      "{}",
      $(%*{"seed": 1, "teams": 3}),
      $(%*{"seed": 1, "overrides": {"windows": "many"}}),
      $(%*{"seed": 1, "overrides": {"mystery": 1}}),
    ]:
      let
        response = handleEditorRequest(
          "POST", "/api/generate", requestBody
        )
        body = response.responseJson()
      check response.status == 200
      check not body["ok"].getBool()
      check body["error"].getStr().len > 0

  test "pool endpoints expose exact curated entries with strict bounds":
    var response = handleEditorRequest("GET", "/api/pool", "")
    var body = response.responseJson()
    check response.status == 200
    check body["count"].getInt() == MapPoolSeeds.len
    check body["seeds"].len == MapPoolSeeds.len
    for i, seed in MapPoolSeeds:
      check body["seeds"][i].getInt() == seed

    response = handleEditorRequest("GET", "/api/pool/0", "")
    body = response.responseJson()
    check response.status == 200
    check body["ok"].getBool()
    check body["spec"]["genSeed"].getInt() == MapPoolSeeds[0]

    for path in ["/api/pool/nope", "/api/pool/-1", "/api/pool/20"]:
      response = handleEditorRequest("GET", path, "")
      body = response.responseJson()
      check response.status == 200
      check not body["ok"].getBool()

  test "routing, body limits, and static paths fail clearly":
    var response = handleEditorRequest("GET", "/", "")
    check response.status == 200
    check response.contentType.startsWith("text/html")

    response = handleEditorRequest("GET", "/static/editor.css", "")
    check response.status == 200
    check response.contentType.startsWith("text/css")
    check response.body.len > 0

    response = handleEditorRequest("GET", "/static/does-not-exist.js", "")
    check response.status == 404

    response = handleEditorRequest("GET", "/static/../arena.nim", "")
    check response.status == 404
    check not response.responseJson()["ok"].getBool()

    response = handleEditorRequest("GET", "/api/map", "")
    check response.status == 405

    response = handleEditorRequest("GET", "/does-not-exist", "")
    check response.status == 404

    response = handleEditorRequest(
      "POST", "/api/map", repeat('x', MapEditorMaxBodyBytes + 1)
    )
    check response.status == 413
    check not response.responseJson()["ok"].getBool()
