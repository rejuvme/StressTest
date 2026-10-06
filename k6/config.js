import http from 'k6/http';
import { check } from 'k6';

export const BASE_URL = (__ENV.BASE_URL || 'https://api.rejuvme.health/api').replace(/\/$/, '');
export const ACCESS_TOKEN = __ENV.ACCESS_TOKEN || '';
export const TEST_PROFILE = (__ENV.TEST_PROFILE || 'baseline').toLowerCase();
export const SEARCH_QUERY = __ENV.SEARCH_QUERY || 'breath';
export const SEARCH_SIZE = __ENV.SEARCH_SIZE || '20';

export function requireAccessToken() {
  if (!ACCESS_TOKEN) {
    throw new Error('Missing ACCESS_TOKEN. Set a valid bearer token before running k6.');
  }
}

export function authHeaders(extra = {}) {
  return {
    Authorization: `Bearer ${ACCESS_TOKEN}`,
    'Content-Type': 'application/json',
    ...extra,
  };
}

export function buildScenarios(profile = TEST_PROFILE) {
  switch (profile) {
    case 'load':
      return {
        main: {
          executor: 'ramping-vus',
          startVUs: 0,
          stages: [
            { duration: '2m', target: 20 },
            { duration: '5m', target: 50 },
            { duration: '10m', target: 100 },
            { duration: '10m', target: 150 },
          ],
          gracefulRampDown: '30s',
        },
      };
    case 'spike':
      return {
        main: {
          executor: 'ramping-vus',
          startVUs: 0,
          stages: [
            { duration: '2m', target: 10 },
            { duration: '30s', target: 100 },
            { duration: '3m', target: 100 },
            { duration: '30s', target: 200 },
            { duration: '3m', target: 200 },
            { duration: '2m', target: 20 },
          ],
          gracefulRampDown: '30s',
        },
      };
    case 'baseline':
    default:
      return {
        main: {
          executor: 'ramping-vus',
          startVUs: 0,
          stages: [
            { duration: '2m', target: 5 },
            { duration: '3m', target: 10 },
            { duration: '3m', target: 20 },
          ],
          gracefulRampDown: '30s',
        },
      };
  }
}

export function commonThresholds(p95Ms) {
  return {
    http_req_failed: ['rate<0.01'],
    http_req_duration: [`p(95)<${p95Ms}`],
  };
}

export function jsonGet(path, params = {}) {
  return http.get(`${BASE_URL}${path}`, {
    ...params,
    headers: authHeaders(params.headers || {}),
  });
}

export function verifyOkJson(res, label) {
  return check(res, {
    [`${label} status is 200`]: (r) => r.status === 200,
    [`${label} body is json`]: (r) => String(r.headers['Content-Type'] || '').includes('application/json'),
  });
}
