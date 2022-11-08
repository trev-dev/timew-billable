import std/[strutils, re, sequtils, times, math, strformat, terminal]
import jsony, nancy, termstyle, csvtools

type
  ClientSpecificRate = tuple[client: string, rate: float]

  RenderKind = enum rkTerminal = "terminal", rkCsv = "csv"

  Config = object
    projectMarker: string
    taskMarker: string
    billable: float
    render: RenderKind
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

const defaultConfig = Config(
  projectMarker: "#",
  taskMarker: "",
  billable: 0,
  render: rkTerminal,
  csvName: "billable-report.csv",
  clients: @[],
)

var config = defaultConfig

func stripString(s:string):string = s.strip()

func coerceFloat(s:string): float =
  try:
    return parseFloat(s)
  except ValueError:
    let message =
      fmt "Failed to parse config! Value {s} should be a float type."
    assert(false, message)

func find[T](s: seq[T], pred: proc (i: T): bool{.noSideEffect.}): int =
  result = -1
  for idx, itm in s.pairs:
    if pred(itm):
      return idx

func findByString[T](s: seq[T], sub: char|string): int =
  result = -1
  for idx, itm in s.pairs:
    if itm.find(sub) > -1:
      return idx

func findConfTag(t: seq[string], prefix = config.projectMarker): int =
  t.find proc (s: string): bool = s.startsWith prefix

proc findTaskName(t: seq[string], prefix = config.taskMarker): int =
  result = -1
  if prefix != "":
    result = t.findConfTag prefix
  if result == -1:
    result = t.findByString ' '

proc updateConfig(keys: seq[string]) =

  for i in keys:
    let kvpair = i
      .split(":", 1)
      .map(stripString)

    if kvpair[1] == "": continue

    let confKeys = kvpair[0].split(".", 1)
    if len(confKeys) == 1:
      config.billable = coerceFloat kvpair[1]

    else:
      case confKeys[1] 
        of "project_marker": config.projectMarker = kvpair[1]
        of "task_marker": config.taskMarker = kvpair[1]
        of "render": config.render = parseEnum[RenderKind](kvpair[1])
        of "csv_name": config.csvName = kvpair[1]
        else:
          let rate = coerceFloat kvpair[1]
          config.clients.add (client: confKeys[1], rate: rate)

proc parseEntryHierarchy(tags: seq[string]): seq[string] =
  let project = tags.findConfTag 
  let taskName = tags.findTaskName

  if project > -1:
    let projectHierarchy = tags[project][config.projectMarker.len..^1].split "."
    result = result.concat projectHierarchy

  if taskName > -1:
    var tn = tags[taskName]
    if tn.startsWith config.taskMarker: tn = tn[config.taskMarker.len..^1]
    result.add tn
  else:
    result.add (if project <= 0: tags[0] else: tags[project + 1])

func toBillableHours(d: Duration): float =
  (d.inSeconds.float / 3600 * 100).round / 100

proc billableRate(e: RawTimeEntry): float =
  for c in config.clients:
    if e.tags.find(c.client) > -1:
      return c.rate
  return config.billable

func totalCost(t: Table): float =
  for row in t:
    result += row.cost

func totalHours(t: Table): float =
  for row in t:
    result += row.hours

proc parseDuration(e: RawTimeEntry): Duration =
  let f = initTimeFormat "yyyyMMdd'T'HHmmss'Z'"
  let stime = e.start.parse f
  var etime = stime

  if e.`end` != "":
    etime = e.`end`.parse f

  etime - stime

proc addOrUpdateRow(
  table: var Table,
  entry: RawTimeEntry,
  hierarchy: seq[string],
) =
  let taskName = hierarchy[0]
  let nextTasks = hierarchy[1..^1]
  let idx = table.find proc (r: TableRow): bool = r.name == taskName
  let rowExists = idx > -1

  var newRow: TableRow
  if rowExists:
    newRow = table[idx]
  else:
    newRow = TableRow(name: taskName)

  let rate = billableRate entry
  let hours = entry.parseDuration.toBillableHours
  newRow.hours += hours
  newRow.cost += round(hours * rate, 2)

  if nextTasks.len > 0:
    newRow.subtasks.addOrUpdateRow(entry, nextTasks)

  if rowExists:
    table[idx] = newRow
  else:
    table.add newRow

proc prepareTable(rawEntries: RawTimewEntries): Table =
  for entry in rawEntries:
    let entryHierarcy = entry.tags.parseEntryHierarchy
    result.addOrUpdateRow(entry, entryHierarcy)

  let totals =
    TableRow(name: "Total", hours: result.totalHours, cost: result.totalCost)

  result.add totals

func depthMarker(depth: int, marker = "—"): string =
  var spacing = ""
  if depth > 0:
    spacing = " "

  fmt"{marker.repeat(depth)}{spacing}"

proc nestedTerminalRows(
  tt: var TerminalTable, t: Table, level = 0, sep = @["%SEP%"]
) =
  for i, row in t.pairs:
    if level == 0 and i != 0:
      tt.add sep
    tt.add @[
      fmt"{level.depthMarker}{row.name.yellow}",
      fmt"{row.hours:.2f}".blue,
      fmt"{row.cost:.2f}".green
    ]
    tt.nestedTerminalRows(row.subtasks, level + 1)

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
  table.nestedTerminalRows subtotals
  table.add @["%SEP%"]
  table.add @[
    fmt"{totals.name}".yellow.bold,
    fmt"{totals.hours:.2f}".blue.bold,
    fmt"{totals.cost:.2f}".green.bold
  ]

  table.echoBillableTable 80

func nestedCSVRows(t: Table, level = 0): seq[CSVRow] =
  for row in t.items:
    let csvRow = CSVRow(
      name: fmt"{level.depthMarker}{row.name}",
      hours: fmt"{row.hours:.2f}",
      cost: fmt"{row.cost:.2f}"
    )
    result.add csvRow
    result.add(nestedCSVRows(row.subtasks, level + 1))

proc renderCSV(tableRows: Table) =
  var report: seq[CSVRow] =
    @[CSVRow(name: "Task", hours: "Hours", cost: "Amount")]
  report = report.concat nestedCSVRows(tableRows)
  report.writeToCsv config.csvName
  echo fmt"CSV file created: {config.csvName.green}"

proc main() =
  let rawConfigAndEntries = readAll(stdin).split "\n\n"

  let configStrings = rawConfigAndEntries[0]
    .findAll(re"(^|\n)billable.*")
    .map(stripString)

  updateConfig configStrings
  let jsonData = rawConfigAndEntries[1].fromJson RawTimewEntries
  let table = prepareTable jsonData

  case config.render
    of rkCsv:
      table.renderCSV
    of rkTerminal:
      table.renderTerminalTable

when isMainModule:
  main()
