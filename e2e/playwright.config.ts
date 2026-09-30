import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests',
    // รัน spec ทีละไฟล์ตามลำดับ (01, 02, 03)
    fullyParallel: false,
    // รอ API พร้อมก่อนรัน tests (timeout 60s)
    // baseURL ชี้ไปที่ api-1 ที่ถูก start ด้วย docker compose ก่อนหน้า
    webServer: {
        command: 'echo "Waiting for API at ${API_BASE_URL:-http://localhost:3000}"',
        url: `${process.env.API_BASE_URL ?? 'http://localhost:3000'}/health/live`,
        timeout: 60 * 1000,
        reuseExistingServer: true,
    },
    reporter: [
        ['list'],
        ['junit', { outputFile: 'reports/e2e-junit.xml' }],
        ['html', { outputFolder: 'playwright-report', open: 'never' }]
    ],
    use: {
        // API_BASE_URL จะถูก inject จาก Jenkinsfile environment
        baseURL: process.env.API_BASE_URL ?? 'http://localhost:3000',
        // Timeout ต่อ request (API อาจช้าตอน cold start)
        actionTimeout: 15_000,
    },
});
