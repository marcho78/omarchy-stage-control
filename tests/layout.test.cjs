// Checks the stage layout: nothing overlaps, everything fits, sizes
// stay proportional, and on-screen order survives.
// Usage (from the plugin directory): node tests/layout.test.cjs

const assert = require("node:assert/strict");
const { load, plain } = require("./load.cjs");

const Layout = load("Layout.js");
const EPS = 0.01;

function overlaps(a, b, gap) {
  return a.x < b.x + b.w + gap - EPS && b.x < a.x + a.w + gap - EPS
    && a.y < b.y + b.h + gap - EPS && b.y < a.y + a.h + gap - EPS;
}

// A rect with the space kept free under it (for a title or a label).
function withSpace(rect, below) {
  return { x: rect.x, y: rect.y, w: rect.w, h: rect.h + below };
}

function check(label, windows, area, options) {
  const result = plain(Layout.spread(windows, area, options));
  const placed = result.windows;
  const gap = options.gap;
  const below = options.groupByApp ? 0 : options.titleSpace || 0;
  assert.equal(Object.keys(placed).length, windows.length, `${label}: every window placed`);
  const ids = Object.keys(placed);
  for (const id of ids) {
    const p = placed[id];
    assert.ok(p.x >= area.x - EPS && p.y >= area.y - EPS, `${label}: ${id} inside area (top-left)`);
    assert.ok(p.x + p.w <= area.x + area.w + EPS && p.y + p.h + below <= area.y + area.h + EPS, `${label}: ${id} and its title inside area (bottom-right)`);
    assert.ok(p.scale <= options.maxScale + EPS, `${label}: ${id} not above maxScale`);
    const source = windows.find((w) => String(w.id) === id);
    assert.ok(Math.abs(p.w / p.h - source.w / source.h) < 0.01, `${label}: ${id} keeps its aspect ratio`);
  }
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      // Grouped layouts space windows inside a group by their own scaled gap.
      const g = options.groupByApp ? 0 : gap;
      const a = withSpace(placed[ids[i]], below), b = withSpace(placed[ids[j]], below);
      assert.ok(!overlaps(a, b, g), `${label}: ${ids[i]} and ${ids[j]} (with titles) don't overlap`);
    }
  }
  if (!options.groupByApp) {
    const scales = ids.map((id) => placed[id].scale);
    assert.ok(Math.max(...scales) - Math.min(...scales) < EPS, `${label}: one scale for all windows`);
  }
  return result;
}

const screen = { x: 40, y: 150, w: 1200, h: 600 };
const opts = { gap: 24, maxScale: 0.8 };
let passed = 0;

// Empty and degenerate input.
assert.deepEqual(plain(Layout.spread([], screen, opts)), { windows: {}, groups: [] });
assert.deepEqual(plain(Layout.spread([{ id: "a", x: 0, y: 0, w: 10, h: 10 }], { x: 0, y: 0, w: 0, h: 10 }, opts)).windows, {});
passed++;

// One maximized window: scaled to fit, centered.
{
  const r = check("single", [{ id: "a", x: 12, y: 64, w: 1256, h: 724 }], screen, opts);
  const p = r.windows.a;
  assert.ok(Math.abs(p.x + p.w / 2 - (screen.x + screen.w / 2)) < 0.5, "single: centered horizontally");
  assert.ok(Math.abs(p.y + p.h / 2 - (screen.y + screen.h / 2)) < 0.5, "single: centered vertically");
  passed++;
}

// One small window never grows past maxScale.
{
  const r = check("small", [{ id: "a", x: 500, y: 300, w: 300, h: 200 }], screen, opts);
  assert.ok(Math.abs(r.windows.a.w - 240) < 0.01, "small: width is 0.8 of 300");
  passed++;
}

// Side by side stays side by side and in order.
{
  const r = check("pair", [
    { id: "right", x: 646, y: 64, w: 622, h: 724 },
    { id: "left", x: 12, y: 64, w: 622, h: 724 },
  ], screen, opts);
  assert.ok(r.windows.left.x < r.windows.right.x, "pair: left stays left");
  assert.ok(Math.abs(r.windows.left.y - r.windows.right.y) < 0.5, "pair: one row");
  passed++;
}

// Dwindle: one tall window on the left, two stacked on the right.
{
  const r = check("dwindle", [
    { id: "main", x: 12, y: 64, w: 622, h: 724 },
    { id: "top", x: 646, y: 64, w: 622, h: 356 },
    { id: "bottom", x: 646, y: 432, w: 622, h: 356 },
  ], screen, opts);
  assert.ok(r.windows.top.y <= r.windows.bottom.y, "dwindle: top above bottom");
  passed++;
}

// Titles on every window: each row keeps room under it, so a title never sits
// on the window below (as LocalSend's once did on Omarchy Spaces).
{
  const quarters = [
    { id: "tl", x: 12, y: 64, w: 622, h: 356 },
    { id: "tr", x: 646, y: 64, w: 622, h: 356 },
    { id: "bl", x: 12, y: 432, w: 622, h: 356 },
    { id: "br", x: 646, y: 432, w: 622, h: 356 },
  ];
  const r = check("titles", quarters, screen, { gap: 24, maxScale: 0.8, titleSpace: 54 });
  const top = r.windows.tl, bottom = r.windows.bl;
  assert.ok(bottom.y > top.y + top.h, "titles: two rows");
  assert.ok(bottom.y - (top.y + top.h) >= 54 + 24 - EPS, "titles: the title's room plus the gap between rows");
  const plainRows = plain(Layout.spread(quarters, screen, { gap: 24, maxScale: 0.8 })).windows;
  assert.ok(plainRows.tl.w > top.w, "titles: without titles the windows can be larger");
  passed++;
}

// Stacked windows (same position, e.g. floating on top of each other) get pulled apart.
{
  const same = Array.from({ length: 5 }, (_, i) => ({ id: "w" + i, x: 100, y: 100, w: 800, h: 500 }));
  check("stacked", same, screen, opts);
  passed++;
}

// Random stress: invariants hold for many shapes.
{
  let seed = 7;
  const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  for (let round = 0; round < 400; round++) {
    const n = 1 + Math.floor(random() * 24);
    const windows = Array.from({ length: n }, (_, i) => ({
      id: "w" + i,
      x: Math.floor(random() * 1200),
      y: Math.floor(random() * 700),
      w: 80 + Math.floor(random() * 1200),
      h: 60 + Math.floor(random() * 800),
      group: "app" + Math.floor(random() * 4),
    }));
    const area = { x: 20, y: 120, w: 600 + Math.floor(random() * 1800), h: 300 + Math.floor(random() * 900) };
    check(`random ${round}`, windows, area, { gap: 20, maxScale: 0.8 });
    check(`titled ${round}`, windows, area, { gap: 20, maxScale: 0.8, titleSpace: 54 });
    const grouped = check(`grouped ${round}`, windows, area, { gap: 20, maxScale: 0.8, groupByApp: true, labelSpace: 40 });
    // Each group's windows sit inside the group's rect, and groups don't overlap.
    for (const group of grouped.groups) {
      for (const w of windows.filter((w) => w.group === group.key)) {
        const p = grouped.windows[w.id];
        assert.ok(p.x >= group.x - EPS && p.x + p.w <= group.x + group.w + EPS, `grouped ${round}: ${w.id} inside its group (x)`);
        assert.ok(p.y >= group.y - EPS && p.y + p.h <= group.y + group.h + EPS, `grouped ${round}: ${w.id} inside its group (y)`);
      }
    }
    // Groups and the labels under them don't overlap, and the labels fit.
    for (let i = 0; i < grouped.groups.length; i++) {
      const group = grouped.groups[i];
      assert.ok(group.y + group.h + 40 <= area.y + area.h + EPS, `grouped ${round}: ${group.key}'s label inside area`);
      for (let j = i + 1; j < grouped.groups.length; j++) {
        assert.ok(!overlaps(withSpace(group, 40), withSpace(grouped.groups[j], 40), 0), `grouped ${round}: groups and labels don't overlap`);
      }
    }
  }
  passed++;
}

// A desktop dragged along the Spaces bar lands on the slot nearest its center:
// no dead gaps between desktops, and the ends catch anything past them.
{
  const slots = [{ id: 1, center: 100 }, { id: 2, center: 300 }, { id: 3, center: 500 }];
  assert.equal(Layout.nearestSlot(slots, 290), 2);
  assert.equal(Layout.nearestSlot(slots, 201), 2, "just past the midpoint");
  assert.equal(Layout.nearestSlot(slots, 199), 1, "just short of it");
  assert.equal(Layout.nearestSlot(slots, -500), 1, "past the left end");
  assert.equal(Layout.nearestSlot(slots, 9000), 3, "past the right end");
  assert.equal(Layout.nearestSlot([], 10), null);
  passed++;
}

// Keyboard navigation picks the nearest window in each direction.
{
  const placed = {
    a: { x: 0, y: 0, w: 100, h: 100 },
    b: { x: 200, y: 0, w: 100, h: 100 },
    c: { x: 0, y: 200, w: 100, h: 100 },
    d: { x: 200, y: 200, w: 100, h: 100 },
  };
  assert.equal(Layout.neighbor(placed, "a", "right"), "b");
  assert.equal(Layout.neighbor(placed, "a", "down"), "c");
  assert.equal(Layout.neighbor(placed, "d", "left"), "c");
  assert.equal(Layout.neighbor(placed, "d", "up"), "b");
  assert.equal(Layout.neighbor(placed, "a", "left"), null);
  passed++;
}

console.log(`layout: ${passed} checks passed`);
