import {fileURLToPath} from 'node:url';
import {after} from 'node:test';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';

/** Share the application server and browser while isolating storage per test. */
export function browserFixture(executablePath, args = ['--no-sandbox']) {
  let startup;

  async function launch() {
    const server = await createServer({
      configFile: false,
      root: fileURLToPath(new URL('..', import.meta.url)),
      server: {host: '127.0.0.1', port: 0},
      logLevel: 'silent',
    });
    try {
      await server.listen();
      const browser = await chromium.launch({headless: true, executablePath, args});
      return {server, browser, baseUrl: server.resolvedUrls.local[0]};
    } catch (error) {
      await server.close().catch(() => {});
      throw error;
    }
  }

  after(async () => {
    const fixture = await startup?.catch(() => null);
    if (!fixture) return;
    try {
      await fixture.browser.close();
    } finally {
      await fixture.server.close();
    }
  });

  return {
    async openPage(test, options) {
      const {browser, baseUrl} = await (startup ??= launch());
      const context = await browser.newContext(options);
      test.after(() => context.close());
      return {page: await context.newPage(), baseUrl};
    },
  };
}
