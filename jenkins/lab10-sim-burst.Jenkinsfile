// Lab 10 - run lab10-sim COUNT times in a row with the same OUTCOME.
//   OUTCOME=FAILURE, COUNT=4  -> last 20 builds drop to ~80% -> Health Gate blocks
//   OUTCOME=SUCCESS, COUNT=20 -> the failures fall out of the window -> Health Gate passes again
pipeline {
    agent none
    parameters {
        choice(name: 'OUTCOME', choices: ['FAILURE', 'SUCCESS'])
        string(name: 'COUNT', defaultValue: '4')
    }
    stages {
        stage('Fire') {
            steps {
                script {
                    int n = params.COUNT.toInteger()
                    for (int i = 1; i <= n; i++) {
                        // wait: true = one after another; propagate: false = this job stays green
                        build job: 'lab10-sim', wait: true, propagate: false,
                              parameters: [string(name: 'OUTCOME', value: params.OUTCOME),
                                           string(name: 'RUN_ID', value: "${env.BUILD_NUMBER}-${i}")]
                    }
                }
            }
        }
    }
}
