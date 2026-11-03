# Local tmux fork: `pane-locations-changed` hook

This checkout is Shay's tmux fork (`git@github.com:ShayAgros/tmux.git`, branch
`pane-move-hooks`), upstream tmux master `a73616d781f2` (2026-10-30, reports
`tmux next-3.9`) plus local commits. It is the tmux build used daily on the laptop
(`~/.local/bin/tmux` → `~/workspace/software/tmux-shpool/tmux`). Not sent upstream.

## Why it exists

Panes that run `ssh dev-kermit` attach a shpool session named after the pane's location,
`ssh-<session>.<window>.<pane>`. When a pane moves (swap, rotate, move/link/kill window,
renumbering, split or kill in the middle, rename-session, ...), its shpool session must be
renamed to the new location. Upstream tmux has no single signal for "a pane's location
changed": many of these commands have no after-hook, choose-tree kills and pane exits run
no command at all, and `window-layout-changed` also fires on plain resizes.

## The feature

One new global hook, `pane-locations-changed`, that is stateful:

- It fires once per event-loop pass, and only if an existing pane's
  `session_name.window_index.pane_index` differs from the location recorded at the last
  fire.
- `#{hook_moves}` lists each moved pane as `%id<TAB>old<TAB>new`, all entries tab
  separated, e.g. `%2	t.0.1	t.0.0	%0	t.0.0	t.0.1` for a swap-pane.
- New panes are recorded, not listed. A pane created at the end fires nothing; one created
  in the middle lists only the panes after it. Resizes and layout changes fire nothing.
- A window linked into several sessions takes its location from the first session in name
  order (the `list-panes -a` order).
- Use `#{q:hook_moves}` when passing it to a shell; `q` escapes the tabs and spaces.

## Implementation (commit "Add pane-locations-changed hook")

- `server-fn.c`: `server_locations_changed()` arms a zero-timeout evtimer if not already
  pending. The callback walks sessions → winlinks → panes, builds each pane's location
  (`server_locations_append_moves`), compares it with `wp->location`, updates it, and fires
  the event with a `moves` payload (`hook_moves` in formats) if anything moved.
  `wp->location_generation` makes the first (linked-window) occurrence win.
- `tmux.h`: `char *location` and `u_int location_generation` in `struct window_pane`;
  prototype for `server_locations_changed`. `window_pane_destroy` frees `location`.
- Callers of `server_locations_changed()`: every low-level writer of a location.
  `window.c`: `winlink_add`, `winlink_remove`, `winlink_set_window`, `winlink_shuffle_up`,
  `window_add_pane`, `window_remove_pane`; the direct pane-list edits in
  `cmd-swap-pane.c`, `cmd-rotate-window.c`, `cmd-join-pane.c`; the direct winlink swap in
  `cmd-swap-window.c`; `cmd-rename-session.c`; `options.c` (`pane-base-index`).
  break-pane, kill-window, renumber-windows, kill-session, session groups, choose-tree kill
  and `server_renumber_all` all reach one of these.
- `options-table.c`: the hook entry (`OPTIONS_TABLE_HOOK`, global). `tmux.1`: man entry.
- `regress/pane-locations-changed.sh`: fire counts and exact `hook_moves` for ~30 commands
  (1 for each move, 0 for resize/layout/select/`set -p @x`/base-index, 1 for a pane exit).

If a future upstream change adds a new way to reorder `w->panes`, re-index winlinks or rename
sessions without going through the functions above, it must call
`server_locations_changed()` too. Find candidates with:
`grep -nE 'TAILQ_(INSERT_[A-Z]+|REMOVE)\([^,]*panes|RB_(INSERT|REMOVE)\((winlinks|sessions)|wl[a-z_]*->(window|idx) = ' *.c`

## Who uses it

`~/workspace/dots/dotfiles/tmux/tmux.conf`:
```
set -gq pane-locations-changed[0] "run-shell -b '~/.config/tmux/shpool_refresh.sh --auto #{q:hook_moves}'"
```
(`-q` lets an unpatched tmux ignore the unknown hook.) `tmux/shpool_refresh.sh --auto`
queues the listed pane ids, and one runner refreshes each over the pane's own ssh
ControlMaster (`@shpool_cm`, set by the `.zshrc` `ssh()` wrapper): it reads the session's
current name live on dev-kermit, then renames it, or swaps (`shpool switch`) when the target
name is taken. A burst of hooks gives one `shpool: N panes updated` message.
`<prefix> C-u` still refreshes the current pane by hand.

Design history and test evidence: dev-kermit
`~/workspace/llm_tasks/tmux_auto_detect_pane_moves/` (STATUS.md, artifacts/).

## Build, test, update

```
sh autogen.sh && ./configure --enable-utf8proc && make -j$(nproc)
cd regress && make          # runs each test under env -i, always against ../tmux
(cd regress && sh pane-locations-changed.sh)   # just the hook test
```
To compare with unpatched upstream, build a separate worktree of the base commit; the
regress Makefile ignores `TEST_TMUX`.

Rebasing on newer upstream: `git fetch https://github.com/tmux/tmux master`, rebase
`pane-move-hooks`, rebuild, rerun the hook test and the full suite, re-run the grep above.

Never point the running daily tmux client at a different build while its server is up: a
client and server of different protocol versions refuse to talk. Switching builds means
`tmux kill-server` (closes every pane) and restarting.
