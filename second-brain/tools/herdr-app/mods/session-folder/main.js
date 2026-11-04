// A lazy file browser for the focused pane's folder, with bounded read-only previews, and above it the
// second-brain session folder of the Claude Code session running in that pane (session.md, docs/,
// recap.log) as a collapsible Session section. The session comes from the hc label
// `second-brain.session=<session folder on that machine>` that the second-brain plugin's hooks keep on
// the terminal hosting the session (ADR-0012): declared, never detected, so a pane without one has no
// Session section, and the section goes when the session ends.
//
// A clone of the Herdr app's shipped `files` mod, which Herdr restores on every start. Source of truth:
// second-brain/tools/herdr-app/mods/session-folder/ in sundayhao-plugins. Install, on the Mac:
//   1. copy that folder to ~/.config/herdr-app/mods/session-folder/ and run
//      `herdr-app check ~/.config/herdr-app/mods/session-folder`;
//   2. in a personal layout, change the `files` block's "mod": "files" to "mod": "session-folder". The shipped
//      `main` is replaced on every start, so clone it first: herdr-app do layout.clone '{"name":"main","as":"<yours>"}'.
//      The tab bar's Files button targets the block id `files`, not the mod, so it keeps working.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState } from "gpui-base";
import { spaces, panes, focused, terminals, exec, readTextFile, watchFolder, theme, settings, window } from "herdr";

function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  // Strictly the focused terminal's own session: a pane's terminal, or a focused terminal block's (a peek).
  // The label is a path on the terminal's machine, which its address names: a remote address carries its
  // machine/ prefix in panes() and terminals() alike, so the two compare as they are.
  const address = pane ? pane.terminal : f?.pane === null ? f.terminal : null;
  const t = address ? terminals().find(t => t.address === address) : null;
  // The label outlives a session that died without its end hook (killed, crashed, a reboot that brings the
  // terminal back as a shell), so it is trusted only while claude, the one program whose hooks write it, is the
  // terminal's foreground. Not program.agent or status: measured in this app, both keep a dead agent's last
  // report, still agent and idle 35 s after a SIGKILL left zsh in front, while `foreground` followed within a
  // second. It is the hooks' own test too: a claude started by a wrapper that does not exec shows the wrapper
  // in front, and its hooks never set the label.
  const session = (/(^|\/)claude$/.test(t?.foreground?.argv?.[0] ?? "") && t.labels?.["second-brain.session"]) || null;
  const sessionOn = session && address.includes("/") ? address.split("/")[0] : null;
  return { project: pane?.cwd || f?.cwd || space?.folder || null, session, sessionOn, on, space: space?.id };
}
const key = () => JSON.stringify(location());
const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", toml: "yaml", jsonc: "json", svelte: "html", vue: "html" };
const PER_FOLDER = 500, TOTAL = 5000;

// The session's name from its note, re-read on every refresh so a /rename shows up. Read the way the plugin's
// read_frontmatter_prop reads it: a double-quoted value is unescaped, and a bare one, which is what Obsidian
// leaves when a person saves a note whose quotes were not needed, is taken as it is.
async function sessionName(folder, on) {
  const text = await readTextFile(`${folder}/session.md`, { on }).catch(() => null);
  const v = text?.split(/^---$/m)[1]?.match(/^session_name: *(.*)$/m)?.[1] ?? "";
  return /^".*"$/.test(v) ? v.slice(1, -1).replaceAll('\\"', '"').replaceAll("\\\\", "\\") : v;
}
// What the plugin shows for an unnamed session: its day and the first eight characters of its id.
function sessionFallback(folder) { const [id, date] = folder.split("/").reverse(); return `${date} · ${id.slice(0, 8)}`; }

async function directory(path, on) {
  if (!on && window()?.platform === "windows") {
    // Windows PowerShell otherwise uses the console code page; exec decodes UTF-8.
    // Reparse points keep directory attributes even when dangling; check their target.
    const r = await exec("powershell", ["-NoProfile", "-Command", "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); & { param($p) @(Get-ChildItem -LiteralPath $p -Force -ErrorAction Stop | Where-Object Name -ne '.git' | Select-Object -First 501 | ForEach-Object { @{ name=$_.Name; dir=($_.PSIsContainer -and (-not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($_.Target -and [IO.Directory]::Exists(([IO.Path]::Combine([IO.Path]::GetDirectoryName($_.FullName), $_.Target[0])))))) } }) | ConvertTo-Json -Compress } '" + path.replaceAll("'", "''") + "'"]);
    if (r.code !== 0) throw new Error(r.stderr || "Cannot list this folder");
    const result = JSON.parse(r.stdout || "[]");
    return Array.isArray(result) ? result : [result];
  }
  const script = 'n=0; for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do [ -e "$p" ] || [ -L "$p" ] || continue; name=${p##*/}; [ "$name" = .git ] && continue; if [ -d "$p" ]; then kind=d; else kind=f; fi; printf "%s\\0%s\\0" "$kind" "$name"; n=$((n+1)); [ "$n" -gt 500 ] && break; done; test -d "$1"';
  const r = await exec("sh", ["-c", script, "files", path], { on });
  if (r.code !== 0) throw new Error(r.stderr || "Cannot list this folder");
  const fields = r.stdout.split("\0"), out = [];
  for (let i = 0; i + 1 < fields.length; i += 2) out.push({ name: fields[i + 1], dir: fields[i] === "d" });
  return out;
}

export default class Files extends View {
  init(_props, cx) {
    this.saved = new Map();
    // Two roots in one tree, each with its own folder, machine, entries, expansion, errors and limit: Session
    // above Project. `watches` holds the local folders being watched.
    this.session = { id: "session", label: "Session", initial: ["docs"] };
    this.project = { id: "project", label: "Project", initial: [] };
    this.sections = [this.session, this.project];
    for (const sec of this.sections) Object.assign(sec, { root: null, on: null, entries: new Map(), folders: new Set(), pending: new Set(), marks: {}, open: true });
    this.watches = new Set();
    this.refresh(cx);
    cx.timer.every(10000, cx => this.refresh(cx));
  }

  // One watch per local folder shown, the session folder included, kept across pane hops that keep the folder:
  // hopping between a Claude pane and a shell beside it starts no second watch. It ends after an event once no
  // section shows the folder. A remote folder relies on the 10 s timer.
  watch(sec, cx) {
    const root = sec.root;
    if (sec.on || this.watches.has(root)) return;
    this.watches.add(root);
    cx.spawn(async cx => {
      try { for (;;) { await watchFolder(root); if (!this.sections.some(s => s.root === root && !s.on)) break; this.refresh(cx); } }
      catch {}
      finally { this.watches.delete(root); }
    });
  }

  current(context) {
    return this.context === context && key() === context.key;
  }

  async loadFolder(sec, path, context) {
    const entries = await directory(path ? `${sec.root}/${path}` : sec.root, sec.on);
    if (!this.current(context) || (path && !sec.folders.has(path))) return;
    const used = [...sec.entries.entries()].filter(([p]) => p !== path).reduce((n, [, e]) => n + e.length, 0);
    sec.entries.set(path, entries.slice(0, Math.max(0, Math.min(PER_FOLDER, TOTAL - used))).sort((a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name)));
    if (entries.length > PER_FOLDER || used + entries.length > TOTAL) sec.limited = true;
  }

  // A section keeps its tree across a pane switch that keeps its root, so a shell split beside the Claude
  // pane leaves the Project tree as it was; a root change is saved by the old key and restored by the new.
  // The Session section starts with docs/ open.
  // Returns what was saved for the new folder when the section moved, else null.
  place(sec, root, on) {
    if (sec.root === root && sec.on === on) return null;
    if (sec.root) this.saved.set(sec.key, { folders: sec.folders, open: sec.open, file: this.file?.sec === sec ? this.file.path : null });
    const saved = this.saved.get(sec.key = JSON.stringify({ section: sec.id, folder: root, on })) ?? {};
    Object.assign(sec, { root, on, entries: new Map(), folders: new Set(saved.folders ?? sec.initial), open: saved.open ?? true, marks: {}, name: null });
    if (this.file?.sec === sec) this.show(null);
    return saved;
  }

  refresh(cx) {
    const loc = location(), next = JSON.stringify(loc);
    if (next !== this.context?.key) {
      this.context = { key: next };
      const moved = this.sections.map(sec => { Object.assign(sec, { pending: new Set(), limited: false, error: null }); return [sec, this.place(sec, loc[sec.id], sec === this.session ? loc.sessionOn : loc.on)]; });
      // One preview at a time, brought back once every section has moved: a file open from a section that kept its
      // folder stays, and one from a folder that went is already closed.
      for (const [sec, saved] of moved) if (saved?.file && !this.file) this.show(sec, saved.file, cx);
      this.loading = false;
    }
    if (this.loading || !this.sections.some(s => s.root)) return;
    const context = this.context;
    this.loading = true;
    for (const sec of this.sections) sec.limited = false;
    cx.spawn(async cx => {
      try {
        for (const sec of this.sections) {
          if (!sec.root) continue;
          // Each section fails on its own, and only its own folder failing is an error: a session folder that cannot
          // be listed keeps its header and one row saying so, while an opened subfolder that has gone is closed.
          try {
            const name = sec === this.session ? await sessionName(sec.root, sec.on) : null;
            for (const path of ["", ...sec.folders]) {
              if (!this.current(context)) return;
              try { await this.loadFolder(sec, path, context); }
              catch (e) { if (!path) throw e; sec.folders.delete(path); sec.entries.delete(path); }
            }
            if (!this.current(context)) return;
            sec.name = name; sec.error = null;
          } catch (e) { if (this.current(context)) { sec.error = String(e); sec.entries = new Map(); } }
          // A redraw per section, so a tree shows as soon as it is listed rather than after every listing and the
          // project's git status: on a remote pane the Session tree otherwise waited about 2 s behind its header.
          if (this.current(context)) cx.notify();
        }
        const cwd = this.project.root, on = this.project.on, marks = {};
        const top = cwd ? await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on }).catch(() => null) : null;
        if (top?.code === 0) {
          // Writes nothing under .git (index lock, fsmonitor cookie): the folder watch would refresh again.
          const status = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"], { cwd, on }).catch(() => null);
          if (status?.code === 0) for (const entry of status.stdout.split("\0").filter(Boolean).slice(0, TOTAL)) {
            const xy = entry.slice(0, 2);
            marks[`${top.stdout.trim()}/${entry.slice(3)}`] = xy === "??" || xy.includes("A") ? "A" : xy.includes("U") ? "U" : xy.includes("D") ? "D" : "M";
          }
        }
        if (!this.current(context)) return;
        this.project.marks = marks;
        for (const sec of this.sections) if (sec.root) this.watch(sec, cx);
      } finally { if (this.context === context) this.loading = false; cx.notify(); }
    });
  }

  toggle(sec, path, cx) {
    if (sec.folders.has(path)) {
      for (const folder of [...sec.folders]) if (folder === path || folder.startsWith(path + "/")) {
        sec.folders.delete(folder);
        sec.entries.delete(folder);
      }
    } else {
      sec.folders.add(path);
      if (!sec.entries.has(path) && !sec.pending.has(path)) {
        const context = this.context;
        sec.pending.add(path);
        cx.spawn(async cx => {
          try { await this.loadFolder(sec, path, context); }
          catch (e) { if (this.current(context)) sec.error = String(e); }
          finally { if (this.context === context) sec.pending.delete(path); cx.notify(); }
        });
      }
    }
    cx.notify();
  }

  show(sec, path, cx) {
    this.code?.release(); this.code = null; this.file = path ? { sec, path } : null; this.fileError = null;
    if (!path || !cx) return;
    // Still this request, for the same folder: a focus change that keeps the section's folder keeps its preview.
    const file = this.file, root = sec.root, on = sec.on;
    const shown = () => this.file === file && sec.root === root && sec.on === on;
    cx.spawn(async cx => {
      try {
        const text = await readTextFile(`${root}/${path}`, { on });
        if (!shown()) return;
        if (text === null) { this.fileError = "This file is no longer available"; return; }
        if (text.includes("\0")) { this.fileError = "Binary file · no text preview"; return; }
        const t = theme(), ext = path.includes(".") ? path.split(".").pop() : "txt";
        this.code = EditorState.new({ language: LANG[ext] ?? ext, readonly: true,
          value: text.length > 400000 ? text.slice(0, 400000) + "\n… (file truncated)" : text,
          font_family: settings().font_family, font_size: 12,
          syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, function: t.ansi4, type: t.ansi3, number: t.ansi1, constant: t.ansi6 } });
      } catch { if (shown()) this.fileError = "Cannot preview this file (binary, too large, or unreadable)"; }
      finally { cx.notify(); }
    });
  }

  rows(sec, prefix, depth, out, t) {
    if (out.length >= TOTAL || depth > 40) return out;
    for (const entry of sec.entries.get(prefix) ?? []) {
      if (out.length >= TOTAL) break;
      const path = prefix ? `${prefix}/${entry.name}` : entry.name, open = sec.folders.has(path), mark = sec.marks[`${sec.root}/${path}`];
      out.push(h_flex().id(`${sec.id}-${path}`).h(28).flex_none().pl(8 + depth * 18).pr(8).gap(7).items_center().rounded(7).cursor_pointer().hover(s => s.bg(t.hover))
        .on_click((_e, cx) => entry.dir ? this.toggle(sec, path, cx) : this.show(sec, path, cx))
        .child(entry.dir ? svg(`mods/session-folder/chevron-${open ? "down" : "right"}.svg`).size(12).flex_none().text_color(t.dim) : div().w(12).flex_none())
        .child(svg(`mods/session-folder/${entry.dir ? "folder" : "file"}.svg`).size(14).flex_none().text_color(t.muted))
        .child(div().flex_1().min_w(0).truncate().child(entry.name))
        .when(Boolean(mark), el => el.child(div().text_size(11).text_color(mark === "A" ? t.ansi2 : mark === "D" || mark === "U" ? t.ansi1 : t.blocked).child(mark))));
      if (entry.dir && open) this.rows(sec, path, depth + 1, out, t);
    }
    return out;
  }

  // A collapsible header per section: chevron, label and a dim suffix (the session's name, else its day and
  // id; the project's folder name), then its tree, or one dim line saying why there is none.
  section(sec, t) {
    const suffix = sec === this.session ? sec.name || sessionFallback(sec.root) : sec.root.split(/[\\/]/).pop();
    const note = (text, size = 12) => div().pl(26).pr(8).py(6).text_size(size).text_color(t.dim).child(text);
    const out = [h_flex().id(`section-${sec.id}`).h(28).flex_none().px(8).gap(7).items_center().rounded(7).cursor_pointer().hover(s => s.bg(t.hover))
      .on_click((_e, cx) => { sec.open = !sec.open; cx.notify(); })
      .child(svg(`mods/session-folder/chevron-${sec.open ? "down" : "right"}.svg`).size(12).flex_none().text_color(t.dim))
      .child(div().font_semibold().child(sec.label))
      .child(div().flex_1().min_w(0).truncate().text_size(12).text_color(t.dim).child(`· ${suffix}`))];
    if (!sec.open) return out;
    this.rows(sec, "", 1, out, t);
    if (sec.error) out.push(note(sec === this.session && !sec.entries.has("") ? "Session folder unavailable" : sec.error));
    else if (!sec.entries.get("")?.length) out.push(note(this.loading ? "Loading files…" : "No files"));
    if (sec.limited) out.push(note("File list limited to 500 entries per folder and 5,000 total", 11));
    return out;
  }

  render(cx) {
    if (key() !== this.context?.key) this.refresh(cx);
    const t = theme(), file = this.file, shown = this.sections.filter(s => s.root);
    return v_flex().id("files").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .when(Boolean(file), el => el.child(div().id("files-back").w(20).cursor_pointer().text_color(t.muted).on_click((_e, cx) => { this.show(null); cx.notify(); }).child("←")))
        .child(div().font_semibold().child("Files"))
        .child(div().flex_1().min_w(0).truncate().text_right().text_size(12).text_color(t.dim).child(file ? `${file.sec.label} · ${file.path}` : this.project.root?.split(/[\\/]/).pop() ?? "")))
      .when(!file, el => el.child(v_flex().id("files-tree").flex_1().min_h(0).overflow_y_scrollbar().p(6).children(shown.flatMap(sec => this.section(sec, t)))
        .when(!shown.length, el => el.child(div().p(8).text_size(12).text_color(t.dim).child("No folder")))))
      .when(Boolean(file), el => el.child(this.code ? Editor.new(this.code).flex_1().min_h(0) : div().p(12).text_color(t.dim).child(this.fileError || "Loading file…")));
  }
}
