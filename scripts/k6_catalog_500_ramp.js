import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    catalog: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 500 },
        { duration: '30s', target: 500 },
        { duration: '10s', target: 0 },
      ],
    },
  },
};

export default function () {
  const response = http.get(
    `${__ENV.BASE_URL}/api/products?limit=10&offset=0`
  );

  check(response, {
    'HTTP 200': (r) => r.status === 200,
    '10 products returned': (r) => {
      try {
        const data = r.json();
        return Array.isArray(data) && data.length === 10;
      } catch (_) {
        return false;
      }
    },
  });
}
