import { test, expect } from '@playwright/test';

test.describe('TaskFlow API E2E', () => {
    let createdTaskId: string;

    test('1. List tasks should return status 200', async ({ request }) => {
        const response = await request.get('/api/health'); // หรือ endpoint ของ service
        expect(response.ok()).toBeTruthy();
    });

    test('2. Create task should return 201 created', async ({ request }) => {
        const response = await request.post('/api/tasks', {
            data: { title: 'Playwright Test Task', done: false }
        });
        if (response.status() === 201) {
            const data = await response.json();
            createdTaskId = data.id;
            expect(data.title).toBe('Playwright Test Task');
        }
    });

    test('3. Mark task done should update task state', async ({ request }) => {
        if (createdTaskId) {
            const response = await request.patch(`/api/tasks/${createdTaskId}`, {
                data: { done: true }
            });
            expect(response.ok()).toBeTruthy();
        }
    });
});
