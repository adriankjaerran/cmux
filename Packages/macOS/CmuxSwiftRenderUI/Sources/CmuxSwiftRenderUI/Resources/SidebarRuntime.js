"use strict";
// cmux sidebar JS runtime prelude.
//
// A fine-grained reactive scene runtime, SolidJS-shaped: the sidebar program
// runs ONCE, builds a retained scene graph, and subscribes to host data via
// signals. Data changes re-run only the effects that read them, emitting
// minimal scene ops (single-prop updates, keyed child reconciles) that the
// host applies to @Observable scene nodes. Nothing re-renders per tick.
//
// Host bridge (injected by SidebarJSRuntime.swift before this file runs):
//   __host_applyOps(jsonString)  - apply a batch of scene ops
//   __host_action(jsonString)    - run captured commands (cmux/openURL/log)
//   __host_log(string)           - debug logging
//   __host_clipboardWrite(string) -> bool - write-only clipboard, honored
//                                  only during a click/menu-action dispatch
// Host entry points (defined here, called by Swift):
//   __setData(key, jsonString)   - update one data key
//   __dispatch(nodeId, event, jsonString) - deliver a UI event
//   __mount(fn)                  - internal: run the sidebar program

(function () {
  // ---------------------------------------------------------------------
  // Reactive core
  // ---------------------------------------------------------------------
  let currentEffect = null;
  let currentScope = null;
  const pendingEffects = new Set();
  let running = false;

  function createSignal(initial) {
    let value = initial;
    const subscribers = new Set();
    const read = () => {
      if (currentEffect) {
        subscribers.add(currentEffect);
        currentEffect.deps.push(subscribers);
      }
      return value;
    };
    const write = (next) => {
      if (Object.is(value, next)) return;
      value = next;
      for (const eff of Array.from(subscribers)) pendingEffects.add(eff);
      scheduleRun();
    };
    return [read, write];
  }

  function createEffect(fn) {
    const eff = {
      deps: [],
      disposed: false,
      run() {
        if (eff.disposed) return;
        cleanupDeps(eff);
        const prevEffect = currentEffect;
        currentEffect = eff;
        try {
          fn();
        } finally {
          currentEffect = prevEffect;
        }
      },
    };
    if (currentScope) currentScope.effects.push(eff);
    eff.run();
    return eff;
  }

  function cleanupDeps(eff) {
    for (const subscribers of eff.deps) subscribers.delete(eff);
    eff.deps = [];
  }

  function scheduleRun() {
    if (running) return; // drained by the active runPending pass
    runPending();
  }

  function runPending() {
    running = true;
    try {
      let guard = 0;
      while (pendingEffects.size > 0) {
        if (++guard > 1000) {
          throw new Error("sidebar effect loop did not settle (1000 rounds)");
        }
        const batch = Array.from(pendingEffects);
        pendingEffects.clear();
        for (const eff of batch) eff.run();
      }
    } finally {
      running = false;
      flushOps();
    }
  }

  // Scopes own effects and child nodes for disposal (row unmount).
  function createScope(parent) {
    return { effects: [], nodes: [], children: [], parent };
  }

  function runInScope(scope, fn) {
    const prev = currentScope;
    if (prev) {
      prev.children.push(scope);
      scope.parent = prev;
    }
    currentScope = scope;
    try {
      return fn();
    } finally {
      currentScope = prev;
    }
  }

  function disposeScope(scope) {
    // Detach from the parent, or a churning keyed list retains every
    // unmounted row scope in the long-lived owner forever.
    if (scope.parent) {
      const siblings = scope.parent.children;
      const at = siblings.indexOf(scope);
      if (at >= 0) siblings.splice(at, 1);
      scope.parent = null;
    }
    for (const child of scope.children) {
      child.parent = null; // already being disposed with us; skip the splice
      disposeScope(child);
    }
    scope.children = [];
    for (const eff of scope.effects) {
      eff.disposed = true;
      cleanupDeps(eff);
      pendingEffects.delete(eff);
    }
    scope.effects = [];
    for (const id of scope.nodes) {
      const nodeHandlers = handlers[id];
      delete handlers[id];
      pushOp({ op: "remove", id });
      // Native onDisappear arrives after this handler is gone. Clear the
      // owning sidebar's signal here when JS removes an active list.
      if (nodeHandlers && nodeHandlers.dragActive && nodeHandlers.dragChange) {
        nodeHandlers.dragChange(null);
      }
    }
    scope.nodes = [];
  }

  // ---------------------------------------------------------------------
  // Scene ops
  // ---------------------------------------------------------------------
  let nextId = 1;
  let ops = [];
  const handlers = Object.create(null);

  function pushOp(op) {
    ops.push(op);
  }

  function flushOps() {
    if (ops.length === 0) return;
    const batch = ops;
    ops = [];
    __host_applyOps(JSON.stringify(batch));
  }

  // ---------------------------------------------------------------------
  // Node handles and builders
  // ---------------------------------------------------------------------
  // Reactive prop: a function-valued prop re-evaluates in its own effect and
  // emits a single-prop update op when its value changes.
  function setProp(id, key, value) {
    if (typeof value === "function") {
      createEffect(() => {
        pushOp({ op: "update", id, key, value: normalizeProp(value()) });
      });
    } else {
      pushOp({ op: "update", id, key, value: normalizeProp(value) });
    }
  }

  function normalizeProp(v) {
    if (v === null || v === undefined) return null;
    const t = typeof v;
    if (t === "string" || t === "boolean") return v;
    if (t === "number") return Number.isFinite(v) ? v : null;
    return String(v);
  }

  const chainableProps = [
    "font", "color", "padding", "background", "cornerRadius", "opacity",
    "bold", "italic", "monospaced", "lineLimit", "spacing", "size",
    "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
    "alignment", "fill", "stroke", "strokeWidth", "systemName", "value",
    "help", "truncation", "weight", "secondary", "borderColor", "borderWidth",
    "hoverBackground", "paddingHorizontal", "paddingVertical", "destructive",
    "paddingLeading", "paddingTrailing", "paddingTop", "paddingBottom",
    "fixed", "block", "layoutPriority", "marginLeading",
    "showOnHover", "hideOnHover", "dragBackground", "dragSet", "rotation",
    "fade", "marquee", "fixedSize", "cursor", "dropTarget",
  ];

  function makeHandle(id) {
    const handle = { __nodeId: id };
    for (const key of chainableProps) {
      handle[key] = (value) => {
        // Bare `.bold()` / `.secondary()` style toggles default to true.
        setProp(id, key, value === undefined ? true : value);
        return handle;
      };
    }
    handle.frame = (spec) => {
      // A function spec binds every key it returns: `.frame(() => ({ width: w() }))`.
      // Keys are taken from the first evaluation, read untracked so a
      // `.frame(fn)` inside a ForEach row doesn't subscribe the list effect.
      if (typeof spec === "function") {
        const prevEffect = currentEffect;
        currentEffect = null;
        let keys;
        try {
          keys = Object.keys(spec() || {});
        } finally {
          currentEffect = prevEffect;
        }
        for (const k of keys) setProp(id, k, () => (spec() || {})[k]);
        return handle;
      }
      for (const k of Object.keys(spec || {})) setProp(id, k, spec[k]);
      return handle;
    };
    handle.onTap = (fn) => {
      handlers[id] = handlers[id] || {};
      handlers[id].tap = fn;
      setProp(id, "tappable", true);
      return handle;
    };
    // Double-click (e.g. rename affordance). Coexists with onTap: the host
    // registers the two-click recognizer first, so a double fires this and
    // not two taps.
    handle.onDoubleTap = (fn) => {
      handlers[id] = handlers[id] || {};
      handlers[id].doubletap = fn;
      setProp(id, "doubleTappable", true);
      return handle;
    };
    // Right-click menu: the items (Button / Menu / Divider / Text) become a
    // contextMenu child node; the host renders it as the view's context menu
    // instead of inline content.
    handle.contextMenu = (children) => {
      const menu = makeNode("contextMenu", {}, children);
      pushOp({ op: "append", id, child: menu.__nodeId });
      return handle;
    };
    return handle;
  }

  function applyProps(id, props) {
    for (const key of Object.keys(props || {})) {
      const value = props[key];
      if (key === "onTap" || key === "onMove") {
        handlers[id] = handlers[id] || {};
        handlers[id][key === "onTap" ? "tap" : "move"] = value;
        if (key === "onTap") setProp(id, "tappable", true);
        continue;
      }
      setProp(id, key, value);
    }
  }

  function childIds(children) {
    const out = [];
    for (const child of flatten(children)) {
      if (child && child.__nodeId) out.push(child.__nodeId);
    }
    return out;
  }

  function flatten(children) {
    if (!children) return [];
    if (!Array.isArray(children)) return [children];
    const out = [];
    for (const c of children) {
      if (Array.isArray(c)) out.push(...flatten(c));
      else out.push(c);
    }
    return out;
  }

  function makeNode(type, props, children) {
    const id = "n" + nextId++;
    if (currentScope) currentScope.nodes.push(id);
    pushOp({ op: "create", id, type });
    applyProps(id, props);
    if (children !== undefined) {
      pushOp({ op: "children", id, children: childIds(children) });
    }
    return makeHandle(id);
  }

  // Container builders accept (props, children) or just (children).
  function container(type) {
    return (a, b) => {
      if (Array.isArray(a) || (a && a.__nodeId)) return makeNode(type, {}, a);
      return makeNode(type, a || {}, b || []);
    };
  }

  const g = globalThis;
  g.VStack = container("vstack");
  g.HStack = container("hstack");
  g.ZStack = container("zstack");
  g.LazyVStack = container("lazyVStack");
  g.Group = container("group");

  g.Text = (text, props) => {
    const node = makeNode("text", props || {});
    setProp(node.__nodeId, "text", text);
    return node;
  };
  g.Image = (systemName, props) => makeNode("image", { systemName, ...(props || {}) });
  g.Spacer = (props) => makeNode("spacer", props || {});
  g.Divider = (props) => makeNode("divider", props || {});
  g.Circle = (props) => makeNode("circle", props || {});
  g.Capsule = (props) => makeNode("capsule", props || {});
  g.Rectangle = (props) => makeNode("rectangle", props || {});
  g.RoundedRectangle = (props) => makeNode("roundedRectangle", props || {});
  g.ProgressView = (props) => makeNode("progress", props || {});

  // Submenu inside a context menu (or a standalone menu button).
  g.Menu = (title, children) => {
    const node = makeNode("menu", {}, children);
    setProp(node.__nodeId, "text", title);
    return node;
  };

  // Editable one-line text field. `value` is the initial text (string or
  // binding); opts: placeholder, onSubmit(text), onCancel(), onEdit(text)
  // (fires per keystroke - live search), autofocus (default true; pass
  // false for persistent fields that should wait for a click). The host
  // focuses an autofocus field on appear only when the user gave the sidebar
  // focus: its click handler just created it and focus hasn't moved since
  // (rename editors), or focus is already in one of its fields. A field mounted any other way, such as by a data update while
  // the user types in a terminal, stays unfocused. Return submits, Escape
  // cancels.
  g.TextField = (value, opts) => {
    const node = makeNode("textfield", {});
    setProp(node.__nodeId, "text", value);
    if (opts && opts.placeholder) setProp(node.__nodeId, "placeholder", opts.placeholder);
    if (opts && opts.autofocus === false) setProp(node.__nodeId, "autofocus", false);
    handlers[node.__nodeId] = handlers[node.__nodeId] || {};
    if (opts && opts.onSubmit) handlers[node.__nodeId].submit = opts.onSubmit;
    if (opts && opts.onCancel) handlers[node.__nodeId].cancel = opts.onCancel;
    if (opts && opts.onEdit) handlers[node.__nodeId].edit = opts.onEdit;
    return node;
  };

  g.Button = (label, action, children) => {
    const node = makeNode("button", {}, children);
    if (typeof label === "string" || typeof label === "function") {
      setProp(node.__nodeId, "text", label);
    }
    if (typeof action === "function") {
      handlers[node.__nodeId] = handlers[node.__nodeId] || {};
      handlers[node.__nodeId].tap = action;
    }
    return node;
  };

  // ---------------------------------------------------------------------
  // Keyed list reconciliation (ForEach / Reorderable)
  // ---------------------------------------------------------------------
  // items: array or accessor; key: (item) => string; template: (itemAccessor,
  // keyString) => handle. Rows mount once per key; kept rows get their item
  // signal updated (value-compared, so unchanged rows do nothing); removed
  // rows dispose their scope (effects + nodes).
  function keyedList(type, opts, template) {
    const items = opts.items;
    const keyFn = opts.key || ((item) => String(item && item.id !== undefined ? item.id : item));
    // Scalar options (e.g. spacing) become node props; the wiring keys are not.
    const props = {};
    for (const k of Object.keys(opts)) {
      if (k !== "items" && k !== "key" && k !== "onMove" && k !== "onDragChange") props[k] = opts[k];
    }
    const node = makeNode(type, props, []);
    const id = node.__nodeId;
    if (opts.onMove) {
      handlers[id] = handlers[id] || {};
      handlers[id].move = opts.onMove;
    }
    if (typeof opts.onDragChange === "function") {
      handlers[id] = handlers[id] || {};
      handlers[id].dragChange = opts.onDragChange;
      pushOp({ op: "update", id, key: "reportsDrag", value: true });
    }
    const rows = new Map(); // key -> {scope, rootId, setItem, serialized}
    const owner = currentScope;

    createEffect(() => {
      const list = typeof items === "function" ? items() : items;
      const arr = Array.isArray(list) ? list : [];
      const seen = new Set();
      const order = [];
      const orderedKeys = [];
      for (const item of arr) {
        const key = String(keyFn(item));
        if (seen.has(key)) continue; // ignore duplicate keys
        seen.add(key);
        let row = rows.get(key);
        const serialized = JSON.stringify(item);
        if (!row) {
          const scope = createScope(owner);
          const [readItem, writeItem] = createSignal(item);
          const handle = runInScope(scope, () => template(readItem, key));
          row = { scope, rootId: handle ? handle.__nodeId : null, setItem: writeItem, serialized };
          rows.set(key, row);
        } else if (row.serialized !== serialized) {
          row.serialized = serialized;
          row.setItem(item);
        }
        if (row.rootId) {
          order.push(row.rootId);
          orderedKeys.push(key);
        }
      }
      for (const [key, row] of Array.from(rows.entries())) {
        if (!seen.has(key)) {
          disposeScope(row.scope);
          rows.delete(key);
        }
      }
      pushOp({ op: "children", id, children: order });
      // Reorderable rows carry their item keys (JSON array, parallel to
      // children) so the host can report moves by item id. Keys were
      // collected during the reconcile loop; no second scan.
      if (type === "reorderable") {
        pushOp({ op: "update", id, key: "itemKeys", value: JSON.stringify(orderedKeys) });
      }
    });
    return node;
  }

  g.ForEach = (opts, template) => keyedList("group", opts, template);
  g.Reorderable = (opts, template) => keyedList("reorderable", opts, template);

  // ---------------------------------------------------------------------
  // Host data and actions
  // ---------------------------------------------------------------------
  const dataSignals = new Map(); // key -> [read, write]

  function dataSignal(key) {
    let sig = dataSignals.get(key);
    if (!sig) {
      sig = createSignal(undefined);
      dataSignals.set(key, sig);
    }
    return sig;
  }

  g.data = new Proxy({}, {
    get(_t, key) {
      if (typeof key !== "string") return undefined;
      return () => dataSignal(key)[0]();
    },
  });

  // Author-facing reactive state: `const [open, setOpen] = signal(false)`.
  // Reads inside any function-valued prop subscribe it; writes re-run exactly
  // the bindings that read it.
  g.signal = (initial) => createSignal(initial);
  g.computed = (fn) => {
    const [read, write] = createSignal(undefined);
    createEffect(() => write(fn()));
    return read;
  };

  g.cmux = (method, params) => {
    const p = {};
    for (const k of Object.keys(params || {})) p[k] = String(params[k]);
    __host_action(JSON.stringify({ kind: "cmux", method, params: p }));
  };
  g.openURL = (url) => __host_action(JSON.stringify({ kind: "openURL", url: String(url) }));
  g.log = (message) => __host_action(JSON.stringify({ kind: "log", message: String(message) }));
  // Write-only clipboard. The host writes only while it is dispatching a
  // click, double-click or menu item to this sidebar; anywhere else (load,
  // data effects, text-field submits, deferred callbacks) the call returns
  // false and logs why. There is no read.
  g.clipboard = Object.freeze({
    write: (text) => __host_clipboardWrite(text === undefined || text === null ? "" : String(text)) === true,
  });

  // ---------------------------------------------------------------------
  // Keyboard mode
  // ---------------------------------------------------------------------
  // The host's Focus Sidebar shortcut puts the window in "sidebar keyboard
  // mode": the terminal stops getting keys and every key-down goes to the
  // program's `onKey(fn)` handler instead. `keyboardMode()` is a reactive
  // read of whether that mode is on (draw a cursor ring with it);
  // `onKeyboardMode(fn)` runs on every change. A sidebar without `onKey`
  // never enters the mode.
  //
  // fn({ key, shift, command, option, control }) gets the key as "up",
  // "down", "left", "right", "return", "space", "escape", "tab", "delete",
  // or the typed character ("c"). It returns:
  //   true / { handled: true }  - consumed, stay in the mode
  //   false / undefined         - not handled: the host ends the mode and
  //                               the key goes on to its normal target
  //   { exit: true }            - consumed, leave the mode (focus returns
  //                               to the panel that had it)
  //   { open: workspaceId }     - consumed, leave the mode, select that
  //                               workspace and focus its terminal
  let keyHandler = null;
  let keyModeHandler = null;
  const [keyboardActive, setKeyboardActive] = createSignal(false);
  g.keyboardMode = () => keyboardActive();
  g.onKey = (fn) => {
    keyHandler = typeof fn === "function" ? fn : null;
  };
  g.onKeyboardMode = (fn) => {
    keyModeHandler = typeof fn === "function" ? fn : null;
  };

  // Pure list navigation for keyboard mode, shared by sidebars built from a
  // flat row list with collapsible groups.
  //
  // rows: the VISIBLE rows, top to bottom. A group header is
  //   { id, header: true, group, collapsed }; any other row is
  //   { id, group } (group null/undefined when ungrouped). Members of a
  //   collapsed group are simply not in the list.
  // cursor: the current row id (an id not in `rows` starts at the top).
  // key: the onKey key string.
  //
  // Returns { cursor, handled } plus at most one effect:
  //   collapse / expand / toggle: group id to change
  //   open: row id to open (Return/Space on a non-header row)
  //   exit: true (Escape)
  // Up/Down stop at the ends. Left on a row in a group jumps to its header
  // and collapses the group; Left on an expanded header collapses it.
  // Right on a collapsed header expands it; on an expanded header it steps
  // into the first member. Return/Space toggle a header and open a row.
  g.sidebarKeyNav = (rows, cursor, key) => {
    const list = Array.isArray(rows) ? rows : [];
    let at = list.findIndex((r) => r && r.id === cursor);
    if (at < 0) at = list.length > 0 ? 0 : -1;
    const row = at >= 0 ? list[at] : null;
    const out = { cursor: row ? row.id : null, handled: true };
    const headerOf = (group) => list.find((r) => r.header && r.group === group);
    switch (key) {
      case "up":
        if (at > 0) out.cursor = list[at - 1].id;
        return out;
      case "down":
        if (at >= 0 && at < list.length - 1) out.cursor = list[at + 1].id;
        return out;
      case "left":
        if (!row) return out;
        if (row.header) {
          if (!row.collapsed) out.collapse = row.group;
        } else if (row.group) {
          const header = headerOf(row.group);
          if (header) {
            out.cursor = header.id;
            if (!header.collapsed) out.collapse = row.group;
          }
        }
        return out;
      case "right":
        if (!row || !row.header) return out;
        if (row.collapsed) {
          out.expand = row.group;
        } else {
          const next = list[at + 1];
          if (next && !next.header && next.group === row.group) out.cursor = next.id;
        }
        return out;
      case "return":
      case "space":
        if (!row) return out;
        if (row.header) out.toggle = row.group;
        else out.open = row.id;
        return out;
      case "escape":
        out.exit = true;
        return out;
      default:
        out.handled = false;
        return out;
    }
  };

  // ---------------------------------------------------------------------
  // Host entry points
  // ---------------------------------------------------------------------
  g.__hasKeyHandler = () => keyHandler !== null;

  g.__setKeyboardMode = (on) => {
    const active = !!on;
    setKeyboardActive(active);
    if (keyModeHandler) keyModeHandler(active);
    runPending();
  };

  // Returns a JSON string { handled, exit, open, close } for the host.
  g.__key = (json) => {
    if (!keyHandler) return JSON.stringify({ handled: false });
    let result;
    try {
      result = keyHandler(JSON.parse(json));
    } finally {
      runPending();
    }
    if (result === true) return JSON.stringify({ handled: true });
    if (!result || typeof result !== "object") return JSON.stringify({ handled: false });
    const open = result.open === undefined || result.open === null ? null : String(result.open);
    const close = result.close === undefined || result.close === null ? null : String(result.close);
    return JSON.stringify({
      handled: result.handled !== false || open !== null || close !== null || !!result.exit,
      exit: !!result.exit || open !== null,
      open,
      close,
    });
  };

  g.__setData = (key, json) => {
    dataSignal(key)[1](JSON.parse(json));
    runPending();
  };

  g.__dispatch = (nodeId, event, json) => {
    const nodeHandlers = handlers[nodeId];
    if (!nodeHandlers) return;
    const payload = json ? JSON.parse(json) : null;
    if (event === "tap" && nodeHandlers.tap) nodeHandlers.tap(payload);
    if (event === "move" && nodeHandlers.move) nodeHandlers.move(payload.id, payload.index, payload);
    if (event === "dragChange" && nodeHandlers.dragChange) {
      const state = payload && payload.id !== undefined ? payload : null;
      nodeHandlers.dragActive = state !== null;
      nodeHandlers.dragChange(state);
    }
    if (event === "doubletap" && nodeHandlers.doubletap) nodeHandlers.doubletap(payload);
    if (event === "submit" && nodeHandlers.submit) nodeHandlers.submit(payload ? payload.text : "");
    if (event === "cancel" && nodeHandlers.cancel) nodeHandlers.cancel(payload);
    if (event === "edit" && nodeHandlers.edit) nodeHandlers.edit(payload ? payload.text : "");
    runPending();
  };

  // Optional second argument: surface options applied as root props.
  // `surface: "glass"` asks the host to render the whole sidebar surface as
  // translucent material (liquid glass) instead of its opaque backdrop.
  g.sidebar = (fn, opts) => {
    const rootScope = createScope(null);
    const handle = runInScope(rootScope, fn);
    if (!handle || !handle.__nodeId) {
      throw new Error("sidebar(fn) must return a view (e.g. VStack([...]))");
    }
    if (opts) applyProps(handle.__nodeId, opts);
    pushOp({ op: "root", id: handle.__nodeId });
    runPending();
  };
})();
