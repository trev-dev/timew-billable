import std/[strutils, re, sequtils, times, math, strformat]
import jsony, nancy

type
  ClientSpecificRate = tuple[client: string, rate: float]
  Config = tuple
    projectMarker: string
    billable: float
    clients: seq[ClientSpecificRate]

  RawTimeEntry =
    tuple[id: int, start: string, `end`: string, tags: seq[string]]
  RawTimewEntries = seq[RawTimeEntry]

  Table = seq[TableRow]
  TableRow = object
    name: string
    hours: float
    cost: float
    subtasks: seq[TableRow]

func stripString(s:string):string = s.strip()

func coerceFloat(s:string): float =
  try:
    return parseFloat(s)
  except ValueError:
    let message =
      fmt "Failed to parse config! Value {s} should be a float type."
    assert(false, message)

func createConfig(keys: seq[string]): Config =
  var conf: Config
  conf.projectMarker = "#"

  for i in keys:
    let kvpair = i
      .split(":", 1)
      .map(stripString)

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

func find[T](s: seq[T], pred: proc (i: T): bool): int =
  result = -1
  for idx, itm in s.pairs:
    if pred(itm):
      return idx

func findByName[T](s: seq[T], n: string): int =
  result = s.find(proc (r: TableRow): bool = r.name == n)

func toBillableHours(d: Duration): float =
  round(d.inSeconds.toBiggestFloat / 60.0 / 60.0, 3)

func billableRate(c: Config, e: RawTimeEntry): float =
  for c in c.clients.items:
    if e.tags.find(c.client) > -1:
      return c.rate
  return c.billable

func subTotalHours(r: var TableRow): float =
  result = r.hours
  for task in r.subtasks.mitems:
    task.hours = task.subTotalHours()
    result += task.hours

func subTotalCost(r: var TableRow): float =
  result = r.cost
  for task in r.subtasks.mitems:
    task.cost = task.subTotalCost()
    result += task.cost

func totalCost(t: Table): float =
  for row in t:
    result += row.cost

func totalHours(t: Table): float =
  for row in t:
    result += row.hours

proc parseDuration(e: RawTimeEntry): Duration =
  let fmt = initTimeFormat "yyyyMMdd'T'HHmmss'Z'"
  let stime = e.start.parse fmt
  let etime = e.`end`.parse fmt
  etime - stime

proc addOrUpdateRow(
  table: var Table,
  entry: RawTimeEntry,
  hierarchy: seq[string],
  config: Config
) =
  let taskName = hierarchy[0]
  let nextTasks = hierarchy[1..^1]
  let idx = table.findByName taskName
  let rowExists = idx > -1

  var newRow: TableRow
  if rowExists:
    newRow = table[idx]
  else:
    newRow = TableRow(name: taskName)

  if nextTasks.len > 0:
    newRow.subtasks.addOrUpdateRow(entry, nextTasks, config)
  else:
    let rate = config.billableRate entry
    let hours = entry.parseDuration.toBillableHours
    newRow.hours += hours
    newRow.cost += round(hours * rate, 2)

  if rowExists:
    table[idx] = newRow
  else:
    table.add newRow

proc prepareTable(config: Config, rawEntries: RawTimewEntries): Table =
  for entry in rawEntries.items:
    let entryHierarcy = entry.tags.parseEntryHierarchy config.projectMarker
    result.addOrUpdateRow(entry, entryHierarcy, config)

  for row in result.mitems:
    row.cost = row.subTotalCost()
    row.hours = row.subTotalHours()

  let totals =
    TableRow(name: "TOTAL", hours: result.totalHours, cost: result.totalCost)
  result.add totals

proc loadTerminalTable(tt: var TerminalTable, t: Table, level: int = 0) =
  for row in t.items:
    var spacing: string
    let marker = "—"
    if level > 0:
      spacing = " "
    tt.add @[
      fmt"{marker.repeat(level)}{spacing}{row.name}",
      fmt"{row.hours:.3f}",
      fmt"{row.cost:.2f}"
    ]
    tt.loadTerminalTable(row.subtasks, level + 1)

proc render(tableRows: Table) =
  var table: TerminalTable
  table.loadTerminalTable tableRows
  table.echoTable 80

proc main() =
  let rawConfigAndEntries = readAll(stdin).split "\n\n"

  let configStrings = rawConfigAndEntries[0]
    .findAll(re"(^|\n)billable.*")
    .map(stripString)

  let config = createConfig configStrings
  let jsonData = rawConfigAndEntries[1].fromJson RawTimewEntries
  let table = config.prepareTable jsonData
  table.render()
  
when isMainModule:
  main()
