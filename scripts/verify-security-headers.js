#!/usr/bin/env node

const http = require('http');
const https = require('https');

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...value] = arg.replace(/^--/, '').split('=');
    return [key, value.join('=') || ''];
  })
);

const targetUrl = args.url || process.env.HEADER_CHECK_URL;
const profile = args.profile || process.env.HEADER_PROFILE || 'production-public';

if (!targetUrl) {
  console.error('Missing --url or HEADER_CHECK_URL');
  process.exit(2);
}

if (!['production-public', 'staging-private-tls', 'local-lan-tailscale'].includes(profile)) {
  console.error(`Invalid profile: ${profile}`);
  process.exit(2);
}

let parsed;
try {
  parsed = new URL(targetUrl);
} catch (error) {
  console.error(`Invalid URL: ${targetUrl}`);
  process.exit(2);
}

function headerValue(headers, name) {
  const value = headers[name.toLowerCase()];
  return Array.isArray(value) ? value.join(', ') : value || '';
}

function requestHeaders(url) {
  const client = url.protocol === 'https:' ? https : http;

  return new Promise((resolve, reject) => {
    const req = client.request(
      url,
      { method: 'GET', timeout: 15000 },
      (res) => {
        res.resume();
        resolve({ statusCode: res.statusCode, headers: res.headers });
      }
    );
    req.on('timeout', () => req.destroy(new Error('Timed out waiting for response')));
    req.on('error', reject);
    req.end();
  });
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

(async () => {
  const { statusCode, headers } = await requestHeaders(parsed);
  const csp = headerValue(headers, 'content-security-policy');
  const hsts = headerValue(headers, 'strict-transport-security');
  const isHttps = parsed.protocol === 'https:';

  console.log(`Checked ${targetUrl}`);
  console.log(`Profile: ${profile}`);
  console.log(`Status: ${statusCode}`);
  console.log(`Content-Security-Policy: ${csp || '(absent)'}`);
  console.log(`Strict-Transport-Security: ${hsts || '(absent)'}`);

  if (statusCode >= 400) {
    fail(`URL returned HTTP ${statusCode}`);
  }

  if (profile === 'production-public') {
    if (!isHttps) fail('production-public profile must be checked over HTTPS');
    if (!hsts) fail('production-public profile must emit Strict-Transport-Security');
    if (!csp) fail('production-public profile must emit Content-Security-Policy');
    return;
  }

  if (profile === 'staging-private-tls') {
    if (!isHttps) fail('staging-private-tls profile must be checked over HTTPS');
    if (!csp) fail('staging-private-tls profile must emit Content-Security-Policy');
    return;
  }

  if (profile === 'local-lan-tailscale') {
    if (!isHttps && hsts) {
      fail('local-lan-tailscale HTTP origins must not emit Strict-Transport-Security');
    }
    if (!isHttps && /\bupgrade-insecure-requests\b/i.test(csp)) {
      fail('local-lan-tailscale HTTP origins must not emit CSP upgrade-insecure-requests');
    }
  }
})().catch((error) => {
  console.error(`Header check failed: ${error.message}`);
  process.exit(1);
});
