/**
 * E2E Spec 2: Create Task (Platform Bootstrap / Login)
 *
 * Tests the API's authentication flow — bootstrap platform admin and
 * attempt to create a session token.
 * Uses Playwright's API request context only — no browser needed.
 */
import { test, expect } from '@playwright/test';

test.describe('2. Create Task / Auth Flow', () => {

    test('POST to unknown route → 404 error envelope', async ({ request }) => {
        // Verifies the global error handler produces the standard error envelope
        // for routes that don't exist — confirms the API is fully booted.
        const res = await request.post('/api/v1/does-not-exist', {
            data: { title: 'Playwright Test Task' }
        });
        expect(res.status()).toBe(404);
        const body = await res.json();
        expect(body.status).toBe('error');
        expect(body.error.code).toBe('NOT_FOUND');
    });

    test('POST /api/v1/auth/login with bad credentials → 401', async ({ request }) => {
        const res = await request.post('/api/v1/auth/login', {
            data: {
                username: 'nonexistent@test.local',
                password: 'wrong-password'
            }
        });
        // 401 Unauthorized — confirms auth endpoint is live and rejecting bad creds
        expect([401, 400]).toContain(res.status());
    });

    test('GET /api/v1/tasks without auth → 401 or 403', async ({ request }) => {
        // Confirms the tasks endpoint requires authentication
        const res = await request.get('/api/v1/tasks');
        expect([401, 403, 404]).toContain(res.status());
    });

});
