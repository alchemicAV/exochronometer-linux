// Assemble the Omarchy shell plugin from the same source the app is built from.
//
// One instrument, two hosts: the standalone window (build/app/main.qml) and the
// shell panel (this plugin). To guarantee they cannot drift, the plugin is
// GENERATED - it reuses the app's compiled core and every UI component, and adds
// only the plugin's own host files from src/omarchy-plugin/.
//
// Run after scripts/build-app.mjs.
import { cpSync, mkdirSync, readdirSync, rmSync, copyFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const appDir = join(root, "build", "app");
const pluginSrc = join(root, "src", "omarchy-plugin");
const out = join(root, "build", "omarchy-plugin");

if (!existsSync(appDir)) {
  console.error("build/app is missing - run scripts/build-app.mjs first");
  process.exit(1);
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

// 1. The compiled core: the same .mjs the app loads, so the bar widget's degree
//    is computed by the very code the validators check against the Swift oracle.
cpSync(join(appDir, "core"), join(out, "core"), { recursive: true });

// 2. Every UI component the app built, except its window host - the plugin
//    supplies Panel.qml instead.
let components = 0;
for (const f of readdirSync(appDir)) {
  if (!f.endsWith(".qml")) continue;
  if (f === "main.qml") continue;          // the plugin supplies its own host
  if (f === "smoke.qml") continue;         // smoke-test harness, not a component
  if (f.startsWith("main-p")) continue;    // per-page measurement copies
  copyFileSync(join(appDir, f), join(out, f));
  components++;
}

// 3. the plugin's own files
const pluginFiles = readdirSync(pluginSrc);
for (const f of pluginFiles) copyFileSync(join(pluginSrc, f), join(out, f));

if (!existsSync(join(out, "manifest.json"))) {
  console.error("no manifest.json in src/omarchy-plugin - the plugin would not load");
  process.exit(1);
}
console.log(`omarchy plugin -> build/omarchy-plugin  (core + ${components} UI components + ${pluginFiles.length} plugin files)`);