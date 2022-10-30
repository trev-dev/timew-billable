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
    let message = "Failed to parse config! Value " &
      s & " should be a float type."
    assert(false, message)

func createConfig(keys: seq[string]): Config =
  var conf: Config
  conf.projectMarker = "#"

  for i in keys:
    let kvpair = i
      .split(":", 1)
      .map(proc (s:string):string = strip s)

    if kvpair[1] == "": continue

    let conf_keys = kvpair[0].split(".", 1)
    if len(conf_keys) == 1:
      conf.billable = coerceFloat kvpair[1]

    else:
      case conf_keys[1]
        of "project_marker": conf.projectMarker = kvpair[1]
        else:
          let rate = coerceFloat kvpair[1]
          conf.clients.add (client: conf_keys[1], rate: rate)
  return conf

func parseEntryHierarchy(tags: seq[string], pMarker: string): seq[string] =
  # TODO: Maybe validate taskName based on whitespace
  if tags[0].startsWith pMarker:
    let projectHierarchy = tags[0][pMarker.len..^1].split "."
    let taskName = tags[1]
    result = projectHierarchy.concat @[taskName]
  else:
    result.add tags[0]

proc addRow(table: Table, entry: RawTimeEntry, config: Config) =
  let hierarchy = entry.tags.parseEntryHierarchy config.projectMarker
  let levels = hierarchy.len - 1
  echo hierarchy

proc prepareTable(config: Config, rawEntries: RawTimewEntries): Table =
  for entry in rawEntries.items:
    result.addRow(entry, config)

func stripString(s:string):string = s.strip()

let rawConfigAndEntries = readAll(stdin).split "\n\n"

let configStrings = rawConfigAndEntries[0]
  .findAll(re"(^|\n)billable.*")
  .map(stripString)

let config = createConfig configStrings

let jsonData = rawConfigAndEntries[1].fromJson RawTimewEntries

discard config.prepareTable jsonData

