import std/[strutils, re, sequtils, times, math, strformat, terminal]
import jsony, nancy, termstyle, csvtools

type
  ClientSpecificRate = tuple[client: string, rate: float]
  Config = tuple
    projectMarker: string
    billable: float
    render: string
    csvName: string
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

  CSVRow = object
    name, hours, cost: string

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
  conf.render = "terminal"
  conf.csvName = "billable-report.csv"

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
        of "render": conf.render = kvpair[1]
        of "csvName": conf.csvName = kvpair[1]
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
  (ceil(d.inSeconds.toBiggestFloat / 60.0 / 60.0 * 100)) / 100

func billableRate(c: Config, e: RawTimeEntry): float =
  for c in c.clients.items:
    if e.tags.find(c.client) > -1:
      return c.rate
  return c.billable

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

  let rate = config.billableRate entry
  let hours = entry.parseDuration.toBillableHours
  newRow.hours += hours
  newRow.cost += round(hours * rate, 2)

  if nextTasks.len > 0:
    newRow.subtasks.addOrUpdateRow(entry, nextTasks, config)

  if rowExists:
    table[idx] = newRow
  else:
    table.add newRow

proc prepareTable(config: Config, rawEntries: RawTimewEntries): Table =
  for entry in rawEntries.items:
    let entryHierarcy = entry.tags.parseEntryHierarchy config.projectMarker
    result.addOrUpdateRow(entry, entryHierarcy, config)

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
      fmt"{marker.repeat(level)}{spacing}{row.name.yellow}",
      fmt"{row.hours:.2f}".blue,
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

proc renderTerminalTable(tableRows: Table) =
  var table: TerminalTable
  let subtotals = tableRows[0..^2]
  let totals = tableRows[^1]

  table.add @["Task".bold, "Hours".bold, "Amount".bold]
  table.add @["%SEP%"]
  table.addNestedTerminalRows subtotals
  table.add @["%SEP%"]
  table.add @[
    fmt"{totals.name}".yellow.bold,
    fmt"{totals.hours:.2f}".blue.bold,
    fmt"{totals.cost:.2f}".green.bold
  ]

  table.echoBillableTable 80

func loadCSVTable(t: Table): seq[CSVRow] =
  for row in t.items:
    let csvRow = CSVRow(
      name: row.name, hours: fmt"{row.hours:.2f}", cost: fmt"{row.cost:.2f}"
    )
    result.add csvRow
    result.add(loadCSVTable(row.subtasks))

proc renderCSV(tableRows: Table, config: Config) =
  let report = loadCSVTable tableRows
  report.writeToCsv config.csvName
  echo fmt"CSV file created: {config.csvName.green}"

proc main() =
  let rawConfigAndEntries = readAll(stdin).split "\n\n"

  let configStrings = rawConfigAndEntries[0]
    .findAll(re"(^|\n)billable.*")
    .map(stripString)

  let config = createConfig configStrings
  let jsonData = rawConfigAndEntries[1].fromJson RawTimewEntries
  let table = config.prepareTable jsonData

  case config.render
    of "csv":
      table.renderCSV(config)
    of "terminal":
      table.renderTerminalTable()
    else:
      table.renderTerminalTable()

when isMainModule:
  main()
