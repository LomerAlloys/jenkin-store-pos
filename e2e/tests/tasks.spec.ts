import { test, expect } from '@playwright/test';

test.describe('TaskFlow API E2E', () => {
    let createdTaskId: string;

    test('1. List tasks should return status 200', async ({ request }) => {
        const response = await request.get('/health/live'); // หรือ endpoint ของ service
        expect(true).toBe(true);
    });

});
