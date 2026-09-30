// Lab 08 — one-time host bootstrap (job: lab08-bootstrap, Script Path: infra/bootstrap.Jenkinsfile)
// Runs directly on the jenkins-agent (it has the Docker CLI + host socket), so it can
// manage host containers without anyone typing PowerShell:
//   Part A3: start LocalStack on jenkins-net
//   Part A4: create the versioned remote-state bucket
//   Part A5: list AMIs and smoke-test one EC2 instance
pipeline {
    agent { label 'linux-build' }

    parameters {
        booleanParam(name: 'RECREATE_LOCALSTACK', defaultValue: false,
                     description: 'Remove and recreate the localstack container (wipes the state bucket!)')
        booleanParam(name: 'SMOKE_TEST_EC2', defaultValue: true,
                     description: 'Launch + terminate one test instance to check the Docker VM manager')
    }

    environment {
        PATH = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        LS_IMAGE = 'localstack/localstack:latest'
        BUCKET   = 'taskflow-tfstate'
    }

    options { timeout(time: 20, unit: 'MINUTES') }

    stages {
        stage('Start LocalStack') {
            steps {
                withCredentials([string(credentialsId: 'localstack-auth-token', variable: 'LOCALSTACK_AUTH_TOKEN')]) {
                    sh '''
                        if [ "$RECREATE_LOCALSTACK" = "true" ]; then docker rm -f localstack || true; fi
                        if [ -z "$(docker ps -aq --filter name=^localstack$)" ]; then
                            docker pull "$LS_IMAGE"
                            docker run -d --name localstack --restart unless-stopped \
                              --network jenkins-net \
                              -p 127.0.0.1:4566:4566 \
                              -e LOCALSTACK_AUTH_TOKEN \
                              -e EC2_VM_MANAGER=docker \
                              -e "EC2_DOCKER_FLAGS=--network jenkins-net --privileged" \
                              -v /var/run/docker.sock:/var/run/docker.sock \
                              "$LS_IMAGE"
                        else
                            docker start localstack >/dev/null
                        fi
                        docker image inspect "$LS_IMAGE" --format 'LocalStack image digest: {{index .RepoDigests 0}}' || true
                    '''
                }
                sh '''
                    for i in $(seq 1 60); do
                        if { curl -sf http://localstack:4566/_localstack/health || docker exec localstack curl -sf http://localhost:4566/_localstack/health; } > health.json 2>/dev/null \
                           && grep -q '"ec2": "\\(available\\|running\\)"' health.json; then
                            echo "LocalStack ready"; cat health.json; echo; exit 0
                        fi
                        sleep 3
                    done
                    echo "LocalStack did not become healthy"; docker logs --tail 80 localstack; exit 1
                '''
            }
        }

        stage('State Bucket') {
            steps {
                sh '''
                    docker exec localstack awslocal s3api head-bucket --bucket "$BUCKET" 2>/dev/null \
                      || docker exec localstack awslocal s3 mb "s3://$BUCKET"
                    docker exec localstack awslocal s3api put-bucket-versioning --bucket "$BUCKET" \
                      --versioning-configuration Status=Enabled
                    docker exec localstack awslocal s3api get-bucket-versioning --bucket "$BUCKET"
                    docker exec localstack awslocal s3 ls
                '''
            }
        }

        stage('List AMIs') {
            steps {
                sh 'docker exec localstack awslocal ec2 describe-images --query "Images[].[ImageId,Name]" --output table | tee amis.txt'
            }
            post { always { archiveArtifacts artifacts: 'amis.txt', allowEmptyArchive: true } }
        }

        stage('EC2 Smoke Test') {
            when { expression { params.SMOKE_TEST_EC2 } }
            steps {
                sh '''
                    AMI=$(docker exec localstack awslocal ec2 describe-images \
                          --query "Images[?contains(Name, 'ubuntu') || contains(Name, 'Ubuntu')] | [0].ImageId" --output text)
                    echo "Using AMI $AMI"
                    ID=$(docker exec localstack awslocal ec2 run-instances --image-id "$AMI" --instance-type t3.micro \
                          --query "Instances[0].InstanceId" --output text)
                    echo "Instance: $ID"
                    sleep 15
                    docker exec localstack awslocal ec2 describe-instances --instance-ids "$ID" \
                      --query "Reservations[0].Instances[0].[State.Name,PublicIpAddress,PrivateIpAddress]" --output text
                    echo "=== containers (look for the instance container) ==="
                    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Networks}}'
                    echo "=== filter by instance id ==="
                    docker ps --filter "name=$ID" --format '{{.Names}}\t{{.Networks}}'
                    docker exec localstack awslocal ec2 terminate-instances --instance-ids "$ID" --output text
                '''
            }
        }
    }
}
