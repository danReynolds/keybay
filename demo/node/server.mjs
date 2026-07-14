import { createServer } from 'node:http';

const port = Number.parseInt(process.env.PORT ?? '', 10);
const openAiConfigured = Boolean(process.env.OPENAI_API_KEY);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer from 1 through 65535');
}
if (!openAiConfigured) {
  throw new Error('OPENAI_API_KEY was not injected');
}

const status = { status: 'ok', openai: 'configured' };

if (process.argv.includes('--check')) {
  console.log('Keyway Node demo is configured (value not printed).');
} else {
  const server = createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(`${JSON.stringify(status)}\n`);
  });

  server.listen(port, '127.0.0.1', () => {
    console.log(`Keyway Node demo listening on http://127.0.0.1:${port}`);
    console.log('OPENAI_API_KEY: available (value not printed)');
  });
}
