import
  std/[json, math, os, strutils]

const
  BetaEpsilon = 3.0e-14
  BetaIterations = 200
  BetaTiny = 1.0e-300
  Confidence = 0.95

type
  BattleRoyaleError = object of CatchableError

proc betaFraction(a, b, x: float): float
    {.raises: [BattleRoyaleError].} =
  ## Evaluates the incomplete beta continued fraction.
  let
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
  var
    c = 1.0
    d = 1.0 - qab * x / qap
  if abs(d) < BetaTiny:
    d = BetaTiny
  d = 1.0 / d
  var h = d
  for m in 1 .. BetaIterations:
    let
      mFloat = float(m)
      m2 = 2.0 * mFloat
    var aa = mFloat * (b - mFloat) * x /
      ((qam + m2) * (a + m2))
    d = 1.0 + aa * d
    if abs(d) < BetaTiny:
      d = BetaTiny
    c = 1.0 + aa / c
    if abs(c) < BetaTiny:
      c = BetaTiny
    d = 1.0 / d
    h *= d * c
    aa = -(a + mFloat) * (qab + mFloat) * x /
      ((a + m2) * (qap + m2))
    d = 1.0 + aa * d
    if abs(d) < BetaTiny:
      d = BetaTiny
    c = 1.0 + aa / c
    if abs(c) < BetaTiny:
      c = BetaTiny
    d = 1.0 / d
    let delta = d * c
    h *= delta
    if abs(delta - 1.0) <= BetaEpsilon:
      return h
  raise newException(
    BattleRoyaleError,
    "incomplete beta fraction did not converge"
  )

proc regularizedBeta(a, b, x: float): float
    {.raises: [BattleRoyaleError].} =
  ## Evaluates the regularized incomplete beta function.
  if x <= 0.0:
    return 0.0
  if x >= 1.0:
    return 1.0
  let front = exp(
    lgamma(a + b) - lgamma(a) - lgamma(b) +
    a * ln(x) + b * ln(1.0 - x)
  )
  if x < (a + 1.0) / (a + b + 2.0):
    return front * betaFraction(a, b, x) / a
  result = 1.0 - front * betaFraction(b, a, 1.0 - x) / b

proc studentCdf(t, degrees: float): float
    {.raises: [BattleRoyaleError].} =
  ## Evaluates the Student t cumulative distribution function.
  let
    x = degrees / (degrees + t * t)
    tail = 0.5 * regularizedBeta(degrees / 2.0, 0.5, x)
  if t >= 0.0:
    result = 1.0 - tail
  else:
    result = tail

proc criticalT(degrees: float): float
    {.raises: [BattleRoyaleError].} =
  ## Returns the two-sided 95 percent Student t critical value.
  let target = 0.5 + Confidence / 2.0
  var
    low = 0.0
    high = 16.0
  for i in 0 ..< 80:
    let middle = (low + high) / 2.0
    if studentCdf(middle, degrees) < target:
      low = middle
    else:
      high = middle
  result = (low + high) / 2.0

proc scoresFor(
  jsonPaths: string,
  policyLabel: string
): seq[float] {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Extracts one policy's scores from hosted XP episode JSON files.
  for jsonPath in jsonPaths.split(','):
    let episodes = parseFile(jsonPath)
    if episodes.kind != JArray:
      raise newException(
        BattleRoyaleError,
        "hosted XP episode JSON is not an array: " & jsonPath
      )
    for episode in episodes:
      var position = -1
      for participant in episode["participants"]:
        if participant["label"].getStr() == policyLabel:
          position = participant["position"].getInt()
          break
      if position < 0:
        raise newException(
          BattleRoyaleError,
          "policy is absent from hosted XP episode: " & policyLabel
        )
      var found = false
      for item in episode["participant_scores"]:
        if item["position"].getInt() == position:
          result.add(item["score"].getFloat())
          found = true
          break
      if not found:
        raise newException(
          BattleRoyaleError,
          "policy score is absent from hosted XP episode: " & policyLabel
        )

proc mean(values: seq[float]): float {.raises: [BattleRoyaleError].} =
  ## Returns the arithmetic mean of a non-empty score sequence.
  if values.len == 0:
    raise newException(BattleRoyaleError, "score sequence is empty")
  for value in values:
    result += value
  result /= float(values.len)

proc sampleVariance(
  values: seq[float],
  average: float
): float {.raises: [BattleRoyaleError].} =
  ## Returns the unbiased sample variance of hosted scores.
  if values.len < 2:
    raise newException(
      BattleRoyaleError,
      "at least two hosted scores are required"
    )
  for value in values:
    let delta = value - average
    result += delta * delta
  result /= float(values.len - 1)

proc compare(
  baselineScores: seq[float],
  candidateScores: seq[float]
) {.raises: [BattleRoyaleError].} =
  ## Prints a two-sided 95 percent Welch interval and verdict.
  let
    baselineMean = mean(baselineScores)
    candidateMean = mean(candidateScores)
    baselineVariance = sampleVariance(baselineScores, baselineMean)
    candidateVariance = sampleVariance(candidateScores, candidateMean)
    baselineTerm = baselineVariance / float(baselineScores.len)
    candidateTerm = candidateVariance / float(candidateScores.len)
    error = sqrt(baselineTerm + candidateTerm)
    difference = candidateMean - baselineMean
  if error <= 0.0:
    raise newException(BattleRoyaleError, "Welch standard error is zero")
  let
    degrees = (baselineTerm + candidateTerm) ^ 2 /
      (
        baselineTerm ^ 2 / float(baselineScores.len - 1) +
        candidateTerm ^ 2 / float(candidateScores.len - 1)
      )
    statistic = difference / error
    critical = criticalT(degrees)
    lower = difference - critical * error
    upper = difference + critical * error
    probability = 2.0 * (1.0 - studentCdf(abs(statistic), degrees))
    verdict =
      if lower > 0.0:
        "significant improvement"
      else:
        "inconclusive"
  echo "baseline n=", baselineScores.len,
    " mean=", formatFloat(baselineMean, ffDecimal, 4)
  echo "candidate n=", candidateScores.len,
    " mean=", formatFloat(candidateMean, ffDecimal, 4)
  echo "difference=", formatFloat(difference, ffDecimal, 4),
    " 95% CI=[", formatFloat(lower, ffDecimal, 4),
    ", ", formatFloat(upper, ffDecimal, 4), "]"
  echo "Welch t=", formatFloat(statistic, ffDecimal, 4),
    " df=", formatFloat(degrees, ffDecimal, 3),
    " p=", formatFloat(probability, ffDecimal, 6)
  echo "verdict=", verdict

if paramCount() != 4:
  raise newException(
    BattleRoyaleError,
    "usage: compare_xp_scores BASELINE_LABEL BASELINE_JSONS " &
    "CANDIDATE_LABEL CANDIDATE_JSONS"
  )

let
  baselineScores = scoresFor(paramStr(2), paramStr(1))
  candidateScores = scoresFor(paramStr(4), paramStr(3))

compare(baselineScores, candidateScores)
