**Exochronometer** is a time-cycle instrument — nested cycles of time drawn as
circles, inscribed geometry, and just-intonation tones taken from the harmonic
series. This is the Qt6/QML port of the iOS original.

Source: https://github.com/alchemicAV/exochronometer-linux (tag `v0.1.0`, MIT)

## Two packages

| package | what it is |
|---|---|
| `exochronometer` | the app — a Qt6/QML window |
| `exochronometer-omarchy` | the shell integration: a bar widget and the full instrument as a panel (`depends: quickshell omarchy`) |

They are split because the plugin's QML imports `Quickshell`, `qs.Ui` and
`qs.Commons`. Shipping it inside the app package would make a plain Qt6 program
depend on the shell — namcap flags exactly that (`E: Dependency quickshell detected
and not included`) — and would pull Quickshell onto machines that only want the
window.

## Why it is more than a first pass

The port keeps the Swift original in the source tree as a **correctness oracle**:
every ported module is validated numerically against reference vectors the Swift
implementation generated, rather than by eye. 14 validators run over the geometry,
node labels, the peak calendar, dissonance, harmonic analysis, chord projection,
frequency formatting, harmonic colour, the WAV renderer, the real-time audio
kernel, and — separately — **what the sound device actually plays**, recording the
sink's monitor and failing on any dropout. That last one exists because a format
bug produced choppy audio while every internal counter reported success.

Packaging got the same treatment: namcap is clean on both packages, the split
exists because namcap objected to the combined one, and the source tarball is
trimmed of makepkg's working directories.

## Verified build

Built with `makepkg` from the `v0.1.0` tag:

```
exochronometer-0.1.0-1-x86_64       namcap clean
exochronometer-omarchy-0.1.0-1-any  namcap clean
```

Both recipes build from source (`npm ci` + `tsc`, then the C++ audio module). The
audio module is a compiled QML plugin built for the target architecture, so
`aarch64` is genuine rather than a prebuilt x86_64 object.

## One design note for review

The shell loads plugins from `~/.config/omarchy/plugins/<id>/`, and omarchy's
validator requires a real directory there (`symlinks are not allowed inside a
plugin folder`), so the install cannot be a symlink into `/usr/share`. The package
ships the plugin tree plus a helper that makes that copy, with a `check` mode to
report drift — because a stale copy is invisible: the shell keeps running the old
plugin while the package is current. That bit us during development. Happy to
change the approach if there is a preferred mechanism for third-party plugins.

## Regarding the build gate

I can see from `.github/VOUCHED.td` that an unvouched author's PR gets the plan
only. No objection from me — flagging it so the review isn't waiting on a build
that will not start until someone vouches or applies `build-approved`. Happy to
make any changes reviewers want.