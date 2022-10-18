import std/strutils
import std/re
import std/sequtils

type
  ClientSpecificRate = tuple[client: string, rate: int]
  Config = object
    projectMarker: string
    billable: int
    clients: seq[ClientSpecificRate]
    descriptionMarker: string
    locale: string

const CONFIG_DEFAULTS = Config(
  projectMarker: "#",
  billable: 0,
  clients: @[],
  descriptionMarker:"",
  locale: ""
)

func stripStr(s: string): string = strip s

proc createConfigObject(keys: seq[string]): Config =
  var conf: Config
  for i in keys:
    let kvpair = map(split(i, ":"), proc (s:string):string = strip s)
    let conf_keys = kvpair[0].split('.')
    if conf_keys[0] != "billable": continue


let data = split(readAll(stdin), "\n\n")
let headerKeys = findAll(data[0], re"(^|\n)billable.*")
let strippedKeys = map(headerKeys, proc (s: string):string = strip s)

discard createConfigObject(strippedKeys)
