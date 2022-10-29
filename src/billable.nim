import std/[strutils, re, sequtils]
import jsony

type
  ClientSpecificRate = tuple[client: string, rate: float]
  Config = tuple
    projectMarker: string
    billable: float
    clients: seq[ClientSpecificRate]

  RawTimeEntry =
    tuple[id: int, start: string, `end`: string, tags: seq[string]]
  RawTimewEntries = seq[RawTimeEntry]

  TimeEntry = tuple[name: string, hours: float, cost: float, rate: float]
  Table = seq[seq[TimeEntry]]

func coerceFloat(s:string): float =
  try:
    return parseFloat(s)
  except ValueError:
    assert(
      false,
      "Failed to parse config! Value " & s & " should be a float type."
    )

func createConfig(keys: seq[string]): Config =
  var conf: Config
  conf.projectMarker = "#"

  for i in keys:
    let kvpair = map(split(i, ":", 1), proc (s:string):string = strip s)
    if kvpair[1] == "": continue

    let conf_keys = split(kvpair[0], ".", 1)
    if len(conf_keys) == 1:
      conf.billable = coerceFloat(kvpair[1])

    else:
      case conf_keys[1]
        of "project_marker": conf.projectMarker = kvpair[1]
        else:
          let rate = coerceFloat(kvpair[1])
          add(conf.clients, (client: conf_keys[1], rate: rate))
  return conf

func parseEntryHierarchy(tags: seq[string], pMarker: string): seq[string] =
  # TODO: Maybe validate taskName based on whitespace
  if tags[0].startsWith pMarker:
    let projectHierarchy = tags[0][pMarker.len..^1].split "."
    let taskName = tags[1]
    result = projectHierarchy.concat @[taskName]
  else:
    result.add tags[0]

func updateTableRow(
  table: Table, hierarchy: seq[string], entry: RawTimeEntry
): seq[TimeEntry] =
  let levels = hierarchy.len

func prepareTableData(config: Config, rawEntries: RawTimewEntries): Table =
  var table: Table = @[]
  for i in 0 ..< rawEntries.len:
    let entry = rawEntries[i]
    let hierarchy = entry.tags.parseEntryHierarchy config.projectMarker

  return table

func stripString(s:string):string = s.strip()

let rawConfigAndEntries = readAll(stdin).split("\n\n")

let configStrings = rawConfigAndEntries[0]
  .findAll(re"(^|\n)billable.*")
  .map(stripString)

let config = createConfig(configStrings)

let jsonData = rawConfigAndEntries[1].fromJson(RawTimewEntries)

discard config.prepareTableData jsonData

