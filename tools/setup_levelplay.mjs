// LevelPlay dashboard setup for LiShi Mahjong (Android + iOS):
//   node tools/setup_levelplay.mjs --dry-run           read-only: report what exists / is missing
//   node tools/setup_levelplay.mjs                     attach Meta bidders + groups, write ids
//   node tools/setup_levelplay.mjs --create-ad-units   also try to create missing ad units via API
//
// For every platform it finds the app (by name), then for each ad unit in AD_UNITS:
//   - finds the LevelPlay ad unit by format AND name (create it in the dashboard with exactly that
//     name if missing: Setup > Ad Units > New), or creates it with --create-ad-units;
//   - ensures a Meta Audience Network BIDDER instance with that unit's Meta placement id
//     (matched by placement id, so several instances of one format can coexist), live;
//   - ensures an "All Countries" group for that ad unit with the ironSource bidder + Meta.
// Then writes the ad unit ids to data/config/levelplay.json and the secrets env file.
// Meta placement ids live only in the dashboard; the game never references them.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const DRY_RUN = process.argv.includes('--dry-run');
const CREATE_AD_UNITS = process.argv.includes('--create-ad-units');
const APP_NAME = 'Veya Mahjong';   // dashboard app name (rename here and in the dashboard together)

const envPath = path.join(os.homedir(), '.cursor', 'secrets', 'monetization.env');
const { loadMonetizationEnv } = await import(
  pathToFileURL(path.join(os.homedir(), '.cursor', 'mcp-servers', 'monetization', 'src', 'loadEnv.js')).href
);
const { getLevelPlayToken } = await import(
  pathToFileURL(path.join(os.homedir(), '.cursor', 'mcp-servers', 'monetization', 'src', 'levelplay.js')).href
);
loadMonetizationEnv();

const META_APP_ID = '2738184516598537';
// Ad unit name -> format and Meta placement id per platform (owner-created in Meta, 2026-10-19).
const AD_UNITS = {
  banner: {
    format: 'banner',
    meta: { Android: '2738184516598537_2738184553265200', iOS: '2738184516598537_2738184556598533' },
    instanceName: { Android: 'Banner-Android', iOS: 'Banner-IOS' },
  },
  rewarded_bonus_coins: {
    format: 'rewarded',
    meta: { Android: '2738184516598537_2739140413169614', iOS: '2738184516598537_2739141546502834' },
    instanceName: { Android: 'Meta-RV-BonusCoins-Android', iOS: 'Meta-RV-BonusCoins-iOS' },
  },
  rewarded_bloom_bonus: {
    format: 'rewarded',
    meta: { Android: '2738184516598537_2739140619836260', iOS: '2738184516598537_2739141389836183' },
    instanceName: { Android: 'Meta-RV-BloomBonus-Android', iOS: 'Meta-RV-BloomBonus-iOS' },
  },
  interstitial_level_complete: {
    format: 'interstitial',
    meta: { Android: '2738184516598537_2739140819836240', iOS: '2738184516598537_2739141229836199' },
    instanceName: { Android: 'Meta-IS-LevelComplete-Android', iOS: 'Meta-IS-LevelComplete-iOS' },
  },
};

const API = 'https://platform.ironsrc.com';

async function lp(method, url, body) {
  if (DRY_RUN && method !== 'GET') {
    console.log(`[dry-run] would ${method} ${url} ${body ? JSON.stringify(body) : ''}`);
    return null;
  }
  const token = await getLevelPlayToken();
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body == null ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = text;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text.slice(0, 800) };
  }
  if (!res.ok) {
    const err = new Error(`${method} ${url} -> HTTP ${res.status}`);
    err.detail = json;
    throw err;
  }
  return json;
}

function asArray(body) {
  if (Array.isArray(body)) return body;
  for (const k of ['apps', 'applications', 'adUnits', 'instances', 'groups']) {
    if (Array.isArray(body?.[k])) return body[k];
  }
  return [];
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const unitName = (u) => u.mediationAdUnitName ?? u.adUnitName ?? u.name ?? '';
const isMeta = (i) => String(i.networkName).toLowerCase() === 'meta';

function upsertEnv(updates) {
  if (DRY_RUN) return;
  let text = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
  if (!text.endsWith('\n')) text += '\n';
  for (const [key, value] of Object.entries(updates)) {
    const line = `${key}=${value}`;
    const re = new RegExp(`^${key}=.*$`, 'm');
    if (re.test(text)) text = text.replace(re, line);
    else text += `${line}\n`;
  }
  fs.writeFileSync(envPath, text);
}

async function findApp(platform) {
  const apps = asArray(await lp('GET', `${API}/partners/publisher/applications/v6`));
  const existing = apps.find((a) => a.appName === APP_NAME && a.platform === platform);
  if (existing) return existing.appKey;
  if (DRY_RUN) throw new Error(`no ${platform} app named ${APP_NAME}`);
  const created = await lp('POST', `${API}/partners/publisher/applications/v6`, { appName: APP_NAME, platform, coppa: 0 });
  const appKey = created.appKey || created?.app?.appKey || asArray(created)[0]?.appKey;
  if (!appKey) throw new Error(`create ${platform} returned no appKey: ${JSON.stringify(created).slice(0, 400)}`);
  return appKey;
}

async function adUnits(appKey) {
  return asArray(await lp('GET', `${API}/levelPlay/adUnits/v1/${appKey}/`));
}

function findUnit(units, name, format) {
  const live = units.filter((u) => u.adFormat === format && !u.isPaused);
  // The banner predates the naming scheme: accept the only live banner unit if none is named.
  return live.find((u) => unitName(u) === name) ?? (format === 'banner' && live.length === 1 ? live[0] : null);
}

async function loadGroups(appKey) {
  let last = null;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      return asArray(await lp('GET', `${API}/levelPlay/groups/v4/${appKey}/`));
    } catch (error) {
      last = error;
      await sleep(1500);
    }
  }
  throw last;
}

async function instances(appKey) {
  return asArray(await lp('GET', `${API}/levelPlay/network/instances/v4/${appKey}/`));
}

async function ensureMetaFor(appKey, platform, name, spec, unitId) {
  const placement = spec.meta[platform];
  let all = await instances(appKey);
  let meta = all.find((i) => isMeta(i) && i.adFormat === spec.format && String(i.instanceConfig1) === placement);
  if (!meta) {
    // The API rejects new Meta instances on these apps with ERR-1401 ("App configuration is not
    // consistent") even with the banner instance's appConfig1. Keep going with the ironSource bidder
    // alone; add the Meta instance in the dashboard and rerun to attach it to the group.
    let created = false;
    try {
      await lp('POST', `${API}/levelPlay/network/instances/v4/${appKey}/`, [{
        instanceName: spec.instanceName[platform],
        networkName: 'meta',
        adFormat: spec.format,
        isBidder: true,
        isLive: true,
        appConfig1: META_APP_ID,
        instanceConfig1: placement,
      }]);
      created = !DRY_RUN;
    } catch (error) {
      metaFailures.push(`${platform}: ${spec.instanceName[platform]} (${placement}) - ${error.detail?.errorsArray?.[0]?.errorMessage ?? error.message}`);
    }
    for (let attempt = 0; attempt < 5 && created && !meta; attempt++) {
      await sleep(1000);
      all = await instances(appKey);
      meta = all.find((i) => isMeta(i) && i.adFormat === spec.format && String(i.instanceConfig1) === placement);
    }
    if (created && !meta) throw new Error(`Meta instance for ${name} (${platform}) did not appear`);
  }
  const iron = all.find((i) => String(i.networkName).toLowerCase() === 'ironsource' && i.adFormat === spec.format && i.isBidder);
  const toActivate = [meta, iron].filter((i) => i && i.isLive === false);
  if (toActivate.length) {
    await lp('PUT', `${API}/levelPlay/network/instances/v4/${appKey}/`, toActivate.map((i) => ({ instanceId: i.instanceId, isLive: true })));
  }
  const want = [iron?.instanceId, meta?.instanceId].filter(Boolean);
  if (DRY_RUN || !want.length) return meta?.instanceId ?? null;
  let groups = (await loadGroups(appKey)).filter((g) => String(g.mediationAdUnitId) === String(unitId));
  if (groups.length === 0) {
    await lp('POST', `${API}/levelPlay/groups/v4/${appKey}/`, [{
      groupName: 'All Countries', adFormat: spec.format, mediationAdUnitId: unitId,
      position: 1, countries: ['*'], instances: want.map((id) => ({ id })),
    }]);
    return meta?.instanceId ?? null;
  }
  for (const group of groups) {
    const have = new Set((group.instances || []).map((i) => i.id));
    if (want.every((id) => have.has(id))) continue;
    const merged = [...new Set([...have, ...want])];
    await lp('PUT', `${API}/levelPlay/groups/v4/${appKey}/`, [{ groupId: group.groupId, instances: merged.map((id) => ({ id })) }]);
  }
  return meta?.instanceId ?? null;
}

const result = {};
const missing = [];
const metaFailures = [];
for (const platform of ['Android', 'iOS']) {
  const appKey = await findApp(platform);
  let units = await adUnits(appKey);
  result[platform] = { appKey, units: {}, meta: {} };
  for (const [name, spec] of Object.entries(AD_UNITS)) {
    let unit = findUnit(units, name, spec.format);
    if (!unit && CREATE_AD_UNITS) {
      // Capping/pacing stay off in the dashboard: the game owns caps and pacing (economy.json,
      // feature_flags.json). The reward name/amount is required by the API but unused by the game.
      const unitBody = { mediationAdUnitName: name, adFormat: spec.format };
      if (spec.format === 'rewarded') unitBody.reward = { rewardItemName: name === 'rewarded_bloom_bonus' ? 'Light' : 'Coins', rewardAmount: 1 };
      if (spec.format !== 'banner') unitBody.settings = [{ testGroup: null, cappingEnabled: false, pacingEnabled: false }];
      await lp('POST', `${API}/levelPlay/adUnits/v1/${appKey}/`, [unitBody]);
      if (!DRY_RUN) {
        await sleep(1500);
        units = await adUnits(appKey);
        unit = findUnit(units, name, spec.format);
      }
    }
    if (!unit) {
      missing.push(`${platform}: ${spec.format} ad unit named "${name}"`);
      continue;
    }
    result[platform].units[name] = unit.mediationAdUnitId;
    result[platform].meta[name] = await ensureMetaFor(appKey, platform, name, spec, unit.mediationAdUnitId);
  }
}

if (metaFailures.length) {
  console.log('\nMeta instances the API refused (add them in the dashboard under SDK Networks > Meta, then rerun):');
  for (const m of metaFailures) console.log('  - ' + m);
}
if (missing.length) {
  console.log('\nCreate these ad units in the LevelPlay dashboard (Setup > Ad Units > New), then rerun:');
  for (const m of missing) console.log('  - ' + m);
}

const configPath = path.join(process.cwd(), 'data', 'config', 'levelplay.json');
const old = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
const section = (p, key) => {
  const u = result[p].units;
  return {
    ...(old[key] || {}),
    app_key: result[p].appKey,
    banner_ad_unit_id: u.banner ?? old[key]?.banner_ad_unit_id ?? '',
    rewarded_ad_units: {
      rewarded_bonus_coins: u.rewarded_bonus_coins ?? old[key]?.rewarded_ad_units?.rewarded_bonus_coins ?? '',
      rewarded_bloom_bonus: u.rewarded_bloom_bonus ?? old[key]?.rewarded_ad_units?.rewarded_bloom_bonus ?? '',
    },
    interstitial_ad_units: {
      interstitial_level_complete: u.interstitial_level_complete ?? old[key]?.interstitial_ad_units?.interstitial_level_complete ?? '',
    },
  };
};
const config = {
  _comment: 'LevelPlay app keys and ad unit ids per platform (written by tools/setup_levelplay.mjs). Ad unit NAMES match data/config/economy.json. Meta placement IDs live in the LevelPlay dashboard, not in the game.',
  android: section('Android', 'android'),
  ios: section('iOS', 'ios'),
};
if (DRY_RUN) {
  console.log('\n[dry-run] levelplay.json would become:\n' + JSON.stringify(config, null, 2));
} else {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

const env = {
  VEYA_ANDROID_PACKAGE: 'com.lishimahjong.app',
  VEYA_IOS_BUNDLE: 'com.lishimahjong.app',
  VEYA_META_FAN_APP_ID: META_APP_ID,
};
for (const p of ['Android', 'iOS']) {
  const P = p.toUpperCase();
  env[`VEYA_${P}_LEVELPLAY_APP_KEY`] = result[p].appKey;
  for (const [name, id] of Object.entries(result[p].units)) {
    env[`VEYA_${P}_${name.toUpperCase()}_AD_UNIT_ID`] = id;
    env[`VEYA_META_${P}_${name.toUpperCase()}`] = AD_UNITS[name].meta[p];
  }
}
upsertEnv(env);
if (process.env.VEYA_META_FAN_CLIENT_TOKEN) upsertEnv({ VEYA_META_FAN_CLIENT_TOKEN: process.env.VEYA_META_FAN_CLIENT_TOKEN });

console.log(JSON.stringify(result, null, 2));
