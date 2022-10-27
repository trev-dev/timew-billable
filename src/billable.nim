import std/[strutils, re, sequtils]

type
  ClientSpecificRate = tuple[client: string, rate: float]
  Config = tuple
    projectMarker: string
    billable: float
    clients: seq[ClientSpecificRate]

const CONFIG_DEFAULTS = Config(
const CONFIG_DEFAULTS: Config = (
  projectMarker: "#",
  billable: 0.0,
  clients: @[],
  descriptionMarker:"",
  locale: ""
)

func stripStr(s: string): string = strip s

func coerceFloat(s:string): float =
  try:
    return parseFloat(s)
  except ValueError as e:
    assert(
      false,
      "Failed to parse config! Value " & s & " should be a float type."
    )

proc createConfig(keys: seq[string]): Config =
  var conf = CONFIG_DEFAULTS
  for i in keys:
    let kvpair = map(split(i, ":", 1), proc (s:string):string = strip s)
    if kvpair[1] == "": continue

    let conf_keys = split(kvpair[0], ".", 1)
    if len(conf_keys) == 1:
      conf.billable = coerceFloat(kvpair[1])

    else:
      case conf_keys[1]:
        of "project_marker": conf.projectMarker = kvpair[1]
        else:
          let rate = coerceFloat(kvpair[1])
          add(conf.clients, (client: conf_keys[1], rate: rate))
  return conf

let data = split(readAll(stdin), "\n\n")
let headerKeys = findAll(data[0], re"(^|\n)billable.*")
let strippedKeys = map(headerKeys, proc (s: string):string = strip s)
let config = createConfig(strippedKeys)

