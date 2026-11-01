
import http from 'k6/http';
import { check } from 'k6';

const vus = Number(__ENV.USERS || '500');

if (!Number.isInteger(vus) || vus < 1 || vus > 50000) {
  throw new Error('USERS must be an integer between 1 and 50000');
}

const baseUrl = (__ENV.BASE_URL || 'http://127.0.0.1:51871').replace(/\/$/, '');

export const options = {
  discardResponseBodies: true,
  scenarios: {
    catalog_read: {
      executor: 'per-vu-iterations',
      vus,
      iterations: 1,
      maxDuration: '60s',
      gracefulStop: '5s',
    },
  },
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<=2500'],
    checks: ['rate==1'],
    iterations: [`count>=${vus}`],
  },
};

export default function () {
  const res = http.get(`${baseUrl}/api/products`, {
    timeout: '30s',
    tags: { endpoint: 'catalog_read' },
  });

  check(res, { 'HTTP 200': (r) => r.status === 200 });
}
