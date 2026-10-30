const assert = require('node:assert/strict');
const {once} = require('node:events');
const fs = require('node:fs/promises');
const http = require('node:http');
const path = require('node:path');
const {test} = require('node:test');
const {createConnectMiddleware, mergeConfig} = require('metro');
const {getAssetData} = require('metro/private/Assets');
const config = require('../metro.config');

function get(server, requestPath) {
  return new Promise((resolve, reject) => {
    const request = http.get({host: '127.0.0.1', port: server.address().port, path: requestPath}, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({status: response.statusCode, body: Buffer.concat(chunks)}));
      response.on('error', reject);
    });
    request.on('error', reject);
  });
}

test('Metro serves shared PNGs for raw iOS URLs and normalized URLs', {timeout: 60000}, async () => {
  const metro = await createConnectMiddleware(mergeConfig(config, {
    maxWorkers: 1,
    reporter: {update() {}},
    resolver: {useWatchman: false},
  }), {watch: false, waitForBundler: true});
  const server = http.createServer((request, response) => {
    metro.middleware(request, response, error => {
      response.statusCode = error ? 500 : 404;
      response.end(error ? error.message : 'Not found');
    });
  });
  try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const iconsRoot = path.resolve(__dirname, '../../../packages/icons/assets');
    const icons = (await fs.readdir(iconsRoot)).filter(file => file.endsWith('.png'));
    assert.ok(icons.length > 0);
    for (const platform of ['ios', 'android']) {
      for (const icon of icons) {
        const filename = path.join(iconsRoot, icon);
        const asset = await getAssetData(filename, path.relative(config.projectRoot, filename), [], platform, config.transformer.publicPath);
        const rawPath = `${asset.httpServerLocation}/${icon}?platform=${platform}&hash=${asset.hash}`;
        const normalized = new URL(rawPath, 'http://metro');
        const normalizedPath = normalized.pathname + normalized.search;
        const original = await fs.readFile(filename);
        for (const requestPath of [rawPath, normalizedPath]) {
          const result = await get(server, requestPath);
          assert.equal(result.status, 200, `${platform}: ${requestPath}`);
          assert.deepEqual(result.body, original, `${platform}: ${requestPath}`);
        }
      }
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
    await metro.end();
  }
});

test('bundle, source map, and in-app image requests retain their URLs', () => {
  for (const url of [
    '/index.bundle?platform=ios&dev=true&hot=true',
    'http://localhost:8081/index.bundle?platform=android&dev=true',
    '/index.map?platform=ios&dev=true',
    '/assets/src/example.png?platform=ios',
    '/status',
  ]) {
    assert.equal(config.server.rewriteRequestUrl(url), url);
  }
});

test('shared image rewriting preserves the URL form and query parameters', () => {
  for (const origin of ['', 'http://localhost:8081', '//localhost:8081']) {
    const result = config.server.rewriteRequestUrl(`${origin}/assets/../../packages/icons/assets/home.png?platform=ios&hash=example`);
    const url = new URL(result, 'http://metro');
    assert.equal(url.pathname, '/assets/');
    assert.equal(url.searchParams.get('unstable_path'), '../../packages/icons/assets/home.png');
    assert.equal(url.searchParams.get('platform'), 'ios');
    assert.equal(url.searchParams.get('hash'), 'example');
    assert.ok(result.startsWith(origin + '/assets/'));
  }
});
