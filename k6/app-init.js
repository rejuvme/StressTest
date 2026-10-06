import { sleep, check } from 'k6';
import { Trend } from 'k6/metrics';
import {
  buildScenarios,
  commonThresholds,
  jsonGet,
  requireAccessToken,
  verifyOkJson,
} from './config.js';

const initDuration = new Trend('app_init_duration', true);

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    ...commonThresholds(1200),
    app_init_duration: ['p(95)<1200'],
  },
};

export function setup() {
  requireAccessToken();
}

export default function () {
  const res = jsonGet('/app/init');
  initDuration.add(res.timings.duration);

  verifyOkJson(res, 'app/init');
  check(res, {
    'app/init success envelope': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.success === true && body.data;
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
