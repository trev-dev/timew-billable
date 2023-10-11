# Package

version       = "0.2.3"
author        = "Trevor Richards <trev@trevdev.ca>"
description   = "timew-billable"
license       = "GPL3"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6.6 & < 2.0",
  "csvtools >= 0.2.1 & < 1.0",
  "jsony >= 1.1.3 & < 2.0",
  "nancy >= 0.1.1 & < 1.0",
  "termstyle >= 0.1.0 & < 1.0"

binDir = "build"
bin = @["billable"]
