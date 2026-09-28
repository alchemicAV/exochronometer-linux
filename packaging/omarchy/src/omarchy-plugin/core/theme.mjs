/**
 * The system palette.
 *
 * Omarchy themes ship colors.toml (the app palette) and shell.toml (shell
 * surfaces). The two hosts get it by different routes:
 *
 *   - the standalone app is handed it by its launcher as command-line arguments,
 *     because QML cannot read files in this build (XMLHttpRequest returns an
 *     empty response for file:// URLs - verified);
 *   - the shell panel reads the palette the shell has ALREADY loaded, through
 *     qs.Commons' Color.
 *
 * A JS module, not a QML singleton: a `pragma Singleton` in a directory module
 * aborts the QML engine on this build (SIGABRT, no diagnostic - verified). The
 * cost is that exports are not observable, so the palette must be configured
 * BEFORE the views are built. Both hosts do that by loading AppShell through a
 * Loader they activate after configuring, so ordering is guaranteed rather than
 * hoped for. Nothing re-themes mid-session; a theme change is a relaunch.
 *
 * Every accessor is a function for the same reason: a module-level `let` would
 * be read once, at binding time.
 */
// Tokyo-night-ish defaults, so a host that supplies nothing still looks
// deliberate rather than unstyled.
let current = {
    background: "#0d0d11",
    backgroundDark: "#08080b",
    surface: "#15151c",
    foreground: "#e8e8ee",
    muted: "#7b7f95",
    accent: "#7aa2f7",
    urgent: "#f7768e",
    onAccent: "#0d0d11",
};
export function configure(c) {
    // Written out key by key on purpose: object spread is ES2018 and this QML
    // engine rejects the whole module when it meets it (parse error, no message,
    // and every importer fails with it).
    if (c.background !== undefined && c.background !== null)
        current.background = c.background;
    if (c.backgroundDark !== undefined && c.backgroundDark !== null)
        current.backgroundDark = c.backgroundDark;
    if (c.surface !== undefined && c.surface !== null)
        current.surface = c.surface;
    if (c.foreground !== undefined && c.foreground !== null)
        current.foreground = c.foreground;
    if (c.muted !== undefined && c.muted !== null)
        current.muted = c.muted;
    if (c.accent !== undefined && c.accent !== null)
        current.accent = c.accent;
    if (c.urgent !== undefined && c.urgent !== null)
        current.urgent = c.urgent;
    if (c.onAccent !== undefined && c.onAccent !== null)
        current.onAccent = c.onAccent;
}
function hexToRgb(hex) {
    const h = hex.replace("#", "").trim();
    if (h.length === 8) {
        // #AARRGGBB - QML's own order
        return [parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16), parseInt(h.substr(6, 2), 16)];
    }
    if (h.length === 3) {
        return [parseInt(h[0] + h[0], 16), parseInt(h[1] + h[1], 16), parseInt(h[2] + h[2], 16)];
    }
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}
/** A palette entry at a given alpha, as QML's #AARRGGBB. */
export function tint(hex, alpha) {
    const rgb = hexToRgb(hex);
    const a = Math.max(0, Math.min(1, alpha));
    const pair = (n) => ("0" + n.toString(16)).slice(-2);
    return "#" + pair(Math.round(a * 255)) + pair(rgb[0]) + pair(rgb[1]) + pair(rgb[2]);
}
/** Canvas wants CSS, not #AARRGGBB. */
export function cssOf(hex, alpha) {
    const rgb = hexToRgb(hex);
    return "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + "," + alpha + ")";
}
export function background() { return current.background; }
export function backgroundDark() { return current.backgroundDark; }
export function surface() { return current.surface; }
export function foreground() { return current.foreground; }
export function muted() { return current.muted; }
export function accent() { return current.accent; }
export function urgent() { return current.urgent; }
export function onAccent() { return current.onAccent; }
export function fg(alpha) { return tint(current.foreground, alpha); }
export function bg(alpha) { return tint(current.background, alpha); }
export function fgCss(alpha) { return cssOf(current.foreground, alpha); }
export function accentCss(alpha) { return cssOf(current.accent, alpha); }
/** `--theme-bg #1a1b26 --theme-fg ...`, from the launcher. */
export function configureFromArgs(args) {
    if (!args)
        return;
    const map = {
        "--theme-bg": "background",
        "--theme-bg-dark": "backgroundDark",
        "--theme-surface": "surface",
        "--theme-fg": "foreground",
        "--theme-muted": "muted",
        "--theme-accent": "accent",
        "--theme-urgent": "urgent",
        "--theme-on-accent": "onAccent",
    };
    const incoming = {};
    for (let i = 0; i < args.length - 1; i++) {
        const key = map[args[i]];
        if (key)
            incoming[key] = String(args[i + 1]);
    }
    configure(incoming);
}
