import std/[math, strutils]

type
  ## represents values before and after dot as ints
  ## operates on a discrete amout of decimalPlaces, avoiding rounding weirdness
  DiscreteDecimal* = object
    decimalPlaces: int
    before: int
    after: int

## add 2 DiscreteDecimals
func `+`*(a, b: DiscreteDecimal): DiscreteDecimal =
  assert a.decimalPlaces == b.decimalPlaces, "number of decimalPlaces don't match"
  var
    before = a.before + b.before
    after = a.after + b.after
    divisor = 10 ^ a.decimalPlaces

  before += after div divisor
  after = after mod divisor

  DiscreteDecimal(before: before, after: after, decimalPlaces: a.decimalPlaces)

## add 2 DiscreteDecimals in place
func `+=`*(a: var DiscreteDecimal, b: DiscreteDecimal) =
  assert a.decimalPlaces == b.decimalPlaces, "number of decimalPlaces don't match"
  a = a + b

## multiply 2 DiscreteDecimals
func `*`*(a, b: DiscreteDecimal): DiscreteDecimal =
  assert a.decimalPlaces == b.decimalPlaces, "number of decimalPlaces don't match"
  var
    before = a.before * b.before
    before2 = a.after * b.before
    before3 = a.before * b.after
    before4 = a.after * b.after
    after: int
    divisor = 10 ^ a.decimalPlaces

  before += before2 div divisor
  after += before2 mod divisor

  before += before3 div divisor
  after += before3 mod divisor

  after += before4 div divisor

  before += after div divisor
  after = after mod divisor

  DiscreteDecimal(before: before, after: after, decimalPlaces: a.decimalPlaces)

# test 2 DiscreteDecimals for equality
func `==`*(a, b: DiscreteDecimal): bool =
  (a.before == b.before) and
  (a.after == b.after) and
  (a.decimalPlaces == b.decimalPlaces)

## new empty DiscreteDecimal, just specify decimalPlaces
func discreteDecimal*(places: int): DiscreteDecimal =
  DiscreteDecimal(before: 0, after: 0, decimalPlaces: places)

## convert int to DiscreteDecimal with specified places
func discreteDecimal*(a: int, places: int): DiscreteDecimal =
  DiscreteDecimal(before: a, after: 0, decimalPlaces: places)

## convert float to DiscreteDecimal with specified places
func discreteDecimal*(a: float, places: int): DiscreteDecimal =
  var
    before = a.floor.int
    divisor = 10 ^ places
    after = ((a - a.floor) * divisor.float).round.int

  before += after div divisor
  after = after mod divisor

  DiscreteDecimal(before: before, after: after, decimalPlaces: places)

## new DiscreteDecimal, decimalPlaces are inferred from after
func `$$`*(before, after: int): DiscreteDecimal =
  # $ has higher precedence that other operators,
  # so it works with + or * without parens
  DiscreteDecimal(
    before: before,
    after: after,
    decimalPlaces: after.float.log10.int + 1
  )

## new empty DiscreteDecimal, just specify decimalPlaces
func `$$`*(places: int): DiscreteDecimal =
  discreteDecimal(2)

## convert DiscreteDecimal to string
func `$`*(a: DiscreteDecimal): string =
  let
    existingPlaces = if a.after != 0: a.after.float.log10.int + 1 else: 1
    missingPlaces = a.decimalPlaces - existingPlaces
  result =
    $a.before &
    "." &
    (if missingPlaces > 0: "0".repeat(missingPlaces) else: "") &
    $a.after

when isMainModule:
  import sugar

  # tests:
  assert 10$$9 + 10$$9                     == 21$$8
  assert 10$$9 * 10$$9                     == 118$$8
  assert $(10.discreteDecimal 1)           == "10.0"
  assert $(10.999.discreteDecimal 1)       == "11.0"
  assert $(10.96.discreteDecimal 1)        == "11.0"
  assert $(10.95.discreteDecimal 1)        == "10.9"
  assert $(10.9111.discreteDecimal 1)      == "10.9"
  assert 10$$99 + 10$$99                   == 21$$98
  assert 10$$99 * 10$$99                   == 120$$78
  assert $(10.discreteDecimal 2)           == "10.00"
  assert $(10.99999.discreteDecimal 2)     == "11.00"
  assert $(10.996.discreteDecimal 2)       == "11.00"
  assert $(10.995.discreteDecimal 2)       == "10.99"
  assert $(10.99111.discreteDecimal 2)     == "10.99"
  assert 10$$999 + 10$$999                 == 21$$998
  assert 10$$999 * 10$$999                 == 120$$978
  assert $(10.discreteDecimal 3)           == "10.000"
  assert $(10.9999999.discreteDecimal 3)   == "11.000"
  assert $(10.9996.discreteDecimal 3)      == "11.000"
  assert $(10.9995.discreteDecimal 3)      == "10.999"
  assert $(10.999111.discreteDecimal 3)    == "10.999"
  assert $(10.099.discreteDecimal 3)       == "10.099"
  assert 10$$9999 + 10$$9999               == 21$$9998
  assert 10$$9999 * 10$$9999               == 120$$9978
  assert $(10.discreteDecimal 4)           == "10.0000"
  assert $(10.999999999.discreteDecimal 4) == "11.0000"
  assert $(10.99996.discreteDecimal 4)     == "11.0000"
  assert $(10.99995.discreteDecimal 4)     == "11.0000"
  assert $(10.9999111.discreteDecimal 4)   == "10.9999"
  assert $(10.0099.discreteDecimal 4)      == "10.0099"
