# Contributing

Thanks for considering a contribution. This is a small, focused tool — the
guidance below is short on purpose.

## Building and testing

```bash
./setup-signing.sh    # once: creates a stable signing identity (see README)
./build.sh            # builds dist/WinKey.app

# Unit tests — no permissions required
swiftc -O tools/logic_test.swift -o tools/logic_test && ./tools/logic_test
swiftc -O tools/menu_state_test.swift -o /tmp/menu_state_test && /tmp/menu_state_test
```

`./build.sh` runs `plutil -lint` on every `.strings` file and fails the build if
one is malformed — see the localization note below.

## Adding a shortcut mapping

Ctrl→Cmd mappings are data, not code. Add one line in
`Sources/WinKey/KeyMap.swift`:

```swift
KeyMapRule(keyCode: 0x08, name: "C", behaviorKey: "beh.copy", defaultEnabled: true),
```

Then add the `"beh.copy"` string to **both** `Resources/*.lproj/Localizable.strings`,
and extend `tools/logic_test.swift` if the new rule has interesting edge cases.

## Localization

`.strings` files do **not** support `#` comments — use `/* */`. A stray `#`
silently invalidates the whole file and every lookup falls back to showing the
raw key in the UI. `build.sh` guards against this, but it is worth knowing why.

To add a language, copy `Resources/en.lproj` to `<lang>.lproj` and translate.

## Things that are easy to get wrong

These all cost real debugging time. Worth reading before touching the
relevant code.

**Accessibility has no color API on `NSSwitch`.** It exposes neither
`contentTintColor` nor `tintColor`, and KVC `setValue(_:forKey: "tintColor")`
throws `NSUnknownKeyException`. The switch in this project is hand-drawn
(`ToggleSwitch.swift`) for that reason. If you want a different color, change
`onColor` there.

**Window minimize does not work via `AXMinimizeButton`.** On macOS 26, reading
that attribute returns `kAXErrorAttributeUnsupported (-25212)`, and a window's
only action is `AXRaise`. Write the `AXMinimized` attribute instead
(`WindowMinimizer.swift`).

**Some windows genuinely cannot be minimized** — modal dialogs, for instance.
A window reporting `AXMinimized = false` after a successful write is usually
this, not a bug in the code. Test with a normal document window.

**Modifier keys report `keyCode == 0x0` in `flagsChanged` events.** Do not match
Alt by key code; check `flags.contains(.maskAlternate)` instead. This is why
`WindowSwitch` tracks state through flags.

**Menus are not visible to the Accessibility API.** A status-bar menu does not
appear in the app's `AXWindows`, so UI-level automation cannot click menu items.
Test menu logic with `tools/menu_state_test.swift` instead.

**Rebuild the menu before displaying it.** `menuNeedsUpdate` fires *after* the
menu is on screen; rebuilding there produces a new `NSMenu` that is not the one
being displayed, so custom views render a stale snapshot. See
`statusItemClicked` in `MenuBarController.swift`.

**Reading text out of an icon is error-prone.** `Resources/README.md` documents
the pitfalls; the short version is to render each segmented glyph and look at
it rather than trusting bounding boxes.

## Pull requests

- Keep the diff focused; unrelated cleanups make review harder
- Run both test suites and `./build.sh` before opening the PR
- If you change behavior, update the "Measured results" table in `README.md`
  with what you actually observed — the table is meant to be evidence, not
  aspiration

## Reporting bugs

Please include:

- macOS version (`sw_vers`)
- What you did, what you expected, what happened
- The relevant lines from `tail -50 /tmp/winkey.log`
- Whether the app is on the exclusion list for the app you tested in
