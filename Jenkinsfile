pipeline {

    // Lab 09/10: every build gets a brand-new pod in kind (namespace jenkins-agents),
    // deleted when the build ends. node:22: package.json requires Node >= 22 and
    // SonarScanner's JRE needs glibc. /tools = ci-tools PVC (cached, verified CI tools).
    agent {
        kubernetes {
            cloud 'kind'
            defaultContainer 'node'     // sh steps run in "node", not in the jnlp container
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    app: taskflow-ci
                spec:
                  containers:
                  - name: node
                    image: node:22
                    command: ['cat']
                    tty: true
                    resources:
                      requests:
                        cpu: 500m
                        memory: 1536Mi
                    volumeMounts:
                    - name: ci-tools
                      mountPath: /tools
                  volumes:
                  - name: ci-tools
                    persistentVolumeClaim:
                      claimName: ci-tools
            '''
        }
    }

    parameters {
        booleanParam(name: 'BREAK_DEPLOY', defaultValue: false,
                     description: 'Lab 07 demo: deploy the broken image to prove the automatic rollback')
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

        // Lab 10: more pinned tools (ci/install-tools.sh verifies checksums, caches on /tools)
        JQ_VER       = '1.7.1'
        TFSEC_VER    = '1.28.14'
        CHECKOV_VER  = '3.3.20'

        // Lab 10: health gate (Task 4) + notifications (Task 5)
        PROM_URL         = 'http://prometheus:9090'
        HEALTH_WINDOW    = '20'
        HEALTH_THRESHOLD = '0.90'
        SLACK_CHANNEL = '#taskflow-ci'
    }

    options {
        // Never run unbounded: a hung process would hold the pod and the executor forever.
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
        parallelsAlwaysFailFast()       // one red parallel branch aborts its siblings (fail fast)
        disableConcurrentBuilds()       // two builds of the same branch must not deploy at once
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {

        // ------------------------------------------------------------------
        // 1. PREPARE: tools and dependencies don't depend on each other
        // ------------------------------------------------------------------
        stage('Prepare') {
            parallel {
                stage('Setup Tools') {
                    steps {
                        // jnlp (uid 1000) checked out the workspace, we run as root -> "dubious ownership"
                        sh 'git config --global --add safe.directory "*"'
                        sh 'bash ci/install-tools.sh'
                    }
                }
                stage('Install') {
                    steps {
                        dir('server') {
                            // pnpm@10 pinned by packageManager in package.json; corepack provides it
                            sh 'corepack enable && pnpm install --frozen-lockfile'
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // 2. STATIC CHECKS: all of them only READ the source -> run together
        // ------------------------------------------------------------------
        stage('Static Checks') {
            parallel {

                stage('Lint') {
                    steps {
                        dir('server') { sh 'pnpm run lint' }
                    }
                }

                stage('Unit Test') {
                    steps {
                        dir('server') { sh 'pnpm test' }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true, testResults: 'server/reports/junit.xml'
                            publishCoverage adapters: [coberturaAdapter('server/coverage/cobertura-coverage.xml')]
                        }
                    }
                }

                stage('SAST') {
                    steps {
                        dir('server') {
                            // full report for the record (never fails here)...
                            sh '''
                                semgrep scan --config=p/owasp-top-ten --config=p/nodejs \
                                  --sarif --output ../semgrep-results.sarif . || true
                            '''
                        }
                        script {
                            // ...the gate: any ERROR-severity finding blocks. A missing report (semgrep crashed)
                            // makes jq fail, so the gate fails closed.
                            def raw = sh(returnStdout: true, script: '''
                                jq '[.runs[].results[] | select(.level == "error")] | length' semgrep-results.sarif
                            ''').trim()
                            def errors = raw.isInteger() ? raw.toInteger() : 0
                            echo "Semgrep ERROR findings: ${errors}"
                            if (errors > 0) {
                                error("SAST: ${errors} ERROR-severity findings (see semgrep-results.sarif)")
                            }
                        }
                    }
                    post {
                        always { archiveArtifacts artifacts: 'semgrep-results.sarif', allowEmptyArchive: true }
                    }
                }

                stage('SCA + Policy Gate') {
                    stages {
                        stage('Dependency Audit') {
                            steps {
                                dir('server') {
                                    // pnpm project: "npm audit" needs package-lock.json (there is none), so it
                                    // errored and the old gate read "0 critical". pnpm audit reads pnpm-lock.yaml
                                    // and prints the same JSON shape (.metadata.vulnerabilities.*).
                                    sh 'pnpm audit --json > ../audit.json || true'
                                }
                                script {
                                    // fail closed: no metadata means the audit itself failed (network, lockfile)
                                    if (sh(returnStatus: true, script: "jq -e '.metadata.vulnerabilities' audit.json > /dev/null") != 0) {
                                        error('SCA: pnpm audit produced no report, see audit.json')
                                    }
                                    sh "jq -c '.metadata.vulnerabilities' audit.json"
                                }
                            }
                        }
                        stage('Policy Gate') {
                            steps {
                                // The decision is made here, by policy-as-code (policy/security.rego)
                                sh '''
                                    opa eval --data policy/security.rego --input audit.json \
                                      --format json "data.security.deny" > opa-result.json
                                    jq -r 'if .result == null or (.result | length) == 0
                                           then "[]" else (.result[0].expressions[0].value | @json) end' \
                                      opa-result.json > opa-result.txt
                                    cat opa-result.txt
                                '''
                                script {
                                    def result = readFile('opa-result.txt').trim()
                                    if (result != '[]') {
                                        error("Policy Gate FAILED:\n${result}")
                                    }
                                    echo 'Policy Gate passed: no critical CVEs'
                                }
                            }
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'audit.json, opa-result.json, opa-result.txt', allowEmptyArchive: true
                        }
                    }
                }

                stage('Secrets Detection') {
                    steps {
                        // Scans the whole git HISTORY. (The old "--no-git false" silently switched that off.)
                        sh '''
                            gitleaks detect --source . --config .gitleaks.toml --redact \
                              --report-format json --report-path gitleaks-report.json --exit-code 1
                        '''
                    }
                    post {
                        always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true }
                    }
                }

                stage('SBOM & Sign') {
                    steps {
                        sh 'syft dir:server --output cyclonedx-json=taskflow-api.cdx.json'
                        withCredentials([
                            file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY'),
                            string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')
                        ]) {
                            // single quotes: the SHELL expands $COSIGN_KEY, Groovy never sees the secret
                            sh 'cosign sign-blob --yes --key "$COSIGN_KEY" --output-signature taskflow-api.cdx.json.sig taskflow-api.cdx.json'
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'taskflow-api.cdx.json, taskflow-api.cdx.json.sig', allowEmptyArchive: true
                        }
                    }
                }

                stage('IaC Scan') {
                    steps {
                        // Lab 08's static gates. plan/apply stay in the separate taskflow-infra job.
                        dir('infra/terraform') {
                            sh '''
                                tfsec . --no-color --format sarif --out ../../tfsec-results.sarif --soft-fail
                                tfsec . --no-color --minimum-severity HIGH
                                checkov -d . --framework terraform --quiet --compact \
                                  -o cli -o junitxml --output-file-path console,../../checkov-junit.xml
                            '''
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'tfsec-results.sarif, checkov-junit.xml', allowEmptyArchive: true
                        }
                    }
                }

                stage('Jenkinsfile Secret Lint') {
                    steps {
                        sh 'bash ci/check-jenkinsfile-secrets.sh'
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // 3. CODE QUALITY: needs the coverage report from Unit Test
        // ------------------------------------------------------------------
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
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

        // Lab 09: these stages need the HOST Docker daemon (docker build/push, trivy --image-src docker).
        // kind nodes run containerd, so a pod has no docker.sock -> keep them on the static agent.
        // One parent stage = one container, so tools installed in Setup CD Tools survive.
        stage('Image & Deploy (Docker host)') {
            agent {
                docker {
                    image 'node:22'
                    label 'linux-build'
                    // + trivy-cache volume so the vuln DB isn't re-downloaded every build
                    args '-u root --network jenkins-net -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/trivy'
                }
            }
            stages {
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
                beforeInput true            // Lab 10: check the branch BEFORE asking for approval
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

    // ----------------------------------------------------------------------
    // 7. NOTIFY
    // ----------------------------------------------------------------------
    post {
        success {
            slackSend(channel: env.SLACK_CHANNEL, color: 'good',
                      message: "✅ *${env.JOB_NAME}* #${env.BUILD_NUMBER} passed on branch `${env.BRANCH_NAME}` " +
                               "(${currentBuild.durationString.replace(' and counting', '')})\n${env.BUILD_URL}")
        }
        failure {
            slackSend(channel: env.SLACK_CHANNEL, color: 'danger',
                      message: "❌ *${env.JOB_NAME}* #${env.BUILD_NUMBER} FAILED on branch `${env.BRANCH_NAME}`\n" +
                               "${env.BUILD_URL}console")
        }
        aborted {
            slackSend(channel: env.SLACK_CHANNEL, color: 'warning',
                      message: "⏹ *${env.JOB_NAME}* #${env.BUILD_NUMBER} aborted on branch `${env.BRANCH_NAME}` " +
                               "(approval rejected or timed out)\n${env.BUILD_URL}")
        }
    }
}
