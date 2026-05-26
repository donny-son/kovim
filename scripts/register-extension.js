const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const extPath = process.argv[2];
const publisher = process.argv[3];
const name = process.argv[4];
const version = process.argv[5];

if (!extPath || !publisher || !name || !version) {
  console.error("Missing arguments for register-extension.js");
  process.exit(1);
}

const extDir = path.dirname(extPath);
const manifestPath = path.join(extDir, 'extensions.json');
const extFolder = path.basename(extPath);
const extId = `${publisher}.${name}`;

if (!fs.existsSync(manifestPath)) {
  try {
    fs.mkdirSync(extDir, { recursive: true });
    fs.writeFileSync(manifestPath, JSON.stringify([], null, 2));
  } catch (e) {
    console.error(`Failed to create manifest directory or file: ${e.message}`);
    process.exit(1);
  }
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch (e) {
  manifest = [];
}

const existing = manifest.find(e => e.identifier && e.identifier.id && e.identifier.id.toLowerCase() === extId.toLowerCase());
if (existing) {
  console.log(`  ✓ Extension ${extId} already registered in extensions.json`);
  process.exit(0);
}

const uuid = crypto.randomUUID();
manifest.push({
  identifier: { id: extId, uuid },
  version: version,
  location: { $mid: 1, path: extPath, scheme: 'file' },
  relativeLocation: extFolder,
  metadata: {
    installedTimestamp: Date.now(),
    pinned: false,
    source: 'local',
    id: uuid,
    publisherDisplayName: publisher,
    isApplicationScoped: false,
    isMachineScoped: false,
    isBuiltin: false,
    isPreReleaseVersion: false,
    hasPreReleaseVersion: false,
    private: false,
    targetPlatform: 'undefined'
  }
});

try {
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  console.log(`  ✓ Successfully registered ${extId} in VSCode extensions.json`);
} catch (e) {
  console.error(`Failed to write manifest file: ${e.message}`);
  process.exit(1);
}
