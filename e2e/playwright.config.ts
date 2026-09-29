import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests',
    reporter: [
        ['list'],
        ['junit', { outputFile: 'reports/e2e-junit.xml' }],
        ['html', { outputFolder: 'playwright-report', open: 'never' }]
    ],
    use: {
        baseURL: process.env.API_BASE_URL || 'http://localhost:3000',
    },
});
