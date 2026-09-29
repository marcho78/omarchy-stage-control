import QtQuick
import Quickshell
import Quickshell.Io

// Runs one command from an argument list, by absolute path and never through
// a shell, then reports once: finished(ok, output).
//
// The command runs as the leader of its own process group (setsid), so a
// deadline or an output overrun ends it together with anything it started.
// Output is counted as it arrives, stdout and stderr together, and nothing
// past the budget is kept.
Item {
  id: run

  property int timeoutMs: 5000
  property int maxBytes: 64 * 1024
  readonly property bool running: proc.running

  signal finished(bool ok, string output)

  property string _out: ""
  property int _seen: 0
  property string _failed: ""

  function start(argv) {
    if (proc.running) return false
    _out = ""
    _seen = 0
    _failed = ""
    proc.command = ["/usr/bin/setsid", "--wait"].concat(argv)
    proc.running = true
    deadline.restart()
    return true
  }

  function _fail(reason) {
    if (_failed) return
    _failed = reason
    if (proc.processId > 0) Quickshell.execDetached(["/usr/bin/kill", "-KILL", "--", "-" + proc.processId])
  }

  function _take(data, isError) {
    if (_failed) return
    _seen += data.length
    if (_seen > maxBytes) {
      _fail("printed more than " + maxBytes + " bytes")
      return
    }
    if (!isError) _out += data
  }

  Timer {
    id: deadline
    interval: run.timeoutMs
    onTriggered: run._fail("took longer than " + run.timeoutMs + "ms")
  }

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { run._take(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { run._take(data, true) }
    }
    onExited: function(exitCode) {
      deadline.stop()
      var ok = exitCode === 0 && !run._failed
      var out = ok ? run._out : (run._failed || run._out)
      run._out = ""
      run.finished(ok, out)
    }
  }
}
