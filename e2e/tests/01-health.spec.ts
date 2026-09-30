/**
 * E2E Spec 1: Health Endpoint
 *
 * Tests the API's /health/live and /health/ready endpoints via HTTP.
 * These specs run against a live API started by docker compose in the CI pipeline.
 * Uses Playwright's API request context only — no browser needed.
 *
 * Expected running stack:
 *   docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d
 *   (postgres + redis-cache + redis-queue + api-1 started and healthy)
 */
import { test, expect } from '@playwright/test';

test.describe('1. List / Health', () => {

    test('GET /health/live → 200 and status: up', async ({ request }) => {
        const res = await request.get('/health/live');
        expect(res.status()).toBe(200);
        const body = await res.json();
        // Response envelope: { status: 'success', data: { status: 'up' } }
        expect(body.status).toBe('success');
        expect(body.data.status).toBe('up');
    });

    test('GET /health/ready → 200 with all dependencies up', async ({ request }) => {
        const res = await request.get('/health/ready');
        expect(res.status()).toBe(200);
        const body = await res.json();
        expect(body.data.checks.postgres).toBe('up');
        expect(body.data.checks.redisCache).toBe('up');
        expect(body.data.checks.redisQueue).toBe('up');
    });

    test('echoes X-Correlation-ID header', async ({ request }) => {
        const res = await request.get('/health/live', {
            headers: { 'X-Correlation-ID': 'ci-e2e-test-001' }
        });
        expect(res.headers()['x-correlation-id']).toBe('ci-e2e-test-001');
    });

});
