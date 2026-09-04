import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const archivePath = process.argv[2];
if (!archivePath) {
  console.error("usage: node patch-app-asar.mjs <app.asar>");
  process.exit(2);
}

const archive = fs.readFileSync(archivePath);
if (archive.length < 16) {
  throw new Error("app.asar is too small");
}

const headerPickleSize = archive.readUInt32LE(4);
const headerJSONSize = archive.readUInt32LE(12);
const headerStart = 16;
const dataStart = 8 + headerPickleSize;
const headerBytes = archive.subarray(headerStart, headerStart + headerJSONSize);
const header = JSON.parse(headerBytes.toString("utf8"));

const buildFiles = header.files?.[".vite"]?.files?.build?.files;
if (!buildFiles) {
  throw new Error("unable to locate .vite/build in app.asar");
}

const mainNames = Object.keys(buildFiles).filter((name) => /^main-.*\.js$/.test(name));
if (mainNames.length !== 1) {
  throw new Error(`expected one main bundle, found ${mainNames.length}`);
}

const mainName = mainNames[0];
const entry = buildFiles[mainName];
const mainStart = dataStart + Number(entry.offset);
const mainEnd = mainStart + Number(entry.size);
const mainBytes = archive.subarray(mainStart, mainEnd);

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

const oldMainHash = sha256(mainBytes);
if (entry.integrity?.hash !== oldMainHash) {
  throw new Error(`main bundle hash mismatch: header=${entry.integrity?.hash} actual=${oldMainHash}`);
}

const dockRefreshSource =
  "if(g){ee();let e=()=>{let e=A();e===`codex-system`&&I(e)};l.nativeTheme.on(`updated`,e)";
const dockRefreshReplacement =
  "if(g){ee();let e=()=>{let e=A();I(e)};setInterval(e,5e3)";
const replacements = [
  {
    source: "if(e===`app-default`&&t!==a.a.Dev)",
    replacement: "if(false)",
  },
  {
    source: "r=(n==null?null:k(n))??j()",
    replacement: 'r="/tmp/codex-quota.png"',
  },
  {
    source: dockRefreshSource,
    replacement: dockRefreshReplacement,
  },
  {
    // The copied app can receive its own unread-count event. If left intact,
    // macOS draws a second red badge over the quota tile.
    source: "l.app.setBadgeCount(t.count)",
    replacement: "l.app.setBadgeCount(0)",
  },
];

for (const { source, replacement: replacementSource } of replacements) {
  const needle = Buffer.from(source);
  const first = mainBytes.indexOf(needle);
  const second = first < 0 ? -1 : mainBytes.indexOf(needle, first + needle.length);
  if (first < 0 || second >= 0) {
    throw new Error(`expected exactly one occurrence of ${source}`);
  }

  if (replacementSource.length > source.length) {
    throw new Error(`replacement is longer than source for ${source}`);
  }
  const replacement = Buffer.from(replacementSource.padEnd(needle.length, " "));
  replacement.copy(archive, mainStart + first);
}

const newMainBytes = archive.subarray(mainStart, mainEnd);
const newMainHash = sha256(newMainBytes);

function replaceAllInRange(buffer, start, end, from, to) {
  const fromBytes = Buffer.from(from);
  const toBytes = Buffer.from(to);
  if (fromBytes.length !== toBytes.length) {
    throw new Error("integrity hash replacement must preserve byte length");
  }

  let count = 0;
  let cursor = start;
  while (cursor < end) {
    const found = buffer.indexOf(fromBytes, cursor);
    if (found < 0 || found + fromBytes.length > end) break;
    toBytes.copy(buffer, found);
    count += 1;
    cursor = found + fromBytes.length;
  }
  return count;
}

const integrityReplacementCount = replaceAllInRange(
  archive,
  headerStart,
  headerStart + headerJSONSize,
  oldMainHash,
  newMainHash,
);
if (integrityReplacementCount !== 2) {
  throw new Error(`expected two main integrity hashes, replaced ${integrityReplacementCount}`);
}

const reparsedHeader = JSON.parse(
  archive.subarray(headerStart, headerStart + headerJSONSize).toString("utf8"),
);
const reparsedEntry = reparsedHeader.files[".vite"].files.build.files[mainName];
if (reparsedEntry.integrity.hash !== newMainHash || reparsedEntry.integrity.blocks?.[0] !== newMainHash) {
  throw new Error("patched ASAR header did not retain the updated main integrity hash");
}

const headerHash = sha256(archive.subarray(headerStart, headerStart + headerJSONSize));
const stat = fs.statSync(archivePath);
const temporaryPath = path.join(
  path.dirname(archivePath),
  `.${path.basename(archivePath)}.native-badge-${process.pid}`,
);
fs.writeFileSync(temporaryPath, archive, { mode: stat.mode });
fs.renameSync(temporaryPath, archivePath);

console.log(JSON.stringify({
  mainName,
  oldMainHash,
  newMainHash,
  headerHash,
  patchedExpressions: replacements.length,
}));
