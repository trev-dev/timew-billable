import std/[strutils, re, sequtils, times, strformat, terminal, sugar]
import jsony, nancy, termstyle, csvtools, fixedpoint
import billable/config

type
  RawTimeEntry =
    tuple[id: int, start: string, `end`: string, tags: seq[string]]
  RawTimewEntries = seq[RawTimeEntry]

  Table = seq[TableRow]
  TableRow = object
    name: string
    hours: FixedPoint
    cost: FixedPoint
    subtasks: seq[TableRow]

  CSVRow = object
    name, hours, cost: string

func find[T](s: seq[T], pred: (T) -> bool): int =
  result = -1
  for idx, itm in s.pairs:
    if pred(itm):
      return idx

func findConfTag(t: seq[string], prefix = getConfig().projectMarker): string =
  let i = t.find (s: string) => s.startsWith prefix
  if i != -1: result = t[i]

proc findTaskName(t: seq[string], prefix = getConfig().taskMarker): string =
  result = t.findConfTag prefix
  if result == "":
    let i = find[string](t, (s: string) => s.find(' ') != -1)
    if i != -1: result = t[i]

proc parseEntryHierarchy(tags: seq[string]): seq[string] =
  let project = tags.findConfTag
  var taskName = tags.findTaskName

  if project != "":
    let projectHierarchy = project[getConfig().projectMarker.len..^1].split "."
    result = result.concat projectHierarchy

  if taskName != "":
    if taskName.startsWith getConfig().taskMarker:
      taskName = taskName[getConfig().taskMarker.len..^1]
    result.add taskName
  else:
    result.add (if project == "": tags[0] else: tags[1])

func toBillableHours(d: Duration): FixedPoint =
  (d.inSeconds.float / 3600.0).fixedPoint(2)

proc getBillableRate(e: RawTimeEntry): FixedPoint =
  for c in getConfig().clients:
    if e.tags.find(c.client) > -1:
      return c.rate
  return getConfig().billable

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
    newRow = TableRow(name: taskName, cost: fixedPoint(2), hours: fixedPoint(2))

  let
    rate = getBillableRate entry
    hours = entry.parseDuration.toBillableHours
  newRow.hours += hours
  newRow.cost += hours * rate

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
    cost = fixedPoint(2)
    hours = fixedPoint(2)
  for row in result:
    cost += row.cost
    hours += row.hours

  let totals =
    TableRow(name: "Total", hours: hours, cost: cost)

  result.add totals

func getDepthMarker(depth: int, marker = getConfig().depthMarker): string =
  var spacing = ""
  if depth > 0:
    spacing = " "

  &"{marker.repeat(depth)}{spacing}"

proc nestedTerminalRows(
  tt: var TerminalTable, t: Table, level = 0, sep = @["%SEP%"]
) =
  for i, row in t.pairs:
    if level == 0 and i != 0:
      tt.add sep
    tt.add @[
      &"{level.getDepthMarker}{row.name.yellow}",
      $(row.hours).blue,
      $(row.cost).green
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
    $(totals.name).yellow.bold,
    $(totals.hours).blue.bold,
    $(totals.cost).green.bold
  ]

  table.echoBillableTable 80

proc nestedCSVRows(t: Table, level = 0): seq[CSVRow] =
  for row in t.items:
    let csvRow = CSVRow(
      name: &"{level.getDepthMarker}{row.name}",
      hours: $(row.hours),
      cost: $(row.cost)
    )
    result.add csvRow
    result.add(nestedCSVRows(row.subtasks, level + 1))

proc renderCSV(tableRows: Table) =
  var report: seq[CSVRow] =
    @[CSVRow(name: "Task", hours: "Hours", cost: "Amount")]
  report = report.concat nestedCSVRows(tableRows)
  report.writeToCsv getConfig().csvName
  echo &"CSV file created: {getConfig().csvName.green}"

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

  case getConfig().render
    of rkCsv:
      table.renderCSV
    of rkTerminal:
      table.renderTerminalTable

when isMainModule:
  main()
