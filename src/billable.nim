import std/[strutils, re, sequtils, times, math, strformat, terminal]
import jsony, nancy, termstyle

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
  # TODO: Figure out why parse may cause side effects
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
    TableRow(name: "Total", hours: result.totalHours, cost: result.totalCost)
  result.add totals

proc addNestedTerminalRows(
  tt: var TerminalTable, t: Table, level = 0, sep = @["%SEP%"]
) =
  for i, row in t.pairs:
    var spacing: string
    let marker = "—"
    if level > 0:
      spacing = " "
    if level == 0 and i != 0:
      tt.add sep
    tt.add @[
      fmt"{marker.repeat(level)}{spacing}{row.name.blue}",
      fmt"{row.hours:.3f}".yellow,
      fmt"{row.cost:.2f}".green
    ]
    tt.addNestedTerminalRows(row.subtasks, level + 1)

template printSeparator(position: untyped): untyped =
  ## Copied from nancy.printSeparator as it is currently not exported.
  stdout.write seps.`position Left`
  for i, size in sizes:
    stdout.write seps.horizontal.repeat(size + 2)
    if i != sizes.high:
      stdout.write seps.`position Middle`
    else:
      stdout.write seps.`position Right` & "\n"

proc echoBillableTable(
  table: TerminalTable, maxSize = terminalWidth(), seps = boxSeps
) =
  ## A modified version of nancy.echoTableSeps that only adds center separators
  ## between grouped top-level rows.
  let sizes = table.getColumnSizes(maxSize - 4, padding = 3)
  printSeparator(top)
  for k, entry in table.entries(sizes):
    var separator = false
    for _, row in entry():
      for i, cell in row():
        separator = cell.find(re"%SEP%") > -1 and i == 0
        if separator: break

        if i == 0: stdout.write seps.vertical & " "
        stdout.write cell &
          (if i != sizes.high: " " & seps.vertical & " " else: "")
      if not separator:
        stdout.write " " & seps.vertical & "\n"
    if separator:
      printSeparator center
  printSeparator(bottom)

proc render(tableRows: Table) =
  var table: TerminalTable
  let subtotals = tableRows[0..^2]
  let totals = tableRows[^1]

  table.add @["Task".bold, "Hours".bold, "Amount".bold]
  table.add @["%SEP%"]
  table.addNestedTerminalRows subtotals
  table.add @["%SEP%"]
  table.add @[
    fmt"{totals.name}".blue.bold,
    fmt"{totals.hours:.3f}".yellow.bold,
    fmt"{totals.cost:.2f}".green.bold
  ]

  table.echoBillableTable 80

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
