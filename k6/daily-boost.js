import { sleep, check } from 'k6';
import { Trend } from 'k6/metrics';
import {
  buildScenarios,
  commonThresholds,
  jsonGet,
  requireAccessToken,
  verifyOkJson,
} from './config.js';

const dailyBoostDuration = new Trend('daily_boost_duration', true);

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    ...commonThresholds(700),
    daily_boost_duration: ['p(95)<700'],
  },
};

export function setup() {
  requireAccessToken();
}

export default function () {
  const res = jsonGet('/daily-boost/me');
  dailyBoostDuration.add(res.timings.duration);

  verifyOkJson(res, 'daily-boost/me');
  check(res, {
    'daily-boost/me success envelope': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.success === true;
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
