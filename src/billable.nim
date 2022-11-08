import std/[strutils, re, sequtils, times, math, strformat, terminal, sugar]
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
    depthMarker: string
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
  depthMarker: "—",
)

var config = defaultConfig


func coerceFloat(s: string): float =
  try:
    return parseFloat(s)
  except ValueError:
    assert false, &"Failed to parse config! Value {s} should be a float type."

func find[T](s: seq[T], pred: (T) -> bool): int =
  result = -1
  for idx, itm in s.pairs:
    if pred(itm):
      return idx

func findConfTag(t: seq[string], prefix = config.projectMarker): string =
  let i = t.find (s: string) => s.startsWith prefix
  if i != -1: result = t[i]

proc findTaskName(t: seq[string], prefix = config.taskMarker): string =
  result = t.findConfTag prefix
  if result == "":
    let i = find[string](t, (s: string) => s.find(' ') != -1)
    if i != -1: result = t[i]

proc updateConfig(keys: seq[string]) =

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

proc parseEntryHierarchy(tags: seq[string]): seq[string] =
  let project = tags.findConfTag
  var taskName = tags.findTaskName

  if project != "":
    let projectHierarchy = project[config.projectMarker.len..^1].split "."
    result = result.concat projectHierarchy

  if taskName != "":
    if taskName.startsWith config.taskMarker:
      taskName = taskName[config.taskMarker.len..^1]
    result.add taskName
  else:
    # slight change in functionality: tags[project+1] -> tags[1]
    # because indices have been exchanged for strings
    result.add (if project == "": tags[0] else: tags[1])

func toBillableHours(d: Duration): float =
  (d.inSeconds.float / 3600 * 100).round / 100

proc getBillableRate(e: RawTimeEntry): float =
  for c in config.clients:
    if e.tags.find(c.client) > -1:
      return c.rate
  return config.billable

proc parseDuration(e: RawTimeEntry): Duration =
  let
    f = initTimeFormat "yyyyMMdd'T'HHmmss'Z'"
    stime = e.start.parse f
  var etime = stime

  if e.`end` != "":
    etime = e.`end`.parse f

  etime - stime

proc addOrUpdateRow(
  table: var Table,
  entry: RawTimeEntry,
  hierarchy: seq[string],
) =
  let
    taskName = hierarchy[0]
    nextTasks = hierarchy[1..^1]
    idx = table.find proc (r: TableRow): bool = r.name == taskName
    rowExists = idx > -1

  var newRow: TableRow
  if rowExists:
    newRow = table[idx]
  else:
    newRow = TableRow(name: taskName)

  let
    rate = getBillableRate entry
    hours = entry.parseDuration.toBillableHours
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

  var
    cost: float
    hours: float
  for row in result:
    cost += row.cost
    hours += row.hours

  let totals =
    TableRow(name: "Total", hours: hours, cost: cost)

  result.add totals

func getDepthMarker(depth: int, marker = config.depthMarker): string =
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
      fmt"{level.getDepthMarker}{row.name.yellow}",
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
  let
    subtotals = tableRows[0..^2]
    totals = tableRows[^1]

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

proc nestedCSVRows(t: Table, level = 0): seq[CSVRow] =
  for row in t.items:
    let csvRow = CSVRow(
      name: fmt"{level.getDepthMarker}{row.name}",
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
  let
    rawConfigAndEntries = readAll(stdin).split "\n\n"
    configStrings = rawConfigAndEntries[0]
    .findAll(re"(^|\n)billable.*")
    .mapIt(it.strip)

  updateConfig configStrings
  let
    jsonData = rawConfigAndEntries[1].fromJson RawTimewEntries
    table = prepareTable jsonData

  case config.render
    of rkCsv:
      table.renderCSV
    of rkTerminal:
      table.renderTerminalTable

when isMainModule:
  main()
