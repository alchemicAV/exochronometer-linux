/**
 * Assemble the QML app directory.
 *
 * QML's JS engine loads ES modules only when the file extension is `.mjs`, but
 * tsc emits `.js`. So this copies the compiled core next to the QML and
 * rewrites the intra-module import specifiers to match.
 *
 * Output layout (what ships in the package):
 *   build/app/main.qml
 *   build/app/core/*.mjs
 */

import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = join(root, "dist", "core");
const outDir = join(root, "build", "app");
const outCore = join(outDir, "core");

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outCore, { recursive: true });

const files = readdirSync(src).filter((f) => f.endsWith(".js"));
for (const f of files) {
  const code = readFileSync(join(src, f), "utf8");
  // "./geometry.js" -> "./geometry.mjs"
  const rewritten = code.replace(/(from\s+")(\.\/[^"]+)\.js(")/g, "$1$2.mjs$3");
  writeFileSync(join(outCore, f.replace(/\.js$/, ".mjs")), rewritten);
}

// Copy every QML file rather than naming them one by one - the page set keeps
// growing and a missed file is a silent runtime failure.
const qmlDir = join(root, "src", "qml");
const qmlFiles = readdirSync(qmlDir).filter((f) => f.endsWith(".qml"));
for (const f of qmlFiles) {
  cpSync(join(qmlDir, f), join(outDir, f));
}

console.log(`assembled ${files.length} modules -> ${outCore}`);
for (const f of readdirSync(outCore)) console.log(`  core/${f}`);
for (const f of qmlFiles) console.log(`  ${f}`);
