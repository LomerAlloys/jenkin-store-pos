// One "build" = one k8s-node pod that holds its executor for 5 minutes.
pipeline {
    agent { label 'k8s-node' }        // the UI Pod Template → its Concurrency Limit applies
    parameters {
        // Different values stop Jenkins from merging identical queued builds into one
        string(name: 'RUN_ID', defaultValue: 'manual')
    }
    options { timeout(time: 60, unit: 'MINUTES') }   // includes time spent waiting in the queue
    stages {
        stage('Hold executor') {
            steps {
                container('node') {
                    sh 'echo "run $RUN_ID on $(hostname)"; sleep 300'
                }
            }
        }
    }
}
