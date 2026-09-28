pipeline {
    // กำหนดให้รัน Pipeline ภายในคอนเทนเนอร์ Node 22 Alpine บนโหนด linux-build
    // node:22 เพราะ package.json กำหนด "engines": { "node": ">=22" }
    agent {
        docker {
            image 'node:22-alpine'
            label 'linux-build'
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
                    // Project uses pnpm (packageManager: pnpm@10.34.5) with pnpm-lock.yaml.
                    // Use npx to run the pinned pnpm version without corepack, because
                    // corepack enable writes symlinks to /usr/local/bin which requires root,
                    // but Docker Pipeline runs containers as the Jenkins UID (non-root).
                    sh 'npx --yes pnpm@10.34.5 install --frozen-lockfile'
                }
            }
        }

        stage('Lint') {
            steps {
                dir('server') {
                    echo "=== Running Linter for ${env.APP_NAME} ==="
                    sh 'npx --yes pnpm@10.34.5 run lint'
                }
            }
        }

        stage('Unit Test') {
            steps {
                dir('server') {
                    echo "=== Running Unit Tests for ${env.APP_NAME} ==="
                    sh 'npx --yes pnpm@10.34.5 test'
                }
            }
        }
    }

    post {
        // เมื่อทุก stage ทำงานสำเร็จครบถ้วน
        success {
            echo "✓ ${env.APP_NAME} passed on ${env.NODE_ENV}"
        }
        // เมื่อมี stage ใด stage หนึ่งล้มเหลว จะแสดงชื่อ stage ที่พัง
        failure {
            echo "✗ Failed at stage: ${env.STAGE_NAME}"
        }
        // ทำงานเสมอไม่ว่าจะ success หรือ failure เพื่อเก็บ log ไฟล์ debug ถ้ามี
        always {
            archiveArtifacts artifacts: 'server/npm-debug.log*,npm-debug.log*', allowEmptyArchive: true
        }
    }
}
