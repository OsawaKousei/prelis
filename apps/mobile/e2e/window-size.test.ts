/// <reference types="node" />

import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {after, before, test} from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {resolve} from 'node:path';
import {mkdirSync, writeFileSync} from 'node:fs';

// Run on a dedicated emulator; this test changes its display configuration.
const serial = process.env.ANDROID_SERIAL ?? '';
assert(serial.startsWith('emulator-'), 'Set ANDROID_SERIAL to a dedicated Android emulator.');
const packageName = 'jp.co.kupacllc.prelis';
const adb = (...args: string[]) => execFileSync('adb', ['-s', serial, ...args], {encoding: 'utf8', timeout: 30_000});
type Node = {attributes: Record<string, string>; bounds: [number, number, number, number]};
let originalSize = '';
let originalDensity = '';
let originalFontScale = '';

function nodes(): Node[] {
  adb('shell', 'uiautomator', 'dump', '/data/local/tmp/prelis-window.xml');
  const xml = adb('shell', 'cat', '/data/local/tmp/prelis-window.xml');
  return [...xml.matchAll(/<node\s+([^>]+)>/g)].map(match => {
    const attributes = Object.fromEntries([...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map(item => [item[1], item[2]]));
    const bounds = attributes.bounds.match(/\d+/g)?.map(Number) as Node['bounds'];
    return {attributes, bounds};
  });
}

async function waitFor(find: (tree: Node[]) => Node | undefined): Promise<Node> {
  for (let attempt = 0; attempt < 15; attempt++) {
    const result = find(nodes());
    if (result) return result;
    await delay(500);
  }
  throw new Error('Expected control was not visible in the native accessibility tree.');
}

const byId = (id: string) => (tree: Node[]) => tree.find(node => node.attributes['resource-id'] === id);
const byLabel = (label: string) => (tree: Node[]) => tree.find(node => node.attributes['content-desc'] === label);
function tap(node: Node) {
  const [left, top, right, bottom] = node.bounds;
  adb('shell', 'input', 'tap', String((left + right) / 2), String((top + bottom) / 2));
}

async function openPage(id: string, tab: string) {
  tap(await waitFor(byId(`tab-${tab}`)));
  await waitFor(byId(`page-${id}`));
  await delay(300);
}

function heading(id: string, tree: Node[]) {
  const titles: Record<string, string> = {home: 'アプリを選択', diary: 'Diary', timer: 'Timer', password: 'パスワード生成'};
  const page = byId(`page-${id}`)(tree)!;
  return tree.find(node => node.attributes.text === titles[id] && node.bounds[1] >= page.bounds[1] && node.bounds[3] <= page.bounds[3]);
}

async function swipePage(id: string, direction: 'up' | 'down') {
  const page = byId(`page-${id}`)(nodes());
  assert(page);
  const [, top, right, bottom] = page.bounds;
  const start = direction === 'up' ? bottom - 24 : top + 24;
  const end = direction === 'up' ? top + 24 : bottom - 24;
  // Use the page margin so gestures cannot be consumed by an internal editor.
  adb('shell', 'input', 'swipe', String(right - 4), String(start), String(right - 4), String(end), '350');
  await delay(200);
}

async function assertFits(id: string, labels: string[]) {
  const tree = nodes();
  assert.deepEqual(tree[0].bounds, [0, 0, 720, 1280], 'Expected a 360×640 window at 2× density');
  const page = byId(`page-${id}`)(tree);
  assert(page, `Missing page-${id}`);
  const firstHeading = heading(id, tree);
  assert(firstHeading, `${id}: page heading is outside the visible page`);
  if (process.env.PRELIS_WINDOW_ARTIFACTS) {
    mkdirSync(process.env.PRELIS_WINDOW_ARTIFACTS, {recursive: true});
    writeFileSync(resolve(process.env.PRELIS_WINDOW_ARTIFACTS, `${id}.png`), execFileSync('adb', ['-s', serial, 'exec-out', 'screencap', '-p']));
  }
  for (const label of labels) {
    assert(tree.some(node => node.attributes['content-desc'] === label &&
      node.bounds[0] >= page.bounds[0] && node.bounds[1] >= page.bounds[1] &&
      node.bounds[2] <= page.bounds[2] && node.bounds[3] <= page.bounds[3] &&
      node.bounds[2] > node.bounds[0] && node.bounds[3] > node.bounds[1]), `${id}: ${label} is outside the visible page`);
  }
  // Android marks RN ScrollView as accessible/scrollable even with no scroll range.
  // Verify the actual result of a gesture, rather than that accessibility flag.
  await swipePage(id, 'up');
  assert.deepEqual(heading(id, nodes())?.bounds, firstHeading.bounds, `${id}: initial page scrolls at 360×640`);
}

before(async () => {
  const response = await fetch('http://127.0.0.1:8081/_expo/open?platform=android&runtime=expo', {signal: AbortSignal.timeout(5000)});
  assert(response.ok, 'Metro must be running on port 8081.');
  const launch = await response.json() as {url: string | null};
  const launchUrl = launch.url ?? '';
  assert(launchUrl.startsWith('exp://'), 'Metro did not return an Android launch URL.');
  const metroUrl = launchUrl.replace('exp://', 'http://');
  originalSize = adb('shell', 'wm', 'size').match(/Override size: (\S+)/)?.[1] ?? 'reset';
  originalDensity = adb('shell', 'wm', 'density').match(/Override density: (\d+)/)?.[1] ?? 'reset';
  originalFontScale = adb('shell', 'settings', 'get', 'system', 'font_scale').trim();
  adb('shell', 'wm', 'size', '720x1280');
  adb('shell', 'wm', 'density', '320');
  adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0');
  adb('install', '-r', '-g', resolve(process.env.PRELIS_ANDROID_APK ?? 'apps/mobile/android/app/build/outputs/apk/debug/app-debug.apk'));
  adb('reverse', 'tcp:8081', 'tcp:8081');
  adb('shell', 'am', 'force-stop', packageName);
  adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW', '-d', `prelis://?__expo_url=${encodeURIComponent(metroUrl)}`, packageName);
  await waitFor(byId('page-home'));
  const notice = nodes().find(node => node.attributes['content-desc']?.includes('Open debugger to view warnings.'));
  if (notice) {
    adb('shell', 'input', 'tap', String(notice.bounds[2] - 28), String((notice.bounds[1] + notice.bounds[3]) / 2));
  }
});

after(() => {
  adb('shell', 'am', 'force-stop', packageName);
  if (originalSize) adb('shell', 'wm', 'size', originalSize);
  if (originalDensity) adb('shell', 'wm', 'density', originalDensity);
  if (originalFontScale === 'null') adb('shell', 'settings', 'delete', 'system', 'font_scale');
  else if (originalFontScale) adb('shell', 'settings', 'put', 'system', 'font_scale', originalFontScale);
});

test('all four initial pages fit the native 360×640 window', async () => {
  await assertFits('home', ['Diary', 'Timer', 'Password']);
  await openPage('diary', 'diary');
  await waitFor(byLabel('日記の本文'));
  await assertFits('diary', ['今日へ', '前日', '翌日', 'カレンダーを開く', '日記の本文', '保存']);
  await openPage('timer', 'timer');
  await assertFits('timer', ['時間（分）', '開始', 'リセット', '音声設定を開く']);
  const timerTree = nodes();
  const ring = byId('timer-ring')(timerTree);
  const page = byId('page-timer')(timerTree)!;
  assert(ring, 'Missing circular timer');
  assert.equal(ring.bounds[2] - ring.bounds[0], ring.bounds[3] - ring.bounds[1], 'Timer ring must remain circular');
  assert(ring.bounds[1] >= page.bounds[1] && ring.bounds[3] <= page.bounds[3], 'Timer ring must fit the initial viewport');
  await openPage('password', 'password');
  await assertFits('password', ['設定を開く', 'パスワードを生成', '生成したパスワード', 'コピー']);
});

test('expanded settings allow page scrolling and collapse back into the window', async () => {
  for (const [page, tab, label] of [['password', 'password', '設定'], ['timer', 'timer', '音声設定'], ['diary', 'diary', 'カレンダー']]) {
    await openPage(page, tab);
    tap(await waitFor(byLabel(`${label}を開く`)));
    await waitFor(byLabel(`${label}を閉じる`));
    const initial = heading(page, nodes());
    await swipePage(page, 'up');
    assert.notDeepEqual(heading(page, nodes())?.bounds, initial?.bounds, `${page}: expanded content must remain reachable by scrolling`);
    for (let i = 0; i < 3; i++) await swipePage(page, 'down');
    tap(await waitFor(byLabel(`${label}を閉じる`)));
    await waitFor(byLabel(`${label}を開く`));
    await assertFits(page, [`${label}を開く`]);
  }
});

test('a long diary scrolls inside its editor while save stays visible', async () => {
  await openPage('diary', 'diary');
  tap(await waitFor(byLabel('日記の本文')));
  adb('shell', 'input', 'text', 'diary%stest%s'.repeat(100));
  adb('shell', 'input', 'keyevent', 'BACK');
  await delay(500);
  assert((byLabel('日記の本文')(nodes())?.attributes.text.length ?? 0) > 500, 'Expected a long draft in the editor');
  await assertFits('diary', ['日記の本文', '保存']);
});
