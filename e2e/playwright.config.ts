import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests',
    // บอก Playwright ให้รอ server พร้อมก่อนรัน tests
    webServer: {
        command: 'echo "API should already be running via docker compose"',
        url: 'http://localhost:3000/api/health',
        timeout: 30 * 1000,
        reuseExistingServer: true,
    },
    reporter: [
        ['list'],
        ['junit', { outputFile: 'reports/e2e-junit.xml' }],
        ['html', { outputFolder: 'playwright-report', open: 'never' }]
    ],
    use: {
        baseURL: process.env.API_BASE_URL || 'http://localhost:3000',
    },
});
