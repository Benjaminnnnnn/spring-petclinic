pipeline {
    agent any

    environment {
        SONAR_HOST_URL = "http" + "://sonarqube:9000"
        DAST_API_BASE = "http" + "://burpsuite:8090"
        DAST_API_KEY = 'burp-api-key'
        APP_NAME = 'spring-petclinic'
        APP_TEST_PORT = '8082'
        DEPLOY_HOST = "${env.PRODUCTION_VM_HOST ?: ''}"
        DEPLOY_USER = "${env.PRODUCTION_VM_USER ?: 'deployer'}"
        DEPLOY_SSH_PORT = "${env.PRODUCTION_VM_SSH_PORT ?: '22'}"
        DEPLOY_APP_PORT = "${env.PRODUCTION_VM_APP_PORT ?: '8080'}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                    env.BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    env.ARTIFACT_PATH = sh(
                        script: "find target -maxdepth 1 -name '*.jar' ! -name 'original-*.jar' | head -n 1",
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Build') {
            steps {
                sh '''
                    chmod +x mvnw
                    ./mvnw -B clean package -DskipTests
                '''
                script {
                    env.ARTIFACT_PATH = sh(
                        script: "find target -maxdepth 1 -name '*.jar' ! -name 'original-*.jar' | head -n 1",
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Unit Tests') {
            steps {
                sh './mvnw -B test jacoco:report -Dspring.docker.compose.host=host.docker.internal'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
                    publishHTML(target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'target/site/jacoco',
                        reportFiles: 'index.html',
                        reportName: 'JaCoCo Coverage Report'
                    ])
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        ./mvnw -B sonar:sonar \
                            -Dsonar.projectKey=${APP_NAME} \
                            -Dsonar.projectName=${APP_NAME} \
                            -Dsonar.host.url=${SONAR_HOST_URL} \
                            -Dsonar.login=${SONAR_AUTH_TOKEN}
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    ./mvnw -B spring-boot:build-image \
                        -DskipTests \
                        -Dspring-boot.build-image.imageName=${APP_NAME}:${BUILD_VERSION}
                    docker tag ${APP_NAME}:${BUILD_VERSION} ${APP_NAME}:latest
                '''
            }
        }

        stage('Prepare Target for Dynamic Application Security Testing') {
            steps {
                sh '''
                    APP_HEALTH_URL=$(printf 'http%s%s' '://' "localhost:${APP_TEST_PORT}/actuator/health")

                    if [ -f .petclinic-app.pid ]; then
                      kill "$(cat .petclinic-app.pid)" || true
                      rm -f .petclinic-app.pid
                    fi

                    nohup java -jar "${ARTIFACT_PATH}" --server.port=${APP_TEST_PORT} > app.log 2>&1 &
                    echo $! > .petclinic-app.pid

                    for attempt in $(seq 1 30); do
                      if curl -fsS "${APP_HEALTH_URL}" > /dev/null; then
                        exit 0
                      fi
                      sleep 2
                    done

                    echo "Application failed to start for DAST" >&2
                    exit 1
                '''
            }
        }

        stage('Dynamic Application Security Testing - Burp Suite-Compatible') {
            steps {
                sh '''
                    TARGET_URL=$(printf 'http%s%s' '://' "jenkins:${APP_TEST_PORT}")
                    chmod +x burp/zap-api-scan.sh
                    burp/zap-api-scan.sh \
                        "${TARGET_URL}" \
                        "${DAST_API_BASE}" \
                        "${DAST_API_KEY}" \
                        "build/reports/dast"
                '''
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'build/reports/dast',
                        reportFiles: 'zap-report.html',
                        reportName: 'Burp-Compatible DAST Report'
                    ])
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'build/reports/dast/*'
                }
            }
        }

        stage('Deploy to Production VM') {
            when {
                expression {
                    return env.DEPLOY_HOST?.trim()
                }
            }
            steps {
                writeFile file: 'ansible/inventory.ini', text: """
[production]
${DEPLOY_HOST} ansible_user=${DEPLOY_USER} ansible_port=${DEPLOY_SSH_PORT} ansible_python_interpreter=/usr/bin/python3
"""
                ansiblePlaybook(
                    playbook: 'ansible/deploy-playbook.yml',
                    inventory: 'ansible/inventory.ini',
                    extras: "-e app_version=${BUILD_VERSION} -e app_name=${APP_NAME} -e app_port=${DEPLOY_APP_PORT}",
                    colorized: true
                )
            }
        }

        stage('Verify Deployment') {
            when {
                expression {
                    return env.DEPLOY_HOST?.trim()
                }
            }
            steps {
                sh '''
                    DEPLOY_URL=$(printf 'http%s%s' '://' "${DEPLOY_HOST}:${DEPLOY_APP_PORT}")
                    for attempt in $(seq 1 30); do
                      if curl -fsS "${DEPLOY_URL}" | grep -q "Welcome"; then
                        exit 0
                      fi
                      sleep 2
                    done

                    echo "Unable to verify the deployed welcome page" >&2
                    exit 1
                '''
            }
        }
    }

    post {
        always {
            sh '''
                if [ -f .petclinic-app.pid ]; then
                  kill "$(cat .petclinic-app.pid)" || true
                  rm -f .petclinic-app.pid
                fi
            '''
            archiveArtifacts allowEmptyArchive: true, artifacts: 'target/*.jar,app.log'
            cleanWs deleteDirs: true
        }
        success {
            echo "Pipeline completed successfully."
        }
        failure {
            echo "Pipeline failed."
        }
    }
}
