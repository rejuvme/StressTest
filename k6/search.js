import { sleep, check } from 'k6';
import { Trend } from 'k6/metrics';
import {
  SEARCH_QUERY,
  SEARCH_SIZE,
  buildScenarios,
  commonThresholds,
  jsonGet,
  requireAccessToken,
  verifyOkJson,
} from './config.js';

const searchDuration = new Trend('search_duration', true);

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    ...commonThresholds(700),
    search_duration: ['p(95)<700'],
  },
};

export function setup() {
  requireAccessToken();
}

export default function () {
  const query = encodeURIComponent(SEARCH_QUERY);
  const size = encodeURIComponent(String(SEARCH_SIZE));
  const res = jsonGet(`/search?q=${query}&size=${size}`);
  searchDuration.add(res.timings.duration);

  verifyOkJson(res, 'search');
  check(res, {
    'search success envelope': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.success === true && body.data && Array.isArray(body.data.items);
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
