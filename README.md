# WinKey

**Make macOS keyboard shortcuts work the Windows way.**

[![CI](https://github.com/ldjwoods/WinKey/actions/workflows/ci.yml/badge.svg)](https://github.com/ldjwoods/WinKey/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

English · [中文说明见下方](#中文说明)

A tiny native macOS menu-bar app that translates `Ctrl+C` / `Ctrl+V` / `Ctrl+X` /
`Ctrl+A` / `Ctrl+Z` / `Ctrl+S` / `Ctrl+F` into their `Cmd+...` equivalents, so your
muscle memory doesn't have to switch when you move between Windows and macOS.

Pure Swift, no third-party dependencies, no Dock icon.

## Why another one of these?

macOS already lets you swap Ctrl and Cmd in *System Settings › Keyboard › Modifier Keys*.
That swap is **global and unconditional**, which breaks three things:

| Problem with the system swap | What WinKey does instead |
|---|---|
| `Cmd+Tab`, `Cmd+Q`, `Cmd+Space` all move to Ctrl — years of Mac muscle memory gone | Only the keys you choose are remapped; everything else is untouched |
| `Ctrl+C` in a terminal stops sending `SIGINT` — you can't interrupt a process | Terminal and IDE apps are excluded by default, so `Ctrl+C` still interrupts |
| All-or-nothing | Every single mapping can be toggled from the menu |

## Features

**Windows-style shortcuts** — `Ctrl+C` `Ctrl+V` `Ctrl+X` `Ctrl+A` `Ctrl+Z` `Ctrl+S`
`Ctrl+F` enabled by default; 11 more (`Q W E G O T U P B R L`) available in the menu.

**Windows-style navigation** — the differences that actually trip you up:

| Windows | macOS default | WinKey gives you |
|---|---|---|
| `Home` = line start | `Home` = document start | `Home` → `Cmd+←` (line start) |
| `End` = line end | `End` = document end | `End` → `Cmd+→` (line end) |
| `Ctrl+Home` = document start | — | `Ctrl+Home` → `Cmd+↑` |
| `Ctrl+End` = document end | — | `Ctrl+End` → `Cmd+↓` |
| `Ctrl+←/→` = word left/right | — | `Ctrl+←/→` → `Option+←/→` |
| `Alt+Tab` = switch window | `Cmd+Tab` | `Alt+Tab` → `Cmd+Tab` |

**Terminal-aware exclusion list** — 24 apps (Terminal, iTerm2, Warp, VS Code,
VSCodium, JetBrains IDEs, Xcode, Slack, Discord, WeChat, QQ, …) pass keystrokes
through untouched. Configurable per app.

**Optional reverse mapping** — translate `Cmd+<key>` back to `Ctrl+<key>` for
deep Windows users. Off by default.

**Minimize the frontmost app** — a Windows habit macOS lacks:
`Ctrl+M` minimizes the current app's window (the real window-level minimize,
not `Cmd+H` app hiding), or enable *click the menu bar icon* to minimize with a click.
Right-click / `Cmd`-click always opens the menu, so you can't lock yourself out.

**Launch at login**, **localized** (English / Simplified Chinese), **zero dependencies**.

## Install

Requires macOS 13+.

```bash
git clone https://github.com/ldjwoods/WinKey.git
cd WinKey

# Optional but recommended: create a stable signing identity first, so the
# Accessibility grant survives rebuilds. Skip it and you'll re-authorize
# after every build.
./setup-signing.sh

./build.sh
cp -R dist/WinKey.app /Applications/
open /Applications/WinKey.app
```

### Prebuilt download

Grab the latest zip from [Releases](../../releases), then **right-click → Open**
the first launch (the build is ad-hoc signed, not notarized, so Gatekeeper warns
once). Verify the download with the published checksum:

```bash
shasum -a 256 -c WinKey-*.zip.sha256
```

### Build from source

Then grant **one** permission — macOS requires this and it cannot be automated:

1. Open **System Settings › Privacy & Security › Accessibility**
2. Click **+**, choose `/Applications/WinKey.app`
3. Turn the switch on

No restart needed — WinKey polls for permission and takes over within ~2 seconds.

> **You only have to do this once.** The project ships with a stable self-signed
> certificate (`WinKey Local Signing`), so the code signature's designated
> requirement stays valid across rebuilds. With ad-hoc signing the binary hash
> changes on every build, macOS treats each build as a brand-new app, and you'd
> have to re-authorize forever. `build.sh` handles this.

## Verification

This project is tested against the real event stream, not just "it seems to work".

### Unit tests (no permissions needed)

```bash
swiftc -O tools/logic_test.swift -o tools/logic_test && ./tools/logic_test
```

24 assertions covering the matching matrices — including the negative cases that
matter, such as `Cmd+C` and bare `C` must **not** be touched, and `Ctrl+Alt+Tab`
must **not** be stolen from the system.

### Menu state timing test (no permissions needed)

```bash
swiftc -O tools/menu_state_test.swift -o /tmp/menu_state_test && /tmp/menu_state_test
```

Reproduces a bug where the power switch displayed a stale value (off, reopen, still
looked on until you reopened it a second time) and verifies the fix.

### End-to-end event-stream verification (needs Accessibility permission)

```bash
swiftc -O tools/verify.swift -o tools/verify && ./tools/verify 10
# Then press Ctrl+C / Ctrl+V during the 10 seconds.
# Output shows what applications actually receive:
#   ✅ 已改写为 Cmd+C(复制)
```

The observer attaches at `.tailAppendEventTap`, so it sees events **after** all
rewrites — exactly what apps get.

### Measured results

| Test | Action | Result |
|---|---|---|
| Rewrite works | `Ctrl+C` in Finder | ✅ rewrite #1, counter 0→1 |
| All keys | `Ctrl+V/X/A/Z/S/F` | ✅ all rewritten to `Cmd+...` |
| Terminal exempt | `Ctrl+C` in Terminal | ⬜ not rewritten, logged `bypass com.apple.Terminal` |
| Native untouched | real `Cmd+C` | ⬜ not rewritten (counter stays 1) |
| AltGr safe | `Ctrl+Alt+C` | ⬜ not rewritten (counter stays 1) |
| Bare key safe | `C` alone | ⬜ not rewritten (counter stays 1) |
| Home | `Home` | ✅ `0x73` → `0x7b` with `maskCommand` |
| End | `End` | ✅ `0x77` → `0x7c` with `maskCommand` |
| Ctrl+Home | `Ctrl+Home` | ✅ `0x73` → `0x7e` (document start) |
| Ctrl+← | `Ctrl+←` | ✅ `0x7b` → `0x7b` with `maskAlternate` (word left) |
| Alt+Tab | `Alt+Tab` | ✅ tail observer confirms `alt=false cmd=true` |
| Minimize | `Ctrl+M` on TextEdit | ✅ `AXMinimized` false → **true** |
| Power switch | on-state color | ✅ sampled `0,136,255` (system blue) |
| Click to minimize | click menu bar icon | ✅ real mouse event at icon position; window minimized |
| Right-click safe | right-click icon | ✅ opens menu, does **not** minimize |

Logs: `tail -f /tmp/winkey.log`

## Implementation notes

**Why the power switch is hand-drawn.** `NSSwitch` exposes no public way to set its
color — it has neither `contentTintColor` nor `tintColor`, and even KVC
`setValue(_:forKey: "tintColor")` throws `NSUnknownKeyException`. Its fill comes
from the system accent color, and inside a menu-item custom view it may not be
tinted at all, which is why it rendered without the expected green.
`ToggleSwitch.swift` draws the capsule and knob directly, so the on-state is the
system blue (`R=0 G=136 B=255` in light mode, `0,145,255` in dark) — matching the
macOS default accent color.

**Icon pipeline.** `tools/import_icon.py` turns `Resources/artwork.png` into
both the app icon and the menu bar icon. The app icon uses an orange rounded plate
(`PLATE_COLOR=orange|light|dark` to switch) because the artwork is dark line art and
would be invisible against a dark wallpaper if left on a transparent background.
The menu bar icon is a **template image** (pure black + alpha only), so macOS tints
it automatically for light/dark menu bars. `build.sh` copies both into the bundle;
if the menu bar PNG is missing the app falls back to an SF Symbol rather than
showing a blank icon.

**Why minimize uses the Accessibility `AXMinimized` attribute.** The obvious
approach — read the window's `AXMinimizeButton` and `AXPress` it — fails on
macOS 26: the attribute is listed but reading it returns
`kAXErrorAttributeUnsupported (-25212)`, and the window's only action is `AXRaise`.
Writing `AXMinimized` directly works in both directions and is verified.
Note some windows genuinely cannot be minimized (e.g. modal dialogs) — in that
case WinKey reports it rather than pretending to succeed.

## Implementation notes (continued)

**Menu state lag — fixed.** The power switch used to show a stale value: turn it off,
reopen the menu, and it still looked on until you reopened it again.

Cause: `menuNeedsUpdate` fires *after* the menu is already on screen. Rebuilding there
created a brand-new `NSMenu`, but the menu being displayed was the object attached
*before* the rebuild — so the switch always rendered the previous snapshot.

Fix: rebuild synchronously in `statusItemClicked` **before** attaching the menu.
`menuNeedsUpdate` no longer rebuilds; it only syncs the checkmark items in place.
`tools/menu_state_test.swift` reproduces the old lag and verifies the fix.

## Known limitations

1. **Only `keyDown`/`keyUp` flags are rewritten; no synthetic `flagsChanged`.**
   Verified working in native Cocoa apps (Finder, Safari, Notes, Pages).
   Apps that maintain their own modifier state machine — mostly Electron
   (Slack, Discord, VS Code) — could theoretically desync. They're on the
   exclusion list for this reason; add any misbehaving app there.

2. **Verification used synthetic events.** The end-to-end evidence above comes
   from AppleScript/CGEvent-generated keystrokes. Real hardware goes through the
   same `CGEventTap` path, so behavior should be identical, but this has not been
   frame-by-frame verified on physical key presses.

3. **`Ctrl+C` no longer reaches non-excluded apps as an interrupt signal.**
   If an app needs both copy and interrupt, add it to the exclusion list.

4. **Self-signed, not notarized.** Distribution to other machines requires
   right-click → Open to bypass Gatekeeper, or a paid Developer ID ($99/yr)
   plus notarization.

5. **Not distributable via the Mac App Store.** `CGEventTap` needs Accessibility
   permission, and the App Store mandates App Sandbox, which suppresses the
   permission prompt. A platform constraint, not an implementation choice.

## Project layout

```
WinKey/
├── build.sh                      # build + sign + bundle .app
├── setup-signing.sh              # create a stable self-signed identity
├── Resources/
│   ├── artwork.png               # source artwork for the icon
│   ├── WinKey.icns               # app icon (orange plate)
│   ├── MenuBarIcon.png           # menu bar template icon (@1x/@2x)
│   ├── en.lproj/Localizable.strings
│   └── zh-Hans.lproj/Localizable.strings
├── Sources/WinKey/
│   ├── main.swift                # entry point (no storyboard)
│   ├── KeyInterceptor.swift      # CGEventTap interception core
│   ├── KeyMap.swift              # Ctrl→Cmd rule table
│   ├── NavigationMap.swift       # Home/End, Ctrl+arrows
│   ├── WindowSwitch.swift        # Alt+Tab
│   ├── AppFilter.swift           # per-app exclusion list
│   ├── Settings.swift            # UserDefaults persistence
│   ├── MenuBarController.swift   # menu bar UI
│   ├── Permission.swift          # Accessibility permission
│   ├── LoginItem.swift           # launch at login
│   ├── Localization.swift        # L() helper
│   └── Log.swift                 # file logging
└── tools/
    ├── extract_wk_menubar.py     # WK.icns → menu bar template icon
    ├── import_icon.py            # artwork → .icns (alternative pipeline)
    ├── draw_wk_icon.py           # hand-drawn WK (superseded by WK.icns)
    ├── verify.swift              # end-to-end event observation
    ├── logic_test.swift          # rule matrix unit tests (24 assertions)
    └── menu_state_test.swift     # menu rebuild timing regression test
```

## Contributing

Adding a shortcut mapping is a one-line change in `Sources/WinKey/KeyMap.swift`:

```swift
KeyMapRule(keyCode: 0x08, name: "C", behaviorKey: "beh.copy", defaultEnabled: true),
```

Add the matching `"beh.copy"` string to **both** `.lproj` files, then run
`./tools/logic_test` and `./build.sh`.

> `.strings` files do **not** support `#` comments — use `/* */`. A stray `#`
> silently invalidates the whole file and the UI falls back to showing raw keys.
> `build.sh` runs `plutil -lint` to catch this.

## License

MIT — see [LICENSE](LICENSE).

---

# 中文说明

**让 macOS 的 Ctrl 快捷键像 Windows 一样工作。**

原生 Swift 写的菜单栏小工具，把 `Ctrl+C` / `Ctrl+V` / `Ctrl+X` / `Ctrl+A` /
`Ctrl+Z` / `Ctrl+S` / `Ctrl+F` 翻译成对应的 `Cmd+...`，双系统来回切换时不用改肌肉记忆。
无第三方依赖，不占 Dock。

## 为什么不用系统自带的修饰键对调？

`系统设置 › 键盘 › 修饰键` 能把 Ctrl 和 Cmd 直接互换，但它是**全局无条件**的：

| 系统对调的问题 | WinKey 的做法 |
|---|---|
| `Cmd+Tab`、`Cmd+Q`、`Cmd+Space` 全部错位，多年 Mac 习惯废掉 | 只改你选的键，其他原封不动 |
| 终端里 `Ctrl+C` 不再发送 `SIGINT`，没法中断程序 | 终端/IDE 默认排除，`Ctrl+C` 仍能中断 |
| 只能全有或全无 | 每一项都能在菜单里单独开关 |

## 功能

**Windows 风格快捷键**：默认开启 `Ctrl+C/V/X/A/Z/S/F`，另有 11 个可在菜单打开。

**Windows 风格光标与窗口**：

| Windows | macOS 默认 | WinKey 改成 |
|---|---|---|
| `Home` 行首 | `Home` 文稿开头 | `Home` → `Cmd+←` |
| `End` 行尾 | `End` 文稿结尾 | `End` → `Cmd+→` |
| `Ctrl+Home` 文稿开头 | — | `Ctrl+Home` → `Cmd+↑` |
| `Ctrl+End` 文稿结尾 | — | `Ctrl+End` → `Cmd+↓` |
| `Ctrl+←/→` 按词移动 | — | `Ctrl+←/→` → `Option+←/→` |
| `Alt+Tab` 切换窗口 | `Cmd+Tab` | `Alt+Tab` → `Cmd+Tab` |

**终端黑名单**：24 个应用（终端、iTerm2、Warp、VS Code、JetBrains 系、Xcode、
Slack、Discord、微信、QQ 等）默认不介入。可在菜单逐项调整。

**反向映射**（可选）：把 `Cmd+<key>` 翻译回 `Ctrl+<key>`，默认关闭。

**最小化前台应用** —— 补上 macOS 缺失的 Windows 习惯：
`Ctrl+M` 最小化当前应用窗口（是真正的窗口最小化，不是 `Cmd+H` 隐藏应用），
也可以开启「点击菜单栏图标最小化」。右键 / `Cmd`+点击始终打开菜单，不会把自己锁死。

**开机自启**、**中英双语界面**、**零依赖**。

## 安装

需要 macOS 13+。

```bash
git clone https://github.com/ldjwoods/WinKey.git
cd WinKey

# 可选但强烈建议：先创建稳定的签名证书。
# 不做这步的话，每次重新编译都要重新授权一次。
./setup-signing.sh

./build.sh
cp -R dist/WinKey.app /Applications/
open /Applications/WinKey.app
```

### 直接下载

从 [Releases](../../releases) 下载 zip，**首次启动需右键 → 打开**
（构建是 ad-hoc 签名、未公证，Gatekeeper 会警告一次）。用发布的校验和验证：

```bash
shasum -a 256 -c WinKey-*.zip.sha256
```

### 从源码构建

然后授权**一次**（macOS 强制要求，无法自动化）：

1. 打开 `系统设置 › 隐私与安全性 › 辅助功能`
2. 点 `+`，选 `/Applications/WinKey.app`
3. 打开开关

**不需要重启应用** —— 内置轮询会在约 2 秒内自动接管。

> **只需授权一次。** 项目用固定的自签证书（`WinKey Local Signing`）签名，
> 重建后签名标识不变，授权持续有效。若用 ad-hoc 签名，每次编译哈希都变，
> macOS 会视为全新应用，就得反复授权 —— 这个坑已经规避。

## 验证

```bash
# 单元自测（不需要权限）
swiftc -O tools/logic_test.swift -o tools/logic_test && ./tools/logic_test

# 端到端事件流观测（需要辅助功能权限）
swiftc -O tools/verify.swift -o tools/verify && ./tools/verify 10
```

日志：`tail -f /tmp/winkey.log`

实测结论见上方英文部分的表格，全部来自真实事件流观测与计数器交叉验证。

最小化功能的实现说明：不用 `NSRunningApplication.hide()`（那是 `Cmd+H` 隐藏应用），
而是通过 Accessibility 写 `AXMinimized` 属性，这样窗口会真正缩进 Dock。
实测发现 macOS 26 上 `AXMinimizeButton` 属性常常读取失败
（返回 `kAXErrorAttributeUnsupported -25212`，且窗口 action 只有 `AXRaise`），
因此改用直接写属性，已验证双向生效。

## 实现说明

**为什么总开关是自绘的。** `NSSwitch` 没有任何公开接口能改颜色 —— 它既没有
`contentTintColor` 也没有 `tintColor`，实测用 KVC 设 `tintColor` 会直接抛
`NSUnknownKeyException`。它的填充色完全由系统 accent color 决定，而在菜单项的自定义
view 里可能根本不跟随 accent color 渲染，这就是它「开启后颜色不受控」的原因。
`ToggleSwitch.swift` 直接绘制胶囊和滑块，开启时是系统蓝
（浅色下 `R=0 G=136 B=255`，深色下 `0,145,255`），对齐 macOS 默认强调色。

**图标流水线。** `tools/import_icon.py` 把 `Resources/artwork.png` 生成应用图标和
菜单栏图标。应用图标用橙色圆角底板（`PLATE_COLOR=orange|light|dark` 可切换）——
因为图形是深色线稿，透明底在深色壁纸下会看不见。菜单栏图标是**模板图**
（纯黑 + 只用 alpha），系统会按菜单栏明暗自动着色。`build.sh` 会把两者都打进 bundle；
若菜单栏 PNG 缺失，应用会回退成系统符号而不是显示空白。

**两个诚实的说明：**
- 验证用的是**离屏渲染后采样像素**，不是肉眼确认。我能证明颜色数值正确，
  但最终观感需要你自己看一眼。
- 想截图验证菜单里的实际渲染时被系统挡下了（缺「屏幕录制」权限）。
  我没有为此向你申请新权限 —— 那只是为了验证，不值得扩大授权范围。

## 实现说明（续）

**菜单状态滞后 —— 已修复。** 总开关曾显示过期状态：关掉后重开菜单仍显示为开，
需要再开一次才对。

成因：`menuNeedsUpdate` 是在菜单**已经显示之后**才回调的。在那里重建会新建一个
`NSMenu` 对象，但屏幕上显示的是重建**之前**挂上去的那个对象，
于是开关渲染的永远是上一次的快照。

修复：在 `statusItemClicked` 里、挂载菜单**之前**同步重建。
`menuNeedsUpdate` 不再重建，只就地同步勾选项状态。
`tools/menu_state_test.swift` 可复现旧行为并验证修复。

### 菜单状态时序测试（不需要权限）

```bash
swiftc -O tools/menu_state_test.swift -o /tmp/menu_state_test && /tmp/menu_state_test
```

复现「总开关显示滞后一次」的 bug 并验证修复。

## 已知局限

1. 只改写 `keyDown`/`keyUp` 的 flags，不合成 `flagsChanged`。原生 Cocoa 应用实测正常；
   Electron 系（Slack、Discord、VS Code）理论上可能状态不一致，已默认列入黑名单。
2. 端到端验证用的是合成事件（AppleScript/CGEvent）。真实键盘走同一条链路，
   但没有对手按场景做逐帧记录 —— 如实说明，不夸大。
3. 非黑名单应用里 `Ctrl+C` 不再传递中断信号。
4. 仅本机自签，未公证。分发给他人需对方右键打开，或购买开发者账号（$99/年）。
5. **无法上架 Mac App Store** —— `CGEventTap` 需要辅助功能权限，而 App Store
   强制沙盒会抑制该权限弹窗。这是平台限制，不是实现取舍。

## 许可

MIT，见 [LICENSE](LICENSE)。
