const path = require('node:path');
const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');

const workspaceRoot = path.resolve(__dirname, '../..');

const config = {
  watchFolders: [workspaceRoot],
  server: {
    rewriteRequestUrl(requestUrl) {
      const url = new URL(requestUrl, 'http://metro');
      const iconPrefix = '/packages/icons/assets/';
      if (!url.pathname.startsWith(iconPrefix)) return requestUrl;

      // Keep external asset paths in the query so URL normalization cannot
      // remove /assets. Both raw /assets/../../... and normalized URLs arrive here.
      const iconPath = `../../${url.pathname.slice(1)}`;
      url.pathname = '/assets/';
      url.searchParams.set('unstable_path', iconPath);
      const requestPath = `${url.pathname}${url.search}${url.hash}`;
      if (requestUrl.startsWith('//')) return `//${url.host}${requestPath}`;
      return requestUrl.startsWith('/') ? requestPath : url.href;
    },
  },
  resolver: {
    // Keep hierarchical lookup for packages with nested dependencies.
    nodeModulesPaths: [path.resolve(workspaceRoot, 'node_modules')],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
