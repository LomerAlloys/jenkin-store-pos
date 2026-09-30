pipeline {

    agent {
        docker {
            image 'node:22'
            label 'linux-build'
            // + trivy-cache volume so the vuln DB isn't re-downloaded every build
            args '-u root --network jenkins-net -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/trivy'
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

        REGISTRY    = 'localhost:5000'
        IMAGE_NAME  = 'taskflow-api'
        DOCKER_VER  = '27.3.1'
        BUILDX_VER  = '0.17.1'
        TRIVY_VER   = '0.69.3'
    }

    options {
        // A pipeline stage should never run unbounded because a hung process
        // (such as an interactive prompt, deadlock, or network timeout) would
        // hold the Jenkins executor indefinitely, blocking subsequent jobs and wasting CI resources.
        timeout(time: 20, unit: 'MINUTES')
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

        // stage('SAST') {
        //     steps {
        //         // Install Semgrep
        //         sh '''
        //             command -v semgrep >/dev/null 2>&1 || {
        //                 apt-get update -qq && apt-get install -y -qq python3-pip
        //                 pip3 install --break-system-packages semgrep --quiet
        //             }
        //             semgrep --version
        //         '''

        //         dir('server') {
        //             // ESLint with security plugin — output as SARIF
        //             sh '''
        //                 pnpm add -D eslint-plugin-security @microsoft/eslint-formatter-sarif --silent
        //                 npx eslint \
        //                 --plugin security \
        //                 --format @microsoft/eslint-formatter-sarif \
        //                 --output-file ../eslint-results.sarif \
        //                 src/ \
        //                 || true   # warn-only: ESLint failures are reported but don't block
        //             '''

        //             // Semgrep OWASP Top 10 + Node.js rules
        //             sh '''
        //                 semgrep scan \
        //                 --config=p/owasp-top-ten \
        //                 --config=p/nodejs \
        //                 --sarif \
        //                 --output ../semgrep-results.sarif \
        //                 . \
        //                 || true   # warn-only
        //             '''
        //         }
        //     }
        //     post {
        //         always {
        //             archiveArtifacts artifacts: '*.sarif', allowEmptyArchive: true
        //         }
        //     }
        // }

        // stage('SCA — npm audit') {
        //     steps {
        //         script {
        //             sh 'apt-get install -y -qq jq'

        //             dir('server') {
        //                 sh 'npm audit --audit-level=high --json > ../audit.json || true'
        //             }

        //             // Use jq "// 0" fallback so missing field returns 0 instead of literal "null".
        //             // npm v6: .metadata.vulnerabilities.critical  |  npm v7+: same path but may be absent.
        //             def rawCritical = sh(
        //                 script: "jq '.metadata.vulnerabilities.critical // 0' audit.json",
        //                 returnStdout: true
        //             ).trim()

        //             def critical = rawCritical.isInteger() ? rawCritical.toInteger() : 0
        //             echo "Critical vulnerabilities found: ${critical}"

        //             if (critical > 0) {
        //                 error("🚨 Blocking: ${critical} critical vulnerabilities found — fix before merging!")
        //             }
        //             echo "✅ SCA passed with 0 critical vulnerabilities (warnings allowed)"
        //         }
        //     }
        //     post {
        //         always {
        //             archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true
        //         }
        //     }
        // }

        // stage('Generate SBOM') {
        //     steps {
        //         sh '''
        //             # Install Syft
        //             curl -sSfL \
        //             "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
        //             | sh -s -- -b /usr/local/bin "v${SYFT_VER}"
        //             syft version

        //             # Install Cosign
        //             curl -sSfL \
        //             "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VER}/cosign-linux-amd64" \
        //             -o /usr/local/bin/cosign
        //             chmod +x /usr/local/bin/cosign
        //             cosign version

        //             # Generate CycloneDX SBOM for the server app
        //             syft dir:server \
        //             --output cyclonedx-json=taskflow-api.cdx.json
        //         '''

        //         // Sign with Cosign using the injected private key + password
        //         withCredentials([
        //             file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY'),
        //             string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')
        //         ]) {
        //             sh '''
        //                 cosign sign-blob \
        //                 --key "$COSIGN_KEY" \
        //                 --output-signature taskflow-api.cdx.json.sig \
        //                 taskflow-api.cdx.json
        //                 echo "✅ SBOM signed"
        //             '''
        //         }
        //     }
        //     post {
        //         always {
        //             archiveArtifacts artifacts: 'taskflow-api.cdx.json, taskflow-api.cdx.json.sig', allowEmptyArchive: true
        //         }
        //     }
        // }
        
        // stage('Policy Gate') {
        //     steps {
        //         script {
        //             sh '''
        //                 # Install OPA
        //                 curl -sSfL \
        //                 "https://openpolicyagent.org/downloads/v${OPA_VER}/opa_linux_amd64_static" \
        //                 -o /usr/local/bin/opa
        //                 chmod +x /usr/local/bin/opa
        //                 opa version

        //                 # Evaluate policy against the npm audit result
        //                 opa eval \
        //                 --data policy/security.rego \
        //                 --input audit.json \
        //                 --format json \
        //                 "data.security.deny" \
        //                 > opa-result.json 2>&1
        //                 cat opa-result.json
        //                 # Extract just the deny array value ([] = no denials, ["msg",...] = blocked)
        //                 jq -r '
        //                   if .result == null or (.result | length) == 0
        //                   then "[]"
        //                   else (.result[0].expressions[0].value | @json)
        //                   end
        //                 ' opa-result.json > opa-result.txt
        //                 cat opa-result.txt
        //             '''

        //             def result = readFile('opa-result.txt').trim()
        //             // [] means no denials (pass). Anything else is a denial message array.
        //             if (result != '[]') {
        //                 error("🚨 Policy Gate FAILED:\n${result}")
        //             }
        //             echo "✅ Policy Gate passed — no critical CVEs"
        //         }
        //     }
        //     post {
        //         always {
        //             archiveArtifacts artifacts: 'opa-result.json, opa-result.txt', allowEmptyArchive: true
        //         }
        //     }
        // }

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

        stage('Setup CD Tools') {
            steps {
                sh '''
                    # Docker CLI (static) + buildx plugin — talks to host daemon via the mounted socket
                    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VER}.tgz" \
                    | tar -xz --strip-components=1 -C /usr/local/bin docker/docker
                    mkdir -p /usr/local/lib/docker/cli-plugins
                    curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VER}/buildx-v${BUILDX_VER}.linux-amd64" \
                    -o /usr/local/lib/docker/cli-plugins/docker-buildx
                    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

                    # Trivy (pinned + checksum-verified; no install.sh from 'main')
                    cd /tmp
                    curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz"
                    curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_checksums.txt"
                    grep " trivy_${TRIVY_VER}_Linux-64bit.tar.gz\$" "trivy_${TRIVY_VER}_checksums.txt" | sha256sum -c -
                    tar -xzf "trivy_${TRIVY_VER}_Linux-64bit.tar.gz" -C /usr/local/bin trivy
                    cd - >/dev/null

                    # kubectl (current stable, avoids version skew with the kind node)
                    curl -fsSL -o /usr/local/bin/kubectl \
                    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x /usr/local/bin/kubectl

                    docker version && docker buildx version && trivy --version && kubectl version --client
                '''
            }
        }

        stage('Build Image') {
            steps {
                script {
                    // Immutable tag = short commit SHA. NEVER 'latest'.
                    env.IMAGE_TAG = env.GIT_COMMIT.take(7)
                    env.IMAGE_REF = "${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
                sh '''
                    docker build \
                    --label org.opencontainers.image.revision="$GIT_COMMIT" \
                    -t "$IMAGE_REF" server
                    echo "Built $IMAGE_REF"
                '''
            }
        }

        stage('Container Scan') {
            steps {
                sh '''
                    # Human-readable table in the console (never fails)
                    trivy image --image-src docker --severity HIGH,CRITICAL --ignore-unfixed \
                    --format table "$IMAGE_REF" || true

                    # The gate: exit 1 on any fixable HIGH/CRITICAL; SARIF is the deliverable
                    trivy image --image-src docker --severity HIGH,CRITICAL --ignore-unfixed \
                    --exit-code 1 --format sarif --output trivy-results.sarif "$IMAGE_REF"
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-results.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('Push Image') {
            steps {
                sh '''
                    # Immutability guard: never overwrite a tag that already exists in the registry
                    if curl -sf -o /dev/null \
                        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                        -H "Accept: application/vnd.oci.image.index.v1+json" \
                        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
                        "http://kind-registry:5000/v2/${IMAGE_NAME}/manifests/${IMAGE_TAG}"; then
                    echo "Tag ${IMAGE_TAG} already in registry — not overwriting (immutable tags)"
                    else
                    docker push "$IMAGE_REF"
                    fi
                '''
            }
        }

        stage('Blue/Green Deploy') {
            steps {
                withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                        def current = sh(
                            script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'",
                            returnStdout: true
                        ).trim()
                        def next = (current == 'blue') ? 'green' : 'blue'

                        // Stash in env so post { failure } can see them (def vars can't)
                        env.PREV_COLOR = current
                        env.NEXT_COLOR = next

                        def deployImage = params.BREAK_DEPLOY
                            ? "${env.REGISTRY}/${env.IMAGE_NAME}:broken"
                            : env.IMAGE_REF
                        echo "Live = ${current}. Deploying ${deployImage} to idle color ${next}"

                        sh 'kubectl get svc taskflow -o yaml > svc-before.yaml'

                        sh "kubectl set image deployment/taskflow-${next} app=${deployImage}"
                        // --timeout is essential: without it a broken image hangs ~10 min
                        sh "kubectl rollout status deployment/taskflow-${next} --timeout=120s"

                        // Smoke test the NEW pods directly, bypassing the live Service
                        sh """
                            kubectl run smoke-${env.BUILD_NUMBER} --rm -i --restart=Never \
                            --image=curlimages/curl:8.10.1 -- \
                            curl -sf --retry 5 --retry-connrefused --retry-delay 2 \
                            http://taskflow-${next}:8080/health/live
                        """

                        // Flip traffic
                        sh """kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"${next}"}}}'"""
                        sh 'kubectl get svc taskflow -o yaml > svc-after.yaml'
                        echo "Switched traffic from ${current} to ${next}"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'svc-before.yaml, svc-after.yaml', allowEmptyArchive: true
                }
                failure {
                    withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                        script {
                            if (env.PREV_COLOR) {
                                echo "⏪ AUTOMATIC ROLLBACK: pointing Service 'taskflow' back to ${env.PREV_COLOR}"
                                sh """kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"${env.PREV_COLOR}"}}}'"""
                                // Also restore the idle deployment to its last good revision
                                sh "kubectl rollout undo deployment/taskflow-${env.NEXT_COLOR} || true"
                                sh "echo \"Service now serving: \$(kubectl get svc taskflow -o jsonpath='{.spec.selector.color}')\""
                            }
                        }
                    }
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

        // stage('E2E Test') {
        //     environment {
        //         API_BASE_URL = 'http://api-1:3000'
        //     }
        //     steps {
        //         // Playwright image มี browser/Node แต่ไม่มี Docker CLI จึงติดตั้งเฉพาะ client
        //         sh '''
        //             apt-get update -qq
        //             DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2
        //             echo "=== Docker & Compose versions ==="
        //             docker --version
        //             docker compose version
        //         '''

        //         // Start the API stack through the mounted host Docker socket.
        //         dir('server') {
        //             sh '''
        //                 cp -n .env.example .env 2>/dev/null || true
        //                 docker compose \
        //                     -f docker-compose.yml \
        //                     -f docker-compose.ci.yml \
        //                     up -d --build --wait api-1
        //                 echo "=== API is up ==="
        //             '''
        //         }

        //         // Compose creates its network after this stage container has started.
        //         // Attach the Playwright runner so api-1 resolves through Docker DNS.
        //         sh 'docker network connect srisurart-pos_default "$HOSTNAME"'

        //         dir('e2e') {
        //             sh 'npm ci'
        //             // Use playwright.config.ts so JUnit/HTML reports keep their configured paths.
        //             sh 'npx playwright test'
        //         }
        //     }
        //     post {
        //         always {
        //             // Disconnect first so Compose can remove its network cleanly.
        //             sh 'docker network disconnect srisurart-pos_default "$HOSTNAME" || true'
        //             dir('server') {
        //                 sh 'docker compose -f docker-compose.yml -f docker-compose.ci.yml down --remove-orphans || true'
        //             }
        //             // Publish reports
        //             junit allowEmptyResults: true, testResults: 'e2e/reports/e2e-junit.xml'
        //             publishHTML([
        //                 allowMissing: true,
        //                 alwaysLinkToLastBuild: true,
        //                 keepAll: true,
        //                 reportDir: 'e2e/playwright-report',
        //                 reportFiles: 'index.html',
        //                 reportName: 'Playwright E2E Report'
        //             ])
        //         }
        //     }
        // }

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


