// Defaults.js - Stage Control's settings: their defaults, and what each may be.
//
// Code rather than JSON files, so Stage Control reads no files at run time. Settings
// are stored on Stage Control's entry in shell.json (by the Omarchy shell), holding
// only what differs from DEFAULTS; Settings.merge() validates them against
// SCHEMA before anything uses them.

var DEFAULTS = {
  barIcon: true,
  gestureFingers: 4,
  appExposeGesture: true,
  desktopSwipeFingers: 0,
  shortcuts: true,
  stageKey: "SUPER + A",
  appWindowsKey: "SUPER + ALT + A",
  macShortcuts: false,
  cornerTopLeft: "none",
  cornerTopRight: "none",
  cornerBottomLeft: "none",
  cornerBottomRight: "none",
  groupByApp: false,
  windowTitles: "hover",
  appIcons: true,
  spacesBar: "auto",
  renumberDesktops: true,
  closeButtons: true,
  middleClickClose: true,
  showMinimized: true,
  background: "blur",
  dim: 25,
  glass: "liquid",
  highlight: "accent",
  reduceMotion: false,
  speed: 100
}

var SCHEMA = {
  types: {
    barIcon: "bool",
    gestureFingers: "int",
    appExposeGesture: "bool",
    desktopSwipeFingers: "int",
    shortcuts: "bool",
    stageKey: "shortcut",
    appWindowsKey: "shortcut",
    macShortcuts: "bool",
    cornerTopLeft: "string",
    cornerTopRight: "string",
    cornerBottomLeft: "string",
    cornerBottomRight: "string",
    groupByApp: "bool",
    windowTitles: "string",
    appIcons: "bool",
    spacesBar: "string",
    renumberDesktops: "bool",
    closeButtons: "bool",
    middleClickClose: "bool",
    showMinimized: "bool",
    background: "string",
    dim: "int",
    glass: "string",
    highlight: "string",
    reduceMotion: "bool",
    speed: "int"
  },
  choices: {
    gestureFingers: [0, 3, 4, 5],
    desktopSwipeFingers: [0, 3, 4, 5],
    cornerTopLeft: ["none", "stage", "appWindows", "launchpad", "menu", "lock", "screensaver"],
    cornerTopRight: ["none", "stage", "appWindows", "launchpad", "menu", "lock", "screensaver"],
    cornerBottomLeft: ["none", "stage", "appWindows", "launchpad", "menu", "lock", "screensaver"],
    cornerBottomRight: ["none", "stage", "appWindows", "launchpad", "menu", "lock", "screensaver"],
    windowTitles: ["hover", "always", "never"],
    spacesBar: ["auto", "expanded"],
    background: ["blur", "dim"],
    glass: ["liquid", "frosted", "solid"],
    highlight: ["accent", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"]
  },
  ranges: {
    dim: [0, 80],
    speed: [50, 200]
  }
}
