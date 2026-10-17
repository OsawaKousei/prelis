/** @type {import('next-sitemap').IConfig} */
module.exports = {
  siteUrl: (process.env.NEXT_PUBLIC_BASE_URL || 'https://prelis.prj.kupac.co.jp').replace(/\/$/, ''),
  generateRobotsTxt: true,
  generateIndexSitemap: false,
  autoLastmod: false,
  outDir: 'out',
  trailingSlash: true,
  exclude: ['/icon.png', '/icon.png/'],
};
