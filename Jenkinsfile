// =============================================================================
// taskflow-api: Lab 10 capstone pipeline (Labs 03-09 combined)
// Code -> Commit -> Build -> Test -> Stage -> Deploy -> Monitor
//
// Every stage runs in ONE ephemeral pod on the Lab 09 Kubernetes cloud "kind":
//   node : Node 22 + all CI tools (downloaded once, cached on the ci-tools PVC)
//   dind : a Docker daemon for docker build/push (kind nodes run containerd,
//          so there is no host docker.sock to mount any more)
// Nothing runs on the static linux-build agent.
// =============================================================================
pipeline {

    agent {
        kubernetes {
            cloud 'kind'
            defaultContainer 'node'     // sh steps run in "node" unless wrapped in container('dind')
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
                  - name: dind
                    image: docker:27.3.1-dind
                    args: ['--insecure-registry=kind-registry:5000']
                    securityContext:
                      privileged: true
                    resources:
                      requests:
                        cpu: 500m
                        memory: 1Gi
                    volumeMounts:
                    - name: dind-storage
                      mountPath: /var/lib/docker
                  volumes:
                  - name: ci-tools
                    persistentVolumeClaim:
                      claimName: ci-tools
                  - name: dind-storage
                    emptyDir: {}
            '''
        }
    }

    parameters {
        booleanParam(name: 'BREAK_DEPLOY', defaultValue: false,
                     description: 'Lab 07 demo: deploy the broken image to prove the automatic rollback')
    }

    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
        PATH     = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

        // Pinned tool versions. ci/install-tools.sh verifies checksums and caches them on /tools.
        JQ_VER       = '1.7.1'
        GITLEAKS_VER = '8.18.4'
        SYFT_VER     = '1.4.1'
        COSIGN_VER   = '2.2.4'
        OPA_VER      = '0.64.1'
        TRIVY_VER    = '0.69.3'        // never 0.69.4 (March 2026 supply-chain incident)
        TFSEC_VER    = '1.28.14'
        CHECKOV_VER  = '3.3.20'
        TRIVY_CACHE_DIR = '/tools/trivy-cache'   // vuln DB survives between builds

        IMAGE_NAME    = 'taskflow-api'
        PUSH_REGISTRY = 'kind-registry:5000'     // CI pushes here (the name resolves from pods)
        PULL_REGISTRY = 'localhost:5000'         // kind node pulls this; containerd mirrors it to kind-registry

        PROM_URL         = 'http://prometheus:9090'   // Lab 09 Prometheus on jenkins-net
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

        // ------------------------------------------------------------------
        // 4. BUILD -> SCAN -> PUSH: each step needs the previous one
        // ------------------------------------------------------------------
        stage('Build Image') {
            steps {
                script {
                    env.IMAGE_TAG  = env.GIT_COMMIT.take(7)          // immutable tag, NEVER 'latest'
                    env.PUSH_REF   = "${env.PUSH_REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                    env.DEPLOY_REF = "${env.PULL_REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
                container('dind') {
                    sh '''
                        # the sidecar daemon starts together with the pod, give it a moment
                        for i in $(seq 1 30); do docker info > /dev/null 2>&1 && break; sleep 2; done
                        docker info --format 'dockerd {{.ServerVersion}}, storage driver {{.Driver}}'

                        docker build --label org.opencontainers.image.revision="$GIT_COMMIT" \
                          -t "$PUSH_REF" server
                        # hand the image to Trivy (in the node container) through the shared workspace
                        docker save -o image.tar "$PUSH_REF"
                    '''
                }
            }
        }

        stage('Container Scan') {
            steps {
                sh '''
                    # human-readable table in the console (never fails)
                    trivy image --input image.tar --severity HIGH,CRITICAL --ignore-unfixed \
                      --format table || true
                    # the gate: any fixable HIGH/CRITICAL fails; SARIF is the deliverable
                    trivy image --input image.tar --severity HIGH,CRITICAL --ignore-unfixed \
                      --exit-code 1 --format sarif --output trivy-results.sarif
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-results.sarif', allowEmptyArchive: true
                    sh 'rm -f image.tar'
                }
            }
        }

        stage('Push Image') {
            when { anyOf { branch 'develop'; branch 'main' } }   // feature branches build + scan only
            steps {
                script {
                    // Immutability guard: never overwrite a tag that is already in the registry
                    def exists = sh(returnStatus: true, script: '''
                        curl -sf -o /dev/null \
                          -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                          -H "Accept: application/vnd.oci.image.index.v1+json" \
                          -H "Accept: application/vnd.oci.image.manifest.v1+json" \
                          "http://${PUSH_REGISTRY}/v2/${IMAGE_NAME}/manifests/${IMAGE_TAG}"
                    ''') == 0
                    if (exists) {
                        echo "Tag ${env.IMAGE_TAG} already in the registry, not overwriting (immutable tags)"
                    } else {
                        container('dind') {
                            withCredentials([usernamePassword(credentialsId: 'registry-creds',
                                                              usernameVariable: 'REG_USER',
                                                              passwordVariable: 'REG_PASS')]) {
                                sh '''
                                    echo "$REG_PASS" | docker login "$PUSH_REGISTRY" -u "$REG_USER" --password-stdin
                                    docker push "$PUSH_REF"
                                    docker logout "$PUSH_REGISTRY"
                                '''
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // 5. STAGE (develop): new image on the IDLE color, users keep the live one
        // ------------------------------------------------------------------
        stage('Deploy - Staging') {
            when { branch 'develop' }
            steps {
                withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                        def color = deployToIdleColor(env.DEPLOY_REF, 'stg')
                        env.STAGING_URL = "http://taskflow-${color}.default.svc.cluster.local:8080"
                        echo "Staging = color ${color} at ${env.STAGING_URL} (the live Service was NOT switched)"
                    }
                }
            }
            post {
                failure {
                    withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                        script {
                            if (env.NEXT_COLOR) {
                                sh "kubectl rollout undo deployment/taskflow-${env.NEXT_COLOR} || true"
                            }
                        }
                    }
                }
            }
        }

        stage('E2E - Staging') {
            when { branch 'develop' }
            steps {
                dir('e2e') {
                    // API-only Playwright specs: no browser needed, so plain node:22 is enough
                    sh 'npm ci && API_BASE_URL="$STAGING_URL" npx playwright test'
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'e2e/reports/e2e-junit.xml'
                    archiveArtifacts artifacts: 'e2e/playwright-report/**', allowEmptyArchive: true
                }
            }
        }

        // ------------------------------------------------------------------
        // 6. DEPLOY (main): health gate -> human approval -> blue/green switch
        // ------------------------------------------------------------------
        stage('Pipeline Health Gate') {
            when { branch 'main' }
            steps {
                sh 'bash ci/health-gate.sh'
            }
            post {
                always { archiveArtifacts artifacts: 'health-*.json', allowEmptyArchive: true }
            }
        }

        stage('Deploy - Production') {
            when {
                beforeInput true            // don't even ask for approval on non-main branches
                branch 'main'
            }
            options { timeout(time: 30, unit: 'MINUTES') }   // nobody approves -> abort, pod freed
            input {
                message 'Health gate passed. Deploy to production?'
                ok 'Promote to Production'
                submitter 'admin'
            }
            steps {
                withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                        def image = params.BREAK_DEPLOY ? "${env.PULL_REGISTRY}/${env.IMAGE_NAME}:broken" : env.DEPLOY_REF
                        sh 'kubectl get svc taskflow -o yaml > svc-before.yaml'
                        def next = deployToIdleColor(image, 'prod')
                        // flip live traffic
                        sh """kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"${next}"}}}'"""
                        sh 'kubectl get svc taskflow -o yaml > svc-after.yaml'
                        echo "Switched live traffic ${env.PREV_COLOR} -> ${next}"
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
                                echo "AUTOMATIC ROLLBACK: pointing Service 'taskflow' back to ${env.PREV_COLOR}"
                                sh """kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"${env.PREV_COLOR}"}}}'"""
                                sh "kubectl rollout undo deployment/taskflow-${env.NEXT_COLOR} || true"
                                sh "echo \"Service now serving: \$(kubectl get svc taskflow -o jsonpath='{.spec.selector.color}')\""
                            }
                        }
                    }
                }
            }
        }
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

// =============================================================================
// Deploy an image to the IDLE color, wait for the rollout, smoke-test it directly.
// Does NOT switch the live Service. Stores PREV_COLOR/NEXT_COLOR in env (not in a
// def variable) so that post { failure } can roll back.
// =============================================================================
def deployToIdleColor(String image, String tag) {
    def current = sh(returnStdout: true,
                     script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'").trim()
    def next = (current == 'blue') ? 'green' : 'blue'
    env.PREV_COLOR = current
    env.NEXT_COLOR = next
    echo "Live = ${current}. Deploying ${image} to idle color ${next}"

    sh "kubectl set image deployment/taskflow-${next} app=${image}"
    // --timeout is essential: without it a broken image hangs for ~10 minutes
    sh "kubectl rollout status deployment/taskflow-${next} --timeout=120s"

    def smoke = "smoke-${tag}-${env.BUILD_NUMBER}"
    sh "kubectl delete pod ${smoke} --ignore-not-found"
    sh """
        kubectl run ${smoke} --rm -i --restart=Never \
          --image=curlimages/curl:8.10.1 -- \
          curl -sf --retry 5 --retry-connrefused --retry-delay 2 \
          http://taskflow-${next}:8080/health/live
    """
    return next
}
