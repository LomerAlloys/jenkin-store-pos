// Lab 10 - one build that finishes in about a second with the result you pick.
// Used only to move Jenkins' "last 20 builds" success rate for the Health Gate demo.
// agent none: no pod, no executor. echo/error don't need a workspace.
pipeline {
    agent none
    parameters {
        choice(name: 'OUTCOME', choices: ['FAILURE', 'SUCCESS'], description: 'Result of this build')
        string(name: 'RUN_ID', defaultValue: 'manual', description: 'Unique value so queued builds are not merged')
    }
    stages {
        stage('Simulate') {
            steps {
                script {
                    if (params.OUTCOME == 'FAILURE') {
                        error("Simulated failure (run ${params.RUN_ID}) for the health-gate demo")
                    }
                    echo "Simulated success (run ${params.RUN_ID})"
                }
            }
        }
    }
}
