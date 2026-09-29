// Layout.js - where each window goes on the stage.
//
// Windows are placed in rows so none overlap, all scaled by the same factor
// (so they keep their relative sizes, like macOS) and as large as the area
// allows, never above maxScale. Their on-screen order is kept: rows go top to
// bottom by each window's center, and windows go left to right within a row.
// With grouping, each app's windows are laid out together first and the app
// groups are then arranged the same way.
//
// Pure functions shared by Overview.qml and tests/layout.test.cjs.

function centerX(item) { return item.x + item.w / 2 }
function centerY(item) { return item.y + item.h / 2 }

function sortByScreenOrder(items) {
  return items.slice().sort(function(a, b) {
    var dy = centerY(a) - centerY(b)
    if (Math.abs(dy) > 1) return dy
    var dx = centerX(a) - centerX(b)
    if (Math.abs(dx) > 1) return dx
    return String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0
  })
}

// Splits items (already in screen order) into `rows` consecutive rows so the
// widest row is as narrow as possible.
function partition(items, rows) {
  var n = items.length
  var prefix = [0]
  for (var i = 0; i < n; i++) prefix.push(prefix[i] + items[i].w)
  function width(from, to) { return prefix[to] - prefix[from] }

  // best[k][j]: narrowest widest-row splitting the first j items into k rows.
  var best = [], cut = []
  for (var k = 0; k <= rows; k++) {
    best.push(new Array(n + 1).fill(Infinity))
    cut.push(new Array(n + 1).fill(0))
  }
  best[0][0] = 0
  for (k = 1; k <= rows; k++) {
    for (var j = k; j <= n; j++) {
      for (var start = k - 1; start < j; start++) {
        var value = Math.max(best[k - 1][start], width(start, j))
        if (value < best[k][j]) {
          best[k][j] = value
          cut[k][j] = start
        }
      }
    }
  }
  var out = []
  var end = n
  for (k = rows; k >= 1; k--) {
    var begin = cut[k][end]
    out.unshift(items.slice(begin, end))
    end = begin
  }
  return out
}

function rowMetrics(rows, gap) {
  return rows.map(function(row) {
    var width = 0, height = 0
    row.forEach(function(item) {
      width += item.w
      height = Math.max(height, item.h)
    })
    return { width: width, height: height, count: row.length }
  })
}

// The largest scale at which these rows fit the area, `below` screen pixels
// kept free under each row.
function fitScale(metrics, area, gap, below) {
  var scale = Infinity
  var heights = 0
  metrics.forEach(function(row) {
    heights += row.height
    var room = area.w - gap * (row.count - 1)
    scale = Math.min(scale, room / Math.max(1, row.width))
  })
  var roomY = area.h - gap * (metrics.length - 1) - below * metrics.length
  return Math.max(0, Math.min(scale, roomY / Math.max(1, heights)))
}

// Places `items` ({ id, x, y, w, h }) in `area`. options.below is space under
// every row, in screen pixels, that the layout keeps free for what hangs below
// the items there (window titles, group labels).
function rows(items, area, options) {
  var gap = options.gap
  var maxScale = options.maxScale
  var below = options.below || 0
  var ordered = sortByScreenOrder(items)
  var n = ordered.length
  var sized = ordered.map(function(item) {
    return { id: item.id, x: item.x, y: item.y, w: Math.max(1, item.w), h: Math.max(1, item.h) }
  })

  var bestRows = null, bestScale = -1
  var limit = Math.min(n, Math.max(1, Math.ceil(Math.sqrt(n)) + 2))
  for (var count = 1; count <= limit; count++) {
    var candidate = partition(sized, count)
    var scale = Math.min(maxScale, fitScale(rowMetrics(candidate, gap), area, gap, below))
    // Fewer rows win ties: they keep more of the original arrangement.
    if (scale > bestScale * 1.01) {
      bestScale = scale
      bestRows = candidate
    }
  }

  var metrics = rowMetrics(bestRows, gap)
  var totalHeight = gap * (bestRows.length - 1)
  metrics.forEach(function(row) { totalHeight += row.height * bestScale + below })
  var y = area.y + (area.h - totalHeight) / 2
  var placed = {}
  bestRows.forEach(function(row, index) {
    var inRow = row.slice().sort(function(a, b) { return centerX(a) - centerX(b) })
    var rowHeight = metrics[index].height * bestScale
    var rowWidth = metrics[index].width * bestScale + gap * (row.length - 1)
    var x = area.x + (area.w - rowWidth) / 2
    inRow.forEach(function(item) {
      var w = item.w * bestScale
      var h = item.h * bestScale
      placed[item.id] = {
        x: x,
        y: y + (rowHeight - h) / 2,
        w: w,
        h: h,
        scale: bestScale
      }
      x += w + gap
    })
    y += rowHeight + below + gap
  })
  return { placed: placed, scale: bestScale }
}

// windows: [{ id, x, y, w, h, group }], area: { x, y, w, h }.
// options: { gap, maxScale, groupByApp, labelSpace, titleSpace }. labelSpace is
// kept under every app group, titleSpace under every window when not grouped;
// both in screen pixels.
// Returns { windows: { id: { x, y, w, h, scale } }, groups: [{ key, x, y, w, h }] }.
function spread(windows, area, options) {
  options = options || {}
  var gap = options.gap === undefined ? 24 : options.gap
  var maxScale = options.maxScale === undefined ? 0.8 : options.maxScale
  var result = { windows: {}, groups: [] }
  if (!windows || windows.length === 0 || area.w <= 0 || area.h <= 0) return result

  if (!options.groupByApp) {
    result.windows = rows(windows, area, { gap: gap, maxScale: maxScale, below: options.titleSpace || 0 }).placed
    return result
  }

  // Lay out each app's windows at full size, then treat each app as one item.
  var byGroup = {}
  var order = []
  windows.forEach(function(window) {
    var key = String(window.group || "")
    if (!byGroup[key]) {
      byGroup[key] = []
      order.push(key)
    }
    byGroup[key].push(window)
  })
  var labelSpace = options.labelSpace === undefined ? 56 : options.labelSpace
  var boxes = order.map(function(key) {
    var members = byGroup[key]
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    members.forEach(function(window) {
      left = Math.min(left, window.x)
      top = Math.min(top, window.y)
      right = Math.max(right, window.x + window.w)
      bottom = Math.max(bottom, window.y + window.h)
    })
    // Inside a group, keep the windows' own rows at full size in a box shaped
    // like the area, so a group of three reads as a compact cluster.
    var totalArea = 0
    members.forEach(function(window) { totalArea += window.w * window.h })
    var side = Math.sqrt(totalArea * 1.6)
    var inner = { x: 0, y: 0, w: side * area.w / Math.max(1, area.h), h: side }
    var local = members.length === 1
      ? { placed: {}, scale: 1 }
      : rows(members, inner, { gap: gap * 2, maxScale: 1 })
    if (members.length === 1) local.placed[members[0].id] = { x: 0, y: 0, w: members[0].w, h: members[0].h, scale: 1 }
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    Object.keys(local.placed).forEach(function(id) {
      var p = local.placed[id]
      minX = Math.min(minX, p.x)
      minY = Math.min(minY, p.y)
      maxX = Math.max(maxX, p.x + p.w)
      maxY = Math.max(maxY, p.y + p.h)
    })
    return {
      id: "group:" + key,
      key: key,
      x: left, y: top,
      w: maxX - minX, h: maxY - minY,
      originX: minX, originY: minY,
      local: local.placed
    }
  })

  var outer = rows(boxes, area, { gap: gap, maxScale: maxScale, below: labelSpace })

  boxes.forEach(function(box) {
    var slot = outer.placed[box.id]
    if (!slot) return
    var s = slot.scale
    result.groups.push({ key: box.key, x: slot.x, y: slot.y, w: slot.w, h: slot.h })
    Object.keys(box.local).forEach(function(id) {
      var p = box.local[id]
      result.windows[id] = {
        x: slot.x + (p.x - box.originX) * s,
        y: slot.y + (p.y - box.originY) * s,
        w: p.w * s,
        h: p.h * s,
        scale: s * (p.scale || 1)
      }
    })
  })
  return result
}

// The slot ({ id, center }) whose center lies nearest `x`: where a desktop
// dragged along the Spaces bar lands. There are no dead gaps between desktops,
// and past either end it is that end's slot. null for no slots.
function nearestSlot(slots, x) {
  var best = null, bestDistance = Infinity
  for (var i = 0; i < (slots || []).length; i++) {
    var distance = Math.abs(slots[i].center - x)
    if (distance < bestDistance) {
      bestDistance = distance
      best = slots[i].id
    }
  }
  return best
}

// The window whose placed rect lies nearest in a direction ("left", "right",
// "up", "down") from `fromId`. Used for keyboard navigation.
function neighbor(placed, fromId, direction) {
  var from = placed[fromId]
  if (!from) return null
  var fx = from.x + from.w / 2
  var fy = from.y + from.h / 2
  var best = null, bestScore = Infinity
  Object.keys(placed).forEach(function(id) {
    if (id === fromId) return
    var p = placed[id]
    var dx = p.x + p.w / 2 - fx
    var dy = p.y + p.h / 2 - fy
    var along, across
    if (direction === "left") { along = -dx; across = Math.abs(dy) }
    else if (direction === "right") { along = dx; across = Math.abs(dy) }
    else if (direction === "up") { along = -dy; across = Math.abs(dx) }
    else { along = dy; across = Math.abs(dx) }
    if (along <= 1) return
    var score = along + across * 2
    if (score < bestScore) {
      bestScore = score
      best = id
    }
  })
  return best
}
