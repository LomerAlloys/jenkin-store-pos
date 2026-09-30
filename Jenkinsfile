pipeline {

    agent {
        docker {
            // node:22 (Debian bookworm) ใช้ glibc ซึ่ง sonar-scanner JRE ต้องการ
            // node:22-alpine ใช้ musl libc → sonar-scanner bundled JRE รันไม่ได้ ("java: not found")
            image 'node:22'
            label 'linux-build'
            // -u root: รันเป็น root เพื่อให้ corepack/pnpm ทำงานได้
            // --network jenkins-net: ให้ container เข้าถึง sonarqube:9000 ผ่าน Docker network ได้
            // -v docker.sock: DooD สำหรับ E2E stage (docker compose up api-1)
            args '-u root --network jenkins-net -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    // กำหนดค่า Environment Variables สำหรับใช้ทั้ง Pipeline
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
        // Jenkins node เคยได้รับ PATH ว่าง ทำให้ Docker Pipeline หา /usr/bin/docker ไม่เจอ
        PATH = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    }

    options {
        // A pipeline stage should never run unbounded because a hung process
        // (such as an interactive prompt, deadlock, or network timeout) would
        // hold the Jenkins executor indefinitely, blocking subsequent jobs and wasting CI resources.
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('Install') {
            steps {
                dir('server') {
                    echo "=== Installing Dependencies for ${env.APP_NAME} (${env.NODE_ENV}) ==="
                    // Project uses pnpm (packageManager: pnpm@10.34.5) with pnpm-lock.yaml
                    // Enable corepack so the pinned pnpm version is used without a separate install step
                    sh 'corepack enable'
                    sh 'pnpm install --frozen-lockfile'
                }
            }
        }

        stage('Lint') {
            steps {
                dir('server') {
                    echo "=== Running Linter for ${env.APP_NAME} ==="
                    sh 'pnpm run lint'
                }
            }
            post {
                always {
                    // archiveArtifacts ต้องอยู่ใน stage-level post เพราะต้องการ FilePath context
                    // pipeline-level post ไม่มี workspace เมื่อใช้ Docker agent
                    archiveArtifacts artifacts: 'server/npm-debug.log*,npm-debug.log*', allowEmptyArchive: true
                }
            }
        }

        stage('Unit Test') {
            steps {
                dir('server') {
                    echo "=== Running Unit Tests for ${env.APP_NAME} ==="
                    sh 'pnpm test'
                }
            }
            post {
                always {
                    // ต้องรันภายใน stage post เพื่อให้ FilePath context (workspace) ยังคงอยู่
                    junit allowEmptyResults: true, testResults: 'server/reports/junit.xml'
                    publishCoverage adapters: [coberturaAdapter('server/coverage/cobertura-coverage.xml')]
                }
            }
        }

        stage('SonarQube Analysis') {

            steps {
                withSonarQubeEnv('SonarQube') {
                    // รัน sonar-scanner ผ่าน npx
                    sh 'npx sonarqube-scanner -Dsonar.projectKey=taskflow-api'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Deploy - Staging') {
            when {
                branch 'develop'
            }
            steps {
                echo '=== Deploying to Staging ==='
                sh 'echo deploying to staging ...'
            }
        }
        
        stage('Deploy - Production') {
            when {
                branch 'main'
            }
            input {
                message 'Deploy to production?'
                ok 'Promote to Production'
            }
            steps {
                echo '=== Deploying to Production ==='
                sh 'echo deploying to production ...'
            }
        }

        stage('E2E Test') {
            agent {
                docker {
                    // Keep the image version aligned with e2e/package-lock.json.
                    image 'mcr.microsoft.com/playwright:v1.63.0-noble'
                    label 'linux-build'
                    reuseNode true
                    // DooD: ใช้ Docker daemon ของ host โดยไม่สร้าง Docker daemon ซ้อนใน container
                    args '-u root --network jenkins-net -v /var/run/docker.sock:/var/run/docker.sock'
                }
            }
            environment {
                API_BASE_URL = 'http://api-1:3000'
            }
            steps {
                // Playwright image มี browser/Node แต่ไม่มี Docker CLI จึงติดตั้งเฉพาะ client
                sh '''
                    apt-get update -qq
                    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2
                    echo "=== Docker & Compose versions ==="
                    docker --version
                    docker compose version
                '''

                // Start the API stack through the mounted host Docker socket.
                dir('server') {
                    sh '''
                        cp -n .env.example .env 2>/dev/null || true
                        docker compose \
                            -f docker-compose.yml \
                            -f docker-compose.ci.yml \
                            up -d --build --wait api-1
                        echo "=== API is up ==="
                    '''
                }

                // Compose creates its network after this stage container has started.
                // Attach the Playwright runner so api-1 resolves through Docker DNS.
                sh 'docker network connect srisurart-pos_default "$HOSTNAME"'

                dir('e2e') {
                    sh 'npm ci'
                    // Use playwright.config.ts so JUnit/HTML reports keep their configured paths.
                    sh 'npx playwright test'
                }
            }
            post {
                always {
                    // Disconnect first so Compose can remove its network cleanly.
                    sh 'docker network disconnect srisurart-pos_default "$HOSTNAME" || true'
                    dir('server') {
                        sh 'docker compose -f docker-compose.yml -f docker-compose.ci.yml down --remove-orphans || true'
                    }
                    // Publish reports
                    junit allowEmptyResults: true, testResults: 'e2e/reports/e2e-junit.xml'
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'e2e/playwright-report',
                        reportFiles: 'index.html',
                        reportName: 'Playwright E2E Report'
                    ])
                }
            }
        }

    }

    post {
        // เมื่อทุก stage ทำงานสำเร็จครบถ้วน
        success {
            echo "✓ ${env.APP_NAME} pipeline passed!"
        }
        // เมื่อมี stage ใด stage หนึ่งล้มเหลว จะแสดงชื่อ stage ที่พัง
        failure {
            echo "✗ Pipeline failed. Check stage logs above."
        }
        // หมายเหตุ: ไม่ใส่ archiveArtifacts / junit / publishCoverage ที่นี่
        // เพราะ pipeline-level post ไม่มี workspace (FilePath) เมื่อใช้ Docker agent
        // ให้ใช้ stage-level post { always } แทน
    }
}
