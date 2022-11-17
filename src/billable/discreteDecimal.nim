import std/[math, strutils]

type
  ## Represents values before and after dot as integers. Operates on a discrete
  ## amount of decimal places. Avoids rounding weirdness
  DiscreteDecimal* = object
    places: int
    whole: int
    decimal: int

func `+`*(a, b: DiscreteDecimal): DiscreteDecimal =
  assert a.places == b.places, "number of decimal places don't match"
  var
    whole = a.whole + b.whole
    decimal = a.decimal + b.decimal
    divisor = 10 ^ a.places

  whole += decimal div divisor
  decimal = decimal mod divisor

  DiscreteDecimal(whole: whole, decimal: decimal, places: a.places)

func `+=`*(a: var DiscreteDecimal, b: DiscreteDecimal) =
  assert a.places == b.places, "number of decimal places don't match"
  a = a + b

func `*`*(a, b: DiscreteDecimal): DiscreteDecimal =
  assert a.places == b.places, "number of decimal places don't match"
  var
    whole = a.whole * b.whole
    whole2 = a.decimal * b.whole
    whole3 = a.whole * b.decimal
    whole4 = a.decimal * b.decimal
    decimal: int
    divisor = 10 ^ a.places

  whole += whole2 div divisor
  decimal += whole2 mod divisor

  whole += whole3 div divisor
  decimal += whole3 mod divisor

  decimal += whole4 div divisor

  whole += decimal div divisor
  decimal = decimal mod divisor

  DiscreteDecimal(whole: whole, decimal: decimal, places: a.places)

func `==`*(a, b: DiscreteDecimal): bool =
  (a.whole == b.whole) and
  (a.decimal == b.decimal) and
  (a.places == b.places)

func discreteDecimal*(places: int): DiscreteDecimal =
  DiscreteDecimal(whole: 0, decimal: 0, places: places)

func discreteDecimal*(a: int, places: int): DiscreteDecimal =
  DiscreteDecimal(whole: a, decimal: 0, places: places)

func discreteDecimal*(a: float, places: int): DiscreteDecimal =
  var
    whole = a.floor.int
    divisor = 10 ^ places
    decimal = ((a - a.floor) * divisor.float).round.int

  whole += decimal div divisor
  decimal = decimal mod divisor

  DiscreteDecimal(whole: whole, decimal: decimal, places: places)

## Create a DiscreteDecimal by inferring the number of places from the
## decimal part. Uses a special operator `$$`.
##
## Example: `let discrete = 42$$00` => 42.00
func `$$`*(whole, decimal: int): DiscreteDecimal =
  DiscreteDecimal(
    whole: whole,
    decimal: decimal,
    places: decimal.float.log10.int + 1
  )

## New empty DiscreteDecimal using the special `$$` operator.
##
## Example: `let empty = $$ 2` => 0.00
func `$$`*(places: int): DiscreteDecimal =
  discreteDecimal(2)

func `$`*(a: DiscreteDecimal): string =
  let
    existingPlaces = if a.decimal != 0: a.decimal.float.log10.int + 1 else: 1
    missingPlaces = a.places - existingPlaces
  result =
    $a.whole &
    "." &
    (if missingPlaces > 0: "0".repeat(missingPlaces) else: "") &
    $a.decimal

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
