// Fires 10 lab09-load builds at once. agent none: the build step needs no executor.
pipeline {
    agent none
    stages {
        stage('Fire 10 concurrent builds') {
            steps {
                script {
                    for (int i = 1; i <= 10; i++) {
                        build job: 'lab09-load',
                              parameters: [string(name: 'RUN_ID', value: "${env.BUILD_NUMBER}-${i}")],
                              wait: false
                    }
                }
            }
        }
    }
}
