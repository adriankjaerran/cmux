// Dia-style workspace sidebar: groups, cross-group drag, full context menus.
//
// The whole sidebar is ONE flat drag surface: group headers and workspace
// rows live in a single Reorderable. Headers are `fixed` (not grabbable, but
// they shift to open gaps like any row), so a workspace can be dragged
// between groups, into a group, or out to the ungrouped area in one gesture.
// The drop resolves to (container group, reorder anchor) from the flat index
// and dispatches workspace.group.add/remove + workspace.reorder.
//
// Group collapse is optimistic (a local signal flips instantly) and syncs via
// workspace.group.collapse/expand so the built-in sidebar agrees.
//
// Folders (fork): a group header is only a folder. It has no session of its
// own: clicking it collapses/expands, and the group's anchor workspace shows
// as an ordinary first member row. The app keeps the anchor first in the
// block, so a drop that changes a group's first row hands the anchor role
// to that row (workspace.group.set_anchor) before reordering.
//
// Compact variant: one line per workspace, title left, agent state right.
// Open:     cmux sidebar open compact
// Select:   cmux sidebar select compact

// --- optimistic UI -------------------------------------------------------------
// Every user action flips local state the same frame; the cmux command runs
// behind it and the authoritative data context (which refreshes about once a
// second) reconciles: each override clears itself as soon as the data agrees.
let selectOverride = null;
const [selectTick, setSelectTick] = signal(0);

function isSelected(w) {
  selectTick();
  if (!w) return false;
  if (selectOverride) {
    if (data.selectedId() === selectOverride) selectOverride = null; // caught up
    else return w.id === selectOverride;
  }
  return !!w.selected;
}

function selectWorkspace(id) {
  if (!id) return;
  selectOverride = id;
  setSelectTick(selectTick() + 1);
  cmux("workspace.select", { workspace_id: id });
}

const closedOverride = new Set();
const [closeTick, setCloseTick] = signal(0);

// Optimistic tabs order: a bulk drop rearranges rows locally the same frame
// (reorder_many echoes ~1s later); clears itself once the data agrees.
let orderOverride = null;
const [orderTick, setOrderTick] = signal(0);

function setOrderOverride(ids) {
  orderOverride = ids;
  setOrderTick(orderTick() + 1);
}

function visibleWorkspaces() {
  closeTick();
  orderTick();
  let ws = data.workspaces() ?? [];
  for (const id of Array.from(closedOverride)) {
    if (!ws.some((w) => w.id === id)) closedOverride.delete(id); // caught up
  }
  ws = ws.filter((w) => !closedOverride.has(w.id));
  if (orderOverride) {
    const actual = ws.map((w) => w.id).join(",");
    const wanted = orderOverride.filter((id) => ws.some((w) => w.id === id)).join(",");
    if (actual === wanted) {
      orderOverride = null; // caught up
    } else {
      const rank = new Map(orderOverride.map((id, i) => [id, i]));
      ws = [...ws].sort((a, b) => (rank.get(a.id) ?? 1e9) - (rank.get(b.id) ?? 1e9));
    }
  }
  return ws;
}

function closeWorkspace(id) {
  closedOverride.add(id);
  setCloseTick(closeTick() + 1);
  cmux("workspace.close", { workspace_id: id });
}

// Multi-select: Cmd-click toggles, Shift-click extends from the last click
// over the visible row order, plain click clears. The selection drives the
// context menu's bulk actions (group together, move, close).
const multiSelected = new Set();
const [multiTick, setMultiTick] = signal(0);
let lastClickedId = null;

function isMultiSelected(w) {
  multiTick();
  return !!w && multiSelected.has(w.id);
}

function clearMultiSelect() {
  if (multiSelected.size === 0) return;
  multiSelected.clear();
  setMultiTick(multiTick() + 1);
}

function visibleRowIds() {
  return flatEntries().filter((e) => e.kind === "ws").map((e) => e.wsId);
}

function handleRowClick(w, payload) {
  const id = w.id;
  if (payload && payload.cmd) {
    if (multiSelected.has(id)) multiSelected.delete(id);
    else multiSelected.add(id);
    setMultiTick(multiTick() + 1);
  } else if (payload && payload.shift && lastClickedId) {
    const order = visibleRowIds();
    const a = order.indexOf(lastClickedId);
    const b = order.indexOf(id);
    if (a >= 0 && b >= 0) {
      for (const rid of order.slice(Math.min(a, b), Math.max(a, b) + 1)) multiSelected.add(rid);
      setMultiTick(multiTick() + 1);
    }
  } else {
    clearMultiSelect();
    selectWorkspace(id);
  }
  lastClickedId = id;
}

// The set of workspaces a bulk menu action applies to: the multi-selection
// when the clicked row is part of it, else just the clicked row.
function bulkIds(w) {
  multiTick();
  if (w && multiSelected.has(w.id)) return Array.from(multiSelected);
  return w ? [w.id] : [];
}

const titleOverride = new Map();
const [titleTick, setTitleTick] = signal(0);

function displayTitle(w) {
  titleTick();
  if (!w) return "";
  if (titleOverride.has(w.id)) {
    const t = titleOverride.get(w.id);
    if (w.title === t) titleOverride.delete(w.id); // caught up
    else return t;
  }
  return w.title;
}

// --- inline rename -----------------------------------------------------------
// Double-click a row/header (or its Rename menu item) to edit in place.
// Editing swaps the entry's key, so the keyed reconciler remounts the row as
// an editor; Return commits through workspace(.group).rename, Escape cancels.
const [editingId, setEditingId] = signal(null);

// --- optimistic collapse -----------------------------------------------------
const collapseOverride = new Map();
const [collapseTick, setCollapseTick] = signal(0);

function isCollapsed(g) {
  collapseTick();
  if (collapseOverride.has(g.id)) {
    const v = collapseOverride.get(g.id);
    if (v === g.collapsed) collapseOverride.delete(g.id); // host caught up
    else return v;
  }
  return g.collapsed;
}

function toggleCollapse(g) {
  const next = !isCollapsed(g);
  collapseOverride.set(g.id, next);
  setCollapseTick(collapseTick() + 1);
  cmux(next ? "workspace.group.collapse" : "workspace.group.expand", { group_id: g.id });
}

// --- data helpers ------------------------------------------------------------
const groupById = (id) => (data.groups() ?? []).find((g) => g.id === id);
const membersOf = (id) => visibleWorkspaces().filter((w) => w.group === id);
// Every member is a row, the anchor included: the header is just a folder.
const memberRowsOf = (id) => membersOf(id);

// After a drop the app re-hoists each group's anchor to the front of its
// block. Make the row that will be first in `order` the anchor, so the drop
// sticks instead of snapping back. `groupOf(id)` is the post-drop group.
function syncAnchors(order, groupOf, groupIds) {
  for (const gid of groupIds) {
    const g = groupById(gid);
    const first = order.find((x) => groupOf(x) === gid);
    if (g && first && first !== g.anchorId) {
      cmux("workspace.group.set_anchor", { group_id: gid, workspace_id: first });
    }
  }
}

// One flat entry list. A group renders (header + expanded member rows) at
// its ANCHOR's tabs position - the app's canonical block position - so a
// stray member sitting early in the tabs order can never yank the whole
// group upward. Pinned groups and pinned ungrouped workspaces float to a
// cluster at the top.
const flatEntries = computed(() => {
  const ws = visibleWorkspaces();
  const groups = new Map((data.groups() ?? []).map((g) => [g.id, g]));
  const editing = editingId();
  const wsEntry = (w, groupId) => ({
    kind: "ws",
    id: w.id + (editing === w.id ? ":edit" : ""),
    wsId: w.id,
    editing: editing === w.id,
    groupId,
  });
  const groupSection = (g) => {
    const out = [{
      kind: "header",
      id: "h:" + g.id + (editing === "h:" + g.id ? ":edit" : ""),
      groupId: g.id,
      editing: editing === "h:" + g.id,
    }];
    if (!isCollapsed(g)) {
      for (const m of memberRowsOf(g.id)) out.push(wsEntry(m, g.id));
    }
    return out;
  };

  const pinned = [];
  const rest = [];
  const seen = new Set();
  for (const w of ws) {
    if (w.group && groups.has(w.group)) {
      const g = groups.get(w.group);
      // Emit the group at its anchor's position; a group whose anchor is
      // hidden (optimistically closed) falls back to its first member.
      const isAnchor = w.id === g.anchorId || !ws.some((x) => x.id === g.anchorId);
      if (seen.has(g.id) || !isAnchor) continue;
      seen.add(g.id);
      (g.pinned ? pinned : rest).push(...groupSection(g));
    } else if (!w.group) {
      (w.pinned ? pinned : rest).push(wsEntry(w, null));
    }
  }
  // Groups whose anchor never appeared (edge churn): append at the end.
  for (const g of groups.values()) {
    if (!seen.has(g.id) && ws.some((x) => x.group === g.id)) {
      seen.add(g.id);
      (g.pinned ? pinned : rest).push(...groupSection(g));
    }
  }
  return [...pinned, ...rest];
});

// --- keyboard mode -------------------------------------------------------------
// Focus Sidebar (cmd+O) hands the keyboard to this list; the terminal gets
// no keys until the mode ends. A cursor (thin blue ring) walks the visible
// rows - folder headers included, members of collapsed folders skipped -
// starting on the selected workspace:
//   up/down       move the cursor
//   left          collapse the folder (from a member: jump to its header)
//   right         expand a collapsed folder (on an open one: step in)
//   return/space  open the workspace (focus its terminal, mode ends) or
//                 toggle the folder
//   c             collapse all folders, or expand all when none is open
//   escape        back to the terminal (as does cmd+O again)
// Any other key ends the mode and goes on to the terminal as usual.
// Navigation itself is the runtime's pure sidebarKeyNav (unit-tested).
const [cursorId, setCursorId] = signal(null);

function navRows() {
  return flatEntries().map((e) => (e.kind === "header"
    ? {
        id: "h:" + e.groupId,
        header: true,
        group: e.groupId,
        collapsed: isCollapsed(groupById(e.groupId) ?? { id: e.groupId, collapsed: false }),
      }
    : { id: e.wsId, group: e.groupId }));
}

// The cursor row as shown: the remembered row when it is visible, else the
// header that hides it, else the selected workspace (or its header), else
// the first row.
function resolveCursor(rows) {
  const has = (id) => !!id && rows.some((r) => r.id === id);
  const headerHiding = (id) => {
    const w = id ? (data.workspaces() ?? []).find((x) => x.id === id) : null;
    return w && w.group && has("h:" + w.group) ? "h:" + w.group : null;
  };
  const c = cursorId();
  if (has(c)) return c;
  const sel = visibleWorkspaces().find((w) => isSelected(w));
  return headerHiding(c)
    ?? (sel && has(sel.id) ? sel.id : headerHiding(sel && sel.id))
    ?? (rows[0] ? rows[0].id : null);
}

const cursorRow = computed(() => (keyboardMode() ? resolveCursor(navRows()) : null));
const CURSOR_RING = "#4C8DFFd9";
const cursorRing = (id) => (cursorRow() !== null && cursorRow() === id ? CURSOR_RING : null);

// Collapse every open folder; when none is open, expand them all.
function toggleCollapseAll() {
  const groups = data.groups() ?? [];
  const anyOpen = groups.some((g) => !isCollapsed(g));
  for (const g of groups) {
    if (anyOpen ? !isCollapsed(g) : isCollapsed(g)) toggleCollapse(g);
  }
}

onKeyboardMode((on) => {
  if (on) setCursorId(data.selectedId() ?? null);
});

onKey((e) => {
  if (e.command || e.control || e.option) return false;
  const rows = navRows();
  const current = resolveCursor(rows);
  if (e.key === "c") {
    setCursorId(current);
    toggleCollapseAll();
    return true;
  }
  const r = sidebarKeyNav(rows, current, e.key);
  if (!r.handled) return false;
  setCursorId(r.cursor);
  const group = (gid) => (gid ? groupById(gid) : null);
  if (group(r.collapse) && !isCollapsed(group(r.collapse))) toggleCollapse(group(r.collapse));
  if (group(r.expand) && isCollapsed(group(r.expand))) toggleCollapse(group(r.expand));
  if (group(r.toggle)) toggleCollapse(group(r.toggle));
  if (r.open) {
    // The host selects it and focuses its terminal; paint the selection now.
    selectOverride = r.open;
    setSelectTick(selectTick() + 1);
    clearMultiSelect();
    return { open: r.open };
  }
  if (r.exit) return { exit: true };
  return true;
});

// --- drop resolution ---------------------------------------------------------
// `index` is the dragged row's slot in the flat list (headers included).
// `extra.side` resolves the ambiguous boundary slots: "above" nests with the
// row above (e.g. last item of a group), "below" with the row below (right
// after the group, outside it) - chosen by the pointer's X position mid-drag.
// Dragging a group HEADER moves the whole block (extra.block).
function handleMove(id, index, extra) {
  // Use the order currently rendered, including optimistic reorder overrides.
  // The host-provided `index` fields can lag behind that view for one or more
  // frames after a bulk or group move.
  const ws = visibleWorkspaces();

  // Dropped ONTO a folder header (it highlights while hovered): the
  // workspace (or the whole multi-selection) joins that folder at its end.
  if (extra && extra.into && !extra.block && !id.startsWith("h:")) {
    const gid = String(extra.into).replace(/^h:/, "").replace(/:edit$/, "");
    if (!groupById(gid)) return;
    multiTick();
    const ids = multiSelected.has(id) && multiSelected.size > 1
      ? visibleRowIds().filter((rid) => multiSelected.has(rid) || rid === id)
      : [id];
    for (const rid of ids) {
      const row = ws.find((w) => w.id === rid);
      if (row && row.group !== gid) cmux("workspace.group.add", { group_id: gid, workspace_id: rid });
    }
    clearMultiSelect();
    return;
  }

  if (extra && extra.block && id.startsWith("h:")) {
    // Whole-group move. workspace.group.move is NOT usable here: its
    // to_index is a group-slot index (position among groups, clamped to the
    // pin tier), so a tabs index overshoots to "last group" and a drop
    // between ungrouped rows is unreachable. Instead send the full tabs
    // order with the block extracted and re-inserted contiguously (in its
    // visible order) at the drop slot - the app's contiguity normalization keeps it.
    const gid = id.slice(2);
    const memberIds = new Set(membersOf(gid).map((w) => w.id));
    const entries = flatEntries().filter((e) => e.id !== id && e.groupId !== gid);
    // The next entry that stays put anchors the drop. A header counts too:
    // dropping right above a (possibly collapsed) group means "before its
    // anchor", not "after its hidden members".
    const nextEntry = entries.slice(index).find((e) => e.kind === "ws" || e.kind === "header");
    const nextId = nextEntry
      ? (nextEntry.kind === "header" ? groupById(nextEntry.groupId)?.anchorId : nextEntry.wsId)
      : null;
    const blockIds = ws.map((x) => x.id).filter((x) => memberIds.has(x));
    const rest = ws.map((x) => x.id).filter((x) => !memberIds.has(x));
    let insertAt = nextId ? rest.indexOf(nextId) : rest.length;
    if (insertAt < 0) insertAt = rest.length;
    const full = [...rest.slice(0, insertAt), ...blockIds, ...rest.slice(insertAt)];
    setOrderOverride(full); // paint the new order now; reorder_many echoes behind it
    cmux("workspace.reorder_many", { workspace_ids: JSON.stringify(full) });
    return;
  }

  const dragged = ws.find((w) => w.id === id);
  if (!dragged) return;

  // Dragging a row that is part of the multi-selection moves the WHOLE
  // selection: the visible selected rows gather contiguously at the drop
  // slot (visual order preserved) and all take the slot's container. This is
  // the platform-standard resolution for non-contiguous selections and for
  // selections mixing in-group and ungrouped rows. Hidden rows (inside a
  // collapsed group) never move - what you see is what you drag.
  multiTick();
  const bulk = multiSelected.has(id) && multiSelected.size > 1;
  const movingIds = bulk
    ? visibleRowIds().filter((rid) => multiSelected.has(rid) || rid === id)
    : [id];
  const moving = new Set(movingIds);

  const entries = flatEntries().filter((e) => e.id !== id);
  // Neighbors that will NOT move: rows moving with the drag can't define the
  // drop's container or anchor.
  let prev = null;
  for (let i = index - 1; i >= 0; i -= 1) {
    const e = entries[i];
    if (e.kind === "ws" && moving.has(e.wsId ?? e.id)) continue;
    prev = e;
    break;
  }
  const stays = (e) => !(e.kind === "ws" && moving.has(e.wsId ?? e.id));
  // The drop's tabs-order anchor is the next entry that stays put. A header
  // resolves to its group's ANCHOR workspace: dropping above a group means
  // "before the whole block", never "between its anchor and members" (which
  // would break contiguity and get normalized somewhere else).
  const nextEntry = entries.slice(index).find((e) => {
    if (e.kind === "header") return !moving.has(groupById(e.groupId)?.anchorId);
    return e.kind === "ws" && stays(e);
  });
  const nextAny = entries.slice(index).find(stays) ?? null;
  const nextRefId = nextEntry
    ? (nextEntry.kind === "header" ? groupById(nextEntry.groupId)?.anchorId : (nextEntry.wsId ?? nextEntry.id))
    : null;
  const nextWorkspace = nextRefId ? ws.find((w) => w.id === nextRefId) : null;

  let container;
  if (extra && extra.side === "below") {
    // Nest with what's below: a header below means "above the next group",
    // i.e. ungrouped; a row below means its group (or ungrouped).
    container = nextAny && nextAny.kind === "ws" ? nextAny.groupId : null;
  } else {
    container = prev ? prev.groupId : null;
    // Dropping right below a collapsed group's header means "after the whole
    // group", not "into it" (its rows are hidden), unless it lives there.
    if (prev && prev.kind === "header") {
      const g = groupById(prev.groupId);
      if (g && isCollapsed(g) && dragged.group !== g.id) container = null;
    }
  }

  for (const rid of movingIds) {
    const row = ws.find((w) => w.id === rid);
    if (!row) continue;
    if ((row.group ?? null) !== container) {
      if (container) {
        cmux("workspace.group.add", { group_id: container, workspace_id: rid });
      } else {
        cmux("workspace.group.remove", { workspace_id: rid });
      }
    }
  }

  if (bulk) {
    // Atomic block placement: send the full tabs order with the moving rows
    // inserted contiguously before the anchor.
    const rest = ws.map((x) => x.id).filter((x) => !moving.has(x));
    let insertAt = nextWorkspace ? rest.indexOf(nextWorkspace.id) : rest.length;
    if (insertAt < 0) insertAt = rest.length;
    const full = [...rest.slice(0, insertAt), ...movingIds, ...rest.slice(insertAt)];
    const groupOf = (x) => (moving.has(x) ? container : ws.find((w) => w.id === x)?.group ?? null);
    syncAnchors(full, groupOf, new Set([container, ...movingIds.map((x) => ws.find((w) => w.id === x)?.group)].filter(Boolean)));
    setOrderOverride(full); // gather instantly; reorder_many echoes behind it
    cmux("workspace.reorder_many", { workspace_ids: JSON.stringify(full) });
    clearMultiSelect();
    return;
  }

  // A drop that changes a group's first row (into first place, or the
  // anchor moved down) needs the anchor handed over, then an absolute order.
  {
    const rest = ws.map((x) => x.id).filter((x) => x !== id);
    let insertAt = nextWorkspace ? rest.indexOf(nextWorkspace.id) : rest.length;
    if (insertAt < 0) insertAt = rest.length;
    const full = [...rest.slice(0, insertAt), id, ...rest.slice(insertAt)];
    const groupOf = (x) => (x === id ? container : ws.find((w) => w.id === x)?.group ?? null);
    const touched = [container, dragged.group].filter(Boolean);
    const changesFirst = touched.some((gid) => {
      const first = full.find((x) => groupOf(x) === gid);
      return first && first !== groupById(gid)?.anchorId;
    });
    if (changesFirst) {
      syncAnchors(full, groupOf, new Set(touched));
      setOrderOverride(full);
      cmux("workspace.reorder_many", { workspace_ids: JSON.stringify(full) });
      clearMultiSelect();
      return;
    }
  }

  if (nextWorkspace) {
    const draggedPosition = ws.findIndex((w) => w.id === dragged.id);
    const before = ws.findIndex((w) => w.id === nextWorkspace.id);
    const target = draggedPosition < before ? before - 1 : before;
    cmux("workspace.reorder", { workspace_id: id, index: target });
  } else {
    cmux("workspace.reorder", { workspace_id: id, index: ws.length - 1 });
  }
  // Dragging an unselected row with a selection active clears the stale
  // selection (platform convention).
  clearMultiSelect();
}

// --- agent state (compact) ---------------------------------------------------
// One word per workspace, right-aligned:
//   wait  an agent is asking you something (agents[].status == needs_input)
//   run   an agent is working (or the workspace lane is "working", e.g. Pi)
//   idle  the workspace hosts an agent that is doing nothing
// The workspace lane "needs-attention" on its own is NOT treated as waiting:
// Pi sets it after every finished turn, so it just means "your turn".
// A blue dot marks "finished while you were elsewhere"; it clears when you
// open the workspace.
const STATE_LABEL = { waiting: "wait", running: "run", idle: "idle" };
const STATE_COLOR = { waiting: "orange", running: "#4C8DFF", idle: "tertiary" };

function agentState(w) {
  if (!w) return null;
  const agents = (w.agents ?? []).filter((a) => a.status !== "ended");
  if (agents.some((a) => a.status === "needs_input")) return "waiting";
  if (agents.some((a) => a.status === "working") || w.status === "working") return "running";
  if (agents.length > 0) return "idle";
  return null;
}

// Tracks running -> not running transitions per workspace. Pure closure
// state, no signal writes, so it can live inside a computed.
const prevBusy = new Map();
const doneUnseen = new Set();
const doneTracker = computed(() => {
  const ws = data.workspaces() ?? [];
  const sel = data.selectedId();
  for (const w of ws) {
    const busy = agentState(w) === "running";
    if (prevBusy.get(w.id) === true && !busy && w.id !== sel) doneUnseen.add(w.id);
    if (busy || w.id === sel) doneUnseen.delete(w.id);
    prevBusy.set(w.id, busy);
  }
  return new Set(doneUnseen);
});
const isDoneUnseen = (w) => !!w && doneTracker().has(w.id);

// New workspace inside a folder; opens the folder so the new row shows.
function newWorkspaceInGroup(g) {
  if (!g) return;
  if (isCollapsed(g)) toggleCollapse(g);
  cmux("workspace.group.new_workspace", { group_id: g.id });
}

// New top-level folder. The app creates it with a fresh anchor workspace and
// an auto name ("Group N"); the watcher below drops the header we asked for
// straight into inline rename so the user can type the real name.
let pendingNewFolder = false;
const knownGroupIds = new Set();
let knownGroupsSeeded = false;
computed(() => {
  const groups = data.groups() ?? [];
  for (const g of groups) {
    if (knownGroupIds.has(g.id)) continue;
    knownGroupIds.add(g.id);
    if (knownGroupsSeeded && pendingNewFolder) {
      pendingNewFolder = false;
      setEditingId("h:" + g.id);
    }
  }
  knownGroupsSeeded = true;
});

function newFolder() {
  pendingNewFolder = true;
  cmux("workspace.group.create", {});
}

// Hover strip under the last folder/row: a small "+" that creates a folder.
function newFolderFooter() {
  return HStack({ spacing: 6 }, [
    Image("plus")
      .font(9).weight("semibold").color("secondary")
      .frame({ width: 14, height: 16 })
      .showOnHover(),
    Text("New Folder").font(11).color("secondary").showOnHover(),
    Spacer(),
  ])
    .paddingLeading(8)
    .paddingTrailing(8)
    .paddingVertical(3)
    .cornerRadius(8)
    .hoverBackground("#7f7f7f1c")
    .frame({ maxWidth: "infinity" })
    .help("New folder")
    .onTap(newFolder);
}

// --- rows ----------------------------------------------------------------------
function workspaceMenu(w) {
  const act = (action) => () =>
    cmux("workspace.action", { action, workspace_id: w().id });
  const groupItems = (data.groups() ?? []).map((g) =>
    Button(() => (groupById(g.id)?.name ?? ""), () => {
      for (const id of bulkIds(w())) cmux("workspace.group.add", { group_id: g.id, workspace_id: id });
      clearMultiSelect();
    }));
  const count = () => bulkIds(w()).length;
  return [
    Button(() => (count() > 1 ? "New Group from " + count() + " Workspaces" : "New Group with This"), () => {
      cmux("workspace.group.create", {
        name: "New Group",
        child_workspace_ids: JSON.stringify(bulkIds(w())),
      });
      clearMultiSelect();
    }),
    Divider(),
    Button("Rename", () => setEditingId(w().id)),
    Button(() => (w()?.pinned ? "Unpin" : "Pin"), () =>
      cmux("workspace.action", { action: w()?.pinned ? "unpin" : "pin", workspace_id: w().id })),
    Button(() => (w()?.unread > 0 ? "Mark as Read" : "Mark as Unread"), () =>
      cmux("workspace.action", { action: w()?.unread > 0 ? "mark_read" : "mark_unread", workspace_id: w().id })),
    Divider(),
    Menu("Move", [
      Button("Move Up", act("move_up")),
      Button("Move Down", act("move_down")),
      Button("Move to Top", act("move_top")),
    ]),
    Menu("Move to Group", groupItems),
    Button("Remove from Group", () => cmux("workspace.group.remove", { workspace_id: w().id })),
    Divider(),
    Button("Close Others", act("close_others")).destructive(),
    Button(() => (count() > 1 ? "Close " + count() + " Workspaces" : "Close"), () => {
      for (const id of bulkIds(w())) closeWorkspace(id);
      clearMultiSelect();
    }).destructive(),
  ];
}

function workspaceRow(w, entry) {
  // The title owns the FULL row width; badge, pin, and close button FLOAT
  // over its trailing edge (ZStack trailing) instead of reserving layout.
  // No fades anywhere (they read as glitches when they appear); overflow
  // truncates with a plain ellipsis, and a title too long to fit starts
  // marqueeing after the hover holds 0.5s.
  return ZStack({ alignment: "trailing" }, [
    HStack({ spacing: 0 }, [
      Text(() => displayTitle(w()))
        .font(12)
        .lineLimit(1)
        .truncation("tail")
        .marquee()
        .color(() => (isSelected(w()) ? "primary" : "secondary")),
      Spacer({ minLength: 0 }),
    ])
      .frame({ maxWidth: "infinity" }),
    HStack({ spacing: 5 }, [
      // Finished while you were away.
      Circle({ size: 6 })
        .fill(() => (isDoneUnseen(w()) ? "#4C8DFF" : "clear"))
        .hideOnHover(),
      // Unread count ("1") when something is waiting for you.
      Text(() => (w()?.unread > 0 ? String(w().unread) : ""))
        .font("caption2").bold().color("white")
        .paddingHorizontal(() => (w()?.unread > 0 ? 5 : 0))
        .paddingVertical(() => (w()?.unread > 0 ? 1 : 0))
        .background(() => (w()?.unread > 0 ? "#E4573D" : null))
        .cornerRadius(7)
        .hideOnHover(),
      // Agent state, right-aligned: running / waiting / idle.
      ZStack({ alignment: "trailing" }, [
        Text(() => STATE_LABEL[agentState(w())] ?? "")
          .font(10).monospaced()
          .color(() => STATE_COLOR[agentState(w())] ?? "tertiary")
          .hideOnHover(),
        // Close button replaces the status while hovering the row.
        Image("xmark")
          .font(9).weight("semibold").color("secondary")
          .padding(4)
          .cornerRadius(9)
          .hoverBackground("#7f7f7f4a")
          .showOnHover()
          .onTap(() => closeWorkspace(w().id)),
      ]),
    ]),
  ])
    .paddingHorizontal(8)
    .paddingVertical(3)
    .marginLeading(() => (entry().groupId ? 12 : 0))
    .cornerRadius(8)
    .background(() => (isMultiSelected(w()) ? "#4C9EEB33" : (isSelected(w()) ? "#7f7f7f3d" : null)))
    .borderColor(() => cursorRing(entry().wsId))
    .borderWidth(1.5)
    .hoverBackground(() => (isMultiSelected(w()) ? "#4C9EEB33" : (isSelected(w()) ? "#7f7f7f3d" : "#7f7f7f24")))
    .frame({ maxWidth: "infinity" })
    .block(() => (entry().groupId ? "h:" + entry().groupId : null))
    .dragSet(() => (isMultiSelected(w()) ? "multi" : null))
    .onTap((payload) => handleRowClick(w(), payload))
    .onDoubleTap(() => setEditingId(w().id))
    .contextMenu(workspaceMenu(w));
}

// In-place editor row (same box as a workspace row).
function workspaceEditRow(w, entry) {
  return HStack({ spacing: 8 }, [
    TextField(() => w()?.title ?? "", {
      placeholder: "Workspace name",
      onSubmit: (t) => {
        const title = (t ?? "").trim();
        if (title) {
          titleOverride.set(w().id, title);
          setTitleTick(titleTick() + 1);
          cmux("workspace.action", { action: "rename", workspace_id: w().id, title });
        } else {
          cmux("workspace.action", { action: "clear_name", workspace_id: w().id });
        }
        setEditingId(null);
      },
      onCancel: () => setEditingId(null),
    }).font(12),
  ])
    .paddingHorizontal(10)
    .paddingVertical(3)
    .cornerRadius(8)
    .background("#7f7f7f3d")
    .marginLeading(() => (entry().groupId ? 12 : 0))
    .frame({ maxWidth: "infinity" });
}

function groupHeader(groupId) {
  const g = () => groupById(groupId) ?? { id: groupId, name: "", collapsed: false, pinned: false };
  // Socket-path methods only: `workspace.group.action` exists solely on the
  // mobile RPC path, so routing through it here silently did nothing.
  const groupCall = (method) => () => cmux(method, { group_id: groupId });
  return HStack({ spacing: 6 }, [
    // A folder header: clicking anywhere on it toggles collapse (it has no
    // session of its own; the anchor is a normal row below). Chevron only,
    // no folder icon. One glyph that ROTATES (right -> down on expand):
    // rotation animates as one motion with the accordion, and the fixed box
    // keeps the header height constant.
    Image("chevron.right")
      .font(10).weight("semibold").color("tertiary")
      .rotation(() => (isCollapsed(g()) ? 0 : 90))
      .frame({ width: 14, height: 16 }),
    Text(() => g().name).font(11).weight("semibold").lineLimit(1).truncation("tail")
      .color("secondary"),
    Spacer(),
    // Hover-only "+" where a workspace row shows its close x: a new
    // workspace inside this folder.
    Image("plus")
      .font(9).weight("semibold").color("secondary")
      .frame({ width: 16, height: 16 })
      .cornerRadius(8)
      .hoverBackground("#7f7f7f4a")
      .help("New workspace in folder")
      .showOnHover()
      .onTap(() => newWorkspaceInGroup(g())),
  ])
    .paddingLeading(8)
    .paddingTrailing(8)
    .paddingVertical(3)
    .cornerRadius(8)
    .hoverBackground("#7f7f7f1c")
    .borderColor(() => cursorRing("h:" + groupId))
    .borderWidth(1.5)
    .frame({ maxWidth: "infinity" })
    .fixed()
    .block("h:" + groupId)
    .dropTarget()
    .onTap(() => toggleCollapse(g()))
    .onDoubleTap(() => setEditingId("h:" + groupId))
    .contextMenu([
      Button("New Workspace in Folder", () => newWorkspaceInGroup(g())),
      Divider(),
      Button("Rename Group", () => setEditingId("h:" + groupId)),
      Button(() => (isCollapsed(g()) ? "Expand" : "Collapse"), () => toggleCollapse(g())),
      Button(() => (g().pinned ? "Unpin Group" : "Pin Group"), () =>
        cmux(g().pinned ? "workspace.group.unpin" : "workspace.group.pin", { group_id: groupId })),
      Divider(),
      Button("New Folder", newFolder),
      Divider(),
      Button("Ungroup", groupCall("workspace.group.ungroup")),
      Button("Delete Group", groupCall("sidebar.workspace_group.confirm_delete")).destructive(),
    ]);
}

// Identical geometry to groupHeader (chevron box, paddings, semibold 12)
// so entering/leaving rename changes nothing but the text becoming editable.
function groupEditRow(groupId) {
  const g = () => groupById(groupId);
  return HStack({ spacing: 6 }, [
    Image("chevron.right")
      .font(10).weight("semibold").color("tertiary")
      .rotation(() => (isCollapsed(g() ?? {}) ? 0 : 90))
      .frame({ width: 14, height: 16 }),
    TextField(() => g()?.name ?? "", {
      placeholder: "Group name",
      onSubmit: (t) => {
        const name = (t ?? "").trim();
        if (name) cmux("workspace.group.rename", { group_id: groupId, name });
        setEditingId(null);
      },
      onCancel: () => setEditingId(null),
    }).font(11).weight("semibold"),
  ])
    .paddingLeading(8)
    .paddingTrailing(10)
    .paddingVertical(3)
    .cornerRadius(8)
    .background("#7f7f7f3d")
    .frame({ maxWidth: "infinity" })
    .fixed();
}

// --- root ------------------------------------------------------------------------
sidebar(() =>
  VStack({ spacing: 4 }, [
  Reorderable(
    {
      items: flatEntries,
      key: (e) => e.id,
      spacing: 0,
      onMove: handleMove,
    },
    (e, key) => {
      const entry = e(); // kind, ids, and editing are stable per key
      if (entry.kind === "header") {
        return entry.editing ? groupEditRow(entry.groupId) : groupHeader(entry.groupId);
      }
      const w = () => (data.workspaces() ?? []).find((x) => x.id === entry.wsId);
      return entry.editing ? workspaceEditRow(w, e) : workspaceRow(w, e);
    }
  ),
  newFolderFooter(),
  ]),
  { surface: "glass" }
)
