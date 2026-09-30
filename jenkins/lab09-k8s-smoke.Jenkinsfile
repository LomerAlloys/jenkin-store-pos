pipeline {
    agent { label 'k8s-node' }
    stages {
        stage('Where am I?') {
            steps {
                container('node') {
                    sh 'hostname; node --version; cat /etc/os-release | head -2'
                }
            }
        }
    }
}
