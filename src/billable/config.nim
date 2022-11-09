import std/[strutils, sequtils, strformat]
type
  RenderKind* = enum rkTerminal = "terminal", rkCsv = "csv"
  ClientSpecificRate = tuple[client: string, rate: float]
  Config = object
    projectMarker*: string
    taskMarker*: string
    billable*: float
    render*: RenderKind
    csvName*: string
    depthMarker*: string
    clients*: seq[ClientSpecificRate]

const defaultConfig = Config(
  projectMarker: "#",
  taskMarker: "",
  billable: 0,
  render: rkTerminal,
  csvName: "billable-report.csv",
  clients: @[],
  depthMarker: "—",
)

var config = defaultConfig

func coerceFloat(s: string): float =
  try:
    return parseFloat(s)
  except ValueError:
    assert false, &"Failed to parse config! Value {s} should be a float type."

proc updateConfig*(keys: seq[string]) =
  for i in keys:
    let kvpair = i
      .split(":", 1)
      .mapIt(it.strip)

    if kvpair[1] == "": continue

    let confKeys = kvpair[0].split(".", 1)
    if len(confKeys) == 1:
      config.billable = coerceFloat kvpair[1]

    else:
      case confKeys[1].toLowerAscii.replace("_", "")
        of "projectmarker": config.projectMarker = kvpair[1]
        of "taskmarker": config.taskMarker = kvpair[1]
        of "render": config.render = parseEnum[RenderKind](kvpair[1])
        of "csvname": config.csvName = kvpair[1]
        of "depthmarker": config.depthMarker = kvpair[1]
        else:
          let rate = coerceFloat kvpair[1]
          config.clients.add (client: confKeys[1], rate: rate)

proc getConfig*(): Config =
  config
