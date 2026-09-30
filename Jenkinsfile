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
        GITLEAKS_VER = '8.18.4'
        SYFT_VER     = '1.4.1'
        COSIGN_VER   = '2.2.4'
        OPA_VER      = '0.64.1'
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
        stage('Setup Python & Install') {
            steps {
                sh '''
                    apt-get update && apt-get install -y python3-venv

                    # Create and activate a venv in the current workspace
                    python3 -m venv .venv
                    . .venv/bin/activate

                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Secrets Detection') {
            steps {
                sh '''
                    # Install Gitleaks
                    curl -sSfL \
                    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz" \
                    | tar -xz -C /usr/local/bin gitleaks
                    gitleaks version
                    # Scan full git history — exit 0 so we can archive the report first
                    gitleaks detect \
                    --source . \
                    --config .gitleaks.toml \
                    --report-format json \
                    --report-path gitleaks-report.json \
                    --no-git false \
                    --exit-code 1 \
                    || GITLEAKS_EXIT=$?
                    echo "Gitleaks exit code: ${GITLEAKS_EXIT:-0}"
                    exit ${GITLEAKS_EXIT:-0}
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('SAST') {
            steps {
                // Install Semgrep
                sh 'pip3 install semgrep --quiet || apt-get install -y python3-pip -qq && pip3 install semgrep --quiet'

                dir('server') {
                    // ESLint with security plugin — output as SARIF
                    sh '''
                        pnpm add -D eslint-plugin-security @microsoft/eslint-formatter-sarif --silent
                        npx eslint \
                        --plugin security \
                        --format @microsoft/eslint-formatter-sarif \
                        --output-file ../eslint-results.sarif \
                        src/ \
                        || true   # warn-only: ESLint failures are reported but don't block
                    '''

                    // Semgrep OWASP Top 10 + Node.js rules
                    sh '''
                        semgrep scan \
                        --config=p/owasp-top-ten \
                        --config=p/nodejs \
                        --sarif \
                        --output ../semgrep-results.sarif \
                        . \
                        || true   # warn-only
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: '*.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('SCA — npm audit') {
            steps {
                dir('server') {
                    script {
                        sh 'npm audit --audit-level=high --json > ../audit.json || true'

                        def critical = sh(
                            script: "jq '.metadata.vulnerabilities.critical' ../audit.json",
                            returnStdout: true
                        ).trim().toInteger()

                        if (critical > 0) {
                            error("🚨 Blocking: ${critical} critical vulnerabilities found — fix before merging!")
                        }
                        echo "✅ SCA passed with 0 critical vulnerabilities (warnings allowed)"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true
                }
            }
        }

        stage('Generate SBOM') {
            steps {
                sh '''
                    # Install Syft
                    curl -sSfL \
                    "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
                    | sh -s -- -b /usr/local/bin "v${SYFT_VER}"
                    syft version

                    # Install Cosign
                    curl -sSfL \
                    "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VER}/cosign-linux-amd64" \
                    -o /usr/local/bin/cosign
                    chmod +x /usr/local/bin/cosign
                    cosign version

                    # Generate CycloneDX SBOM for the server app
                    syft dir:server \
                    --output cyclonedx-json \
                    --file taskflow-api.cdx.json
                '''

                // Sign with Cosign using the injected private key
                withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
                    sh '''
                        COSIGN_PASSWORD="" cosign sign-blob \
                        --key "$COSIGN_KEY" \
                        --output-signature taskflow-api.cdx.json.sig \
                        taskflow-api.cdx.json
                        echo "✅ SBOM signed"
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'taskflow-api.cdx.json, taskflow-api.cdx.json.sig', allowEmptyArchive: true
                }
            }
        }
        
        stage('Policy Gate') {
            steps {
                script {
                    sh '''
                        # Install OPA
                        curl -sSfL \
                        "https://openpolicyagent.org/downloads/v${OPA_VER}/opa_linux_amd64_static" \
                        -o /usr/local/bin/opa
                        chmod +x /usr/local/bin/opa
                        opa version

                        # Evaluate policy against the npm audit result
                        opa eval \
                        --data policy/security.rego \
                        --input audit.json \
                        --format pretty \
                        "data.security.deny" \
                        > opa-result.txt 2>&1
                        cat opa-result.txt
                    '''

                    def result = readFile('opa-result.txt').trim()
                    // OPA returns [] when no denials, or ["msg1",...] when denied
                    if (result != '[]') {
                        error("🚨 Policy Gate FAILED:\n${result}")
                    }
                    echo "✅ Policy Gate passed — no critical CVEs"
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'opa-result.txt', allowEmptyArchive: true
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
