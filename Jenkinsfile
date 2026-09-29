pipeline {
    // กำหนดให้รัน Pipeline ภายในคอนเทนเนอร์ Node 22 Alpine บนโหนด linux-build
    // node:22 เพราะ package.json กำหนด "engines": { "node": ">=22" }
    agent {
        docker {
            // node:22 (Debian bookworm) ใช้ glibc ซึ่ง sonar-scanner JRE ต้องการ
            // node:22-alpine ใช้ musl libc → sonar-scanner bundled JRE รันไม่ได้ ("java: not found")
            image 'node:22'
            label 'linux-build'
            // -u root: รันเป็น root เพื่อให้ corepack/pnpm ทำงานได้
            // --network jenkins-net: ให้ container เข้าถึง sonarqube:9000 ผ่าน Docker network ได้
            args '-u root --network jenkins-net'
        }
    }

    // กำหนดค่า Environment Variables สำหรับใช้ทั้ง Pipeline
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
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
