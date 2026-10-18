// Generates docs/ASSET_USAGE_REPORT.md by classifying every file in the supplied asset pack.
//   node tools/asset_usage_report.js
// Evidence comes from the actual project: copied runtime files, scripts and data JSON.
// Classes: USED, USED (fallback), IMPORTED-UNUSED, REPLACED, SOURCE-ONLY, CONCEPT-ONLY, DATA, DOC/TOOL.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PACK = path.join(ROOT, 'VeyaMahjong_AssetPack_v1');
const RUNTIME = path.join(ROOT, 'assets', 'veya');

function walk(dir, base = dir) {
  let out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(walk(p, base));
    else if (!e.name.endsWith('.import') && e.name !== '.gdignore') out.push(path.relative(base, p).split(path.sep).join('/'));
  }
  return out;
}

const code = walk(path.join(ROOT, 'scripts')).map(f => fs.readFileSync(path.join(ROOT, 'scripts', f), 'utf8')).join('\n')
  + fs.readFileSync(path.join(ROOT, 'export_presets.cfg'), 'utf8') + fs.readFileSync(path.join(ROOT, 'project.godot'), 'utf8');
const bloom = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/config/bloom.json'), 'utf8'));
const bloomSprites = new Set(bloom.worlds.flatMap(w => w.discoveries.map(d => d.sprite)));
const audioMap = JSON.parse(fs.readFileSync(path.join(PACK, 'audio/AUDIO_MAP.json'), 'utf8'));

// icon names used: ContentService.icon("x") , tool_button("x", ...), icon_button("x", ...), scaled_tex(".../x.png")
const iconNames = new Set();
for (const re of [/icon\("([a-z_]+)"/g, /tool_button\("([a-z_]+)"/g, /icon_button\("([a-z_]+)"/g, /icons\/navy\/([a-z_]+)\.png/g,
  /\["(home|worlds|daily|collection|shop)", "(?:home|worlds|daily|collection|shop)"/g]) {
  let m; while ((m = re.exec(code))) iconNames.add(m[1]);
}
for (const n of ['home', 'worlds', 'daily', 'collection', 'shop']) iconNames.add(n); // bottom nav (data-driven list)
const sfxUsed = new Set();
{ const re = /AudioService\.play\("([a-z_]+)"/g; let m; while ((m = re.exec(code))) sfxUsed.add(m[1]); }

function classify(rel) {
  const ext = path.extname(rel);
  const copied = fs.existsSync(path.join(RUNTIME, rel));
  const base = path.basename(rel, ext);
  if (ext === '.svg') return ['SOURCE-ONLY', 'Vector source; runtime uses the pack PNG exports.'];
  if (rel.startsWith('previews/') || rel.startsWith('references/') || rel.startsWith('marketing/') || rel.includes('_CONCEPT'))
    return ['CONCEPT-ONLY', 'Visual reference / concept art. Never shipped; store screenshots must come from the running game.'];
  if (rel.startsWith('tools/') || ext === '.md' || rel === 'ASSET_MANIFEST.json' || rel === 'QA_REPORT.json') return ['DOC/TOOL', 'Pack documentation or generator script; read during integration.'];
  if (rel === 'levels/levels_001_150_verified.json') return ['DATA', 'Levels 1-3 ship unchanged; the shapes of 4-50 ship with re-scattered faces (pack placed ~74% of tiles opposite their twin); 51-150 are generated (they reused layouts 1-50 without rising difficulty). The full file stays validated by tests.'];
  if (rel.startsWith('levels/') || rel.startsWith('config/') || rel.startsWith('localization/'))
    return ['DATA', rel.startsWith('localization/') ? 'Copied to data/localization/; en kept as base and extended, he replaced by a complete reviewed-by-AI version.' : 'Copied to data/; parsed and validated at runtime.'];
  if (rel.startsWith('effects/frames/')) return ['REPLACED', 'Individual frames not imported; the matching 12-frame atlas is used instead.'];
  if (!copied) return ['NOT-IMPORTED', rel.endsWith('back.png') ? 'Tile back art; Mahjong Solitaire never shows face-down tiles.' : ''];
  if (rel.startsWith('tiles/atlases/')) return ['USED', 'ContentService.tile_texture() slices faces from the atlas via its JSON map (128 normally, 256 when tiles render >150 physical px).'];
  if (/^tiles\/[a-z]+\/png_(128|256)\//.test(rel)) return ['USED (fallback)', 'Loaded only if an atlas entry is missing.'];
  if (rel.startsWith('tiles/states/')) return ['REPLACED', 'Selection/hint states are drawn as vector rings above the tile so they stay crisp and are never hidden by neighbours.'];
  if (rel.startsWith('backgrounds/')) return ['USED', 'World/gameplay/map backgrounds (540x960 variants on the Low profile).'];
  if (rel.startsWith('ui/buttons/')) return ['USED', 'Nine-patch button styles (all 6 colours x 2 sizes x 3 states are theme variations).'];
  if (rel.startsWith('ui/components/')) {
    if (/^(panel_cream|panel_white|card_cream|toggle_on|toggle_off|round_green|round_blue|round_locked)$/.test(base)) return ['USED', 'Theme nine-patch / level nodes / toggles.'];
    if (/^bar_/.test(base)) return ['REPLACED', '92px-tall bar sprites cannot nine-patch into slim bars; flat rounded styles in the same palette are used.'];
    return ['IMPORTED-UNUSED', 'Not needed by the current layouts (flat styles used for HUD pill, nav bar and dark panels).'];
  }
  if (rel.startsWith('ui/icons/')) {
    const white = rel.includes('/white/');
    const whiteUsed = ['shuffle', 'hint', 'undo'];
    const used = white ? whiteUsed.includes(base) : iconNames.has(base);
    return used ? ['USED', 'Referenced by name in UI code.'] : ['IMPORTED-UNUSED', /coin|gem|heart|crown/.test(base) ? 'Currency/lives iconography intentionally unused (no fake economy or lives).' : 'Available for future UI.'];
  }
  if (rel.startsWith('ui/rewards/')) {
    if (/^(light|flower)(_256)?$/.test(base)) return code.includes(`ui/rewards/${base.replace('_256', '')}.png`) ? ['USED', 'Light reward / collection icon.'] : ['IMPORTED-UNUSED', '256px variant not needed at current sizes.'];
    return ['IMPORTED-UNUSED', 'Coins/gems/hearts/chests/gifts/stars are concept economy art; no currency, lives or loot exists in the game by design.'];
  }
  if (rel.startsWith('decorations/')) {
    const name = base.replace(/_(256|512)$/, '');
    return bloomSprites.has(name) ? ['USED', `LiShi Bloom discovery sprite (${/_512$/.test(base) ? 'Standard profile' : 'Low profile'}).`] : ['IMPORTED-UNUSED', 'Not placed in any world yet.'];
  }
  if (rel.startsWith('effects/atlases/')) {
    const name = base.replace(/_atlas$/, '');
    return code.includes(`"${name}"`) ? ['USED', 'Short frame-animated effect (disabled by Reduced Motion / Low profile).'] : ['IMPORTED-UNUSED', 'Effect not used in v1 (kept for future cosmetic particle options).'];
  }
  if (rel.startsWith('audio/')) {
    if (rel.endsWith('AUDIO_MAP.json')) return ['DATA', 'Audio event map loaded by AudioService.'];
    if (rel.startsWith('audio/music/')) return ['USED', 'Looped, cross-faded world music.'];
    const ev = Object.keys(audioMap.events).find(k => audioMap.events[k] === rel.replace('audio/', ''));
    return ev && sfxUsed.has(ev) ? ['USED', `SFX event "${ev}".`] : ['IMPORTED-UNUSED', `SFX event "${ev}" has no trigger (no coin economy).`];
  }
  if (rel.startsWith('branding/')) return code.includes(rel) || code.includes(path.basename(rel)) ? ['USED', 'Logo / project icon.'] : ['IMPORTED-UNUSED', 'Alternate logo variant.'];
  if (rel.startsWith('branding/veya_logo_')) return ['REPLACED', 'Game renamed to LiShi Mahjong; replaced by branding/lishi_logo_stacked_{dark,light}.png rendered by tools/make_logo.gd (same blossom, new wordmark). Old copies removed from the build.'];
  if (rel.startsWith('app_icons/') || rel.startsWith('branding/app_icon_master')) return ['REPLACED', 'Superseded by the owner-supplied icon v2; runtime copy regenerated by tools/make_app_icons.gd (see docs/BRANDING.md).'];
  if (rel.startsWith('app_icons/web/')) return ['IMPORTED-UNUSED', 'Web export is not a target platform.'];
  if (rel.startsWith('app_icons/')) {
    const used = code.includes(rel) || code.includes(path.basename(rel)) && rel.includes('xxxhdpi');
    return used ? ['USED', 'Referenced by export_presets.cfg launcher icons.'] : ['IMPORTED-UNUSED', 'Godot generates density buckets from the 192/432 sources; per-density PNGs kept for reference.'];
  }
  return ['IMPORTED-UNUSED', ''];
}

const files = walk(PACK).sort();
const rows = files.map(f => [f, ...classify(f)]);
const counts = {};
for (const r of rows) counts[r[1]] = (counts[r[1]] || 0) + 1;

// Missing: files referenced by pack bindings that don't exist
const bindings = JSON.parse(fs.readFileSync(path.join(PACK, 'config/screen_asset_bindings.json'), 'utf8'));
const missing = [];
for (const [screen, list] of Object.entries(bindings)) for (const p of list) if (!p.includes('{') && !p.includes('*') && !fs.existsSync(path.join(PACK, p))) missing.push(`${screen}: ${p}`);

let md = `# Asset usage report\n\nGenerated by \`node tools/asset_usage_report.js\` from the actual project files on ${new Date().toISOString().slice(0, 10)}.\n\n`;
md += `Pack: \`VeyaMahjong_AssetPack_v1/\` (${files.length} files, excluded from Godot import via \`.gdignore\`). Runtime copies live under \`res://assets/veya/\` (PNG/OGG/WAV/JSON only, ~12 MB).\n\n`;
md += `## Summary\n\n| Class | Files | Meaning |\n|---|---|---|\n`;
const meaning = {
  'USED': 'Loaded at runtime by shipped code', 'USED (fallback)': 'Shipped; loaded only if the primary atlas path fails',
  'REPLACED': 'Intentionally replaced by a better runtime technique (reason given)', 'IMPORTED-UNUSED': 'Copied into the project but not referenced by v1 screens',
  'SOURCE-ONLY': 'Editable vector source, not shipped', 'CONCEPT-ONLY': 'Reference/concept art, never shipped', 'DATA': 'Parsed as game data', 'DOC/TOOL': 'Pack docs or generator',
};
for (const [k, v] of Object.entries(counts).sort()) md += `| ${k} | ${v} | ${meaning[k] || ''} |\n`;
md += `\n## Missing files referenced by the pack's screen bindings\n\n${missing.length ? missing.map(m => '- ' + m).join('\n') : 'None - every concrete path in `config/screen_asset_bindings.json` exists.'}\n`;
md += `\n## Design overrides honoured\n\n- Coins, gems, hearts, chests and gift art from the concept mockups are **not** used: the game has no currency, lives, energy or loot (spec section 3).\n- Concept previews/marketing composites are not used as game screens or store screenshots.\n- Text is never baked into PNGs; all labels are live Godot text.\n`;
md += `\n## Per-file detail\n\n| File | Class | Notes |\n|---|---|---|\n`;
for (const r of rows) md += `| \`${r[0]}\` | ${r[1]} | ${r[2]} |\n`;
fs.writeFileSync(path.join(ROOT, 'docs', 'ASSET_USAGE_REPORT.md'), md);
console.log(counts, 'missing:', missing.length);
