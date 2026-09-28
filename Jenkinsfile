pipeline {
    // กำหนดให้รัน Pipeline ภายในคอนเทนเนอร์ Node 20 Alpine บนโหนด linux-build
    agent {
        docker {
            image 'node:20-alpine'
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
                    sh 'npm install --package-lock-only --legacy-peer-deps --no-audit'
                    sh 'npm ci --legacy-peer-deps'
                }
            }
        }

        stage('Lint') {
            steps {
                dir('server') {
                    echo "=== Running Linter for ${env.APP_NAME} ==="
                    sh 'npm run lint'
                }
            }
        }

        stage('Unit Test') {
            steps {
                dir('server') {
                    echo "=== Running Unit Tests for ${env.APP_NAME} ==="
                    sh 'npm test'
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
        // always {
        //     node('linux-build') {
        //         archiveArtifacts artifacts: 'server/npm-debug.log*,npm-debug.log*', allowEmptyArchive: true
        //     }
        // }
    }
}
