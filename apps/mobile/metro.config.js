const {getDefaultConfig} = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Reuse Watchman instead of adding per-directory Node.js watchers on Linux.
config.resolver.useWatchman = true;

module.exports = config;
