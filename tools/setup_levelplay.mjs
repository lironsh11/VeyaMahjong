import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const envPath = path.join(os.homedir(), '.cursor', 'secrets', 'monetization.env');
const { loadMonetizationEnv } = await import(
  pathToFileURL(path.join(os.homedir(), '.cursor', 'mcp-servers', 'monetization', 'src', 'loadEnv.js')).href
);
const { getLevelPlayToken } = await import(
  pathToFileURL(path.join(os.homedir(), '.cursor', 'mcp-servers', 'monetization', 'src', 'levelplay.js')).href
);
loadMonetizationEnv();

const META_APP_ID = '2738184516598537';
const PLACEMENTS = {
  Android: '2738184516598537_2738184553265200',
  iOS: '2738184516598537_2738184556598533',
};

async function lp(method, url, body) {
  const token = await getLevelPlayToken();
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
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
  if (Array.isArray(body?.apps)) return body.apps;
  if (Array.isArray(body?.applications)) return body.applications;
  if (Array.isArray(body?.adUnits)) return body.adUnits;
  if (Array.isArray(body?.instances)) return body.instances;
  if (Array.isArray(body?.groups)) return body.groups;
  return [];
}

function upsertEnv(updates) {
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

async function ensureApp(platform) {
  const apps = asArray(await lp('GET', 'https://platform.ironsrc.com/partners/publisher/applications/v6'));
  const existing = apps.find((a) => a.appName === 'Veya Mahjong' && a.platform === platform);
  if (existing) return existing.appKey;
  const created = await lp('POST', 'https://platform.ironsrc.com/partners/publisher/applications/v6', {
    appName: 'Veya Mahjong',
    platform,
    coppa: 0,
  });
  const appKey = created.appKey || created?.app?.appKey || asArray(created)[0]?.appKey;
  if (!appKey) throw new Error(`create ${platform} returned no appKey: ${JSON.stringify(created).slice(0, 400)}`);
  return appKey;
}

async function bannerUnit(appKey) {
  const units = asArray(await lp('GET', `https://platform.ironsrc.com/levelPlay/adUnits/v1/${appKey}/`));
  const banner = units.find((u) => u.adFormat === 'banner' && !u.isPaused);
  if (!banner) throw new Error(`no live banner ad unit for ${appKey}`);
  return banner.mediationAdUnitId;
}

async function loadGroups(appKey) {
  let last = null;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      return asArray(await lp('GET', `https://platform.ironsrc.com/levelPlay/groups/v4/${appKey}/`));
    } catch (error) {
      last = error;
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
  throw last;
}

async function ensureMeta(appKey, platform, bannerAdUnitId) {
  let instances = asArray(
    await lp('GET', `https://platform.ironsrc.com/levelPlay/network/instances/v4/${appKey}/`),
  );
  let meta = instances.find(
    (i) => String(i.networkName).toLowerCase() === 'meta' && i.adFormat === 'banner',
  );
  if (!meta) {
    await lp('POST', `https://platform.ironsrc.com/levelPlay/network/instances/v4/${appKey}/`, [
      {
        instanceName: platform === 'iOS' ? 'Banner-IOS' : 'Banner-Android',
        networkName: 'meta',
        adFormat: 'banner',
        isBidder: true,
        isLive: true,
        appConfig1: META_APP_ID,
        instanceConfig1: PLACEMENTS[platform],
      },
    ]);
    for (let attempt = 0; attempt < 5 && !meta; attempt++) {
      await new Promise((r) => setTimeout(r, 1000));
      instances = asArray(
        await lp('GET', `https://platform.ironsrc.com/levelPlay/network/instances/v4/${appKey}/`),
      );
      meta = instances.find((i) => String(i.networkName).toLowerCase() === 'meta' && i.adFormat === 'banner');
    }
  }
  if (!meta) throw new Error(`meta instance missing for ${appKey}`);

  const iron = instances.find(
    (i) => String(i.networkName).toLowerCase() === 'ironsource' && i.adFormat === 'banner' && i.isBidder,
  );
  const toActivate = [meta, iron].filter((i) => i && i.isLive === false);
  if (toActivate.length) {
    await lp(
      'PUT',
      `https://platform.ironsrc.com/levelPlay/network/instances/v4/${appKey}/`,
      toActivate.map((i) => ({ instanceId: i.instanceId, isLive: true })),
    );
  }

  let groups = await loadGroups(appKey);
  let bannerGroups = groups.filter((g) => g.adFormat === 'banner');
  const want = [iron?.instanceId, meta.instanceId].filter(Boolean);
  if (bannerGroups.length === 0) {
    await lp('POST', `https://platform.ironsrc.com/levelPlay/groups/v4/${appKey}/`, [
      {
        groupName: 'All Countries',
        adFormat: 'banner',
        mediationAdUnitId: bannerAdUnitId,
        position: 1,
        countries: ['*'],
        instances: want.map((id) => ({ id })),
      },
    ]);
    groups = await loadGroups(appKey);
    bannerGroups = groups.filter((g) => g.adFormat === 'banner');
  }

  for (const group of bannerGroups) {
    const have = new Set((group.instances || []).map((i) => i.id));
    if (want.every((id) => have.has(id))) continue;
    await lp('PUT', `https://platform.ironsrc.com/levelPlay/groups/v4/${appKey}/`, [
      {
        groupId: group.groupId,
        instances: want.map((id) => ({ id })),
      },
    ]);
  }
  return meta.instanceId;
}

const result = {};
for (const platform of ['Android', 'iOS']) {
  const appKey = await ensureApp(platform);
  const bannerAdUnitId = await bannerUnit(appKey);
  const metaInstanceId = await ensureMeta(appKey, platform, bannerAdUnitId);
  result[platform] = { appKey, bannerAdUnitId, metaInstanceId };
}

const configPath = path.join(process.cwd(), 'data', 'config', 'levelplay.json');
const config = {
  _comment: 'LevelPlay app keys and banner ad units. Meta placement IDs live in the LevelPlay dashboard, not in the game.',
  android: { app_key: result.Android.appKey, banner_ad_unit_id: result.Android.bannerAdUnitId },
  ios: { app_key: result.iOS.appKey, banner_ad_unit_id: result.iOS.bannerAdUnitId },
};
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);

upsertEnv({
  VEYA_ANDROID_PACKAGE: 'com.lishimahjong.app',
  VEYA_IOS_BUNDLE: 'com.lishimahjong.app',
  VEYA_ANDROID_LEVELPLAY_APP_KEY: result.Android.appKey,
  VEYA_IOS_LEVELPLAY_APP_KEY: result.iOS.appKey,
  VEYA_ANDROID_BANNER_AD_UNIT_ID: result.Android.bannerAdUnitId,
  VEYA_IOS_BANNER_AD_UNIT_ID: result.iOS.bannerAdUnitId,
  VEYA_META_FAN_APP_ID: META_APP_ID,
  VEYA_META_ANDROID_BANNER: PLACEMENTS.Android,
  VEYA_META_IOS_BANNER: PLACEMENTS.iOS,
});
if (process.env.VEYA_META_FAN_CLIENT_TOKEN) {
  upsertEnv({ VEYA_META_FAN_CLIENT_TOKEN: process.env.VEYA_META_FAN_CLIENT_TOKEN });
}

console.log(JSON.stringify(result, null, 2));
