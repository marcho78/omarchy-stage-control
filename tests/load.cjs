// Loads one of the plugin's plain-JS files (Layout.js, Settings.js) the way
// QML does: as a script whose top-level functions become the module.
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");

function load(file) {
  const context = {};
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(root, file), "utf8"), context, { filename: file });
  return context;
}

// Copies a value out of a vm context so deepEqual sees ordinary objects.
function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

module.exports = { load, plain, root };
