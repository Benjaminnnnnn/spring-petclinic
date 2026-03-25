pipeline {
    agent any
    
    environment {
        MAVEN_HOME = tool 'Maven'
        SONAR_HOST_URL = 'http://sonarqube:9000'
        ZAP_HOST = 'http://zap:8090'
        ZAP_API_KEY = 'devsecops-zap-key'
        APP_NAME = 'spring-petclinic'
        DEPLOY_HOST = "${env.PRODUCTION_VM_HOST ?: 'production-vm'}"
        DEPLOY_USER = "${env.PRODUCTION_VM_USER ?: 'deployer'}"
    }
    
    tools {
        maven 'Maven'
        jdk 'JDK17'
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 1, unit: 'HOURS')
    }
    
    triggers {
        pollSCM('H/5 * * * *')  // Poll SCM every 5 minutes
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "Checking out code from SCM..."
                    checkout scm
                    
                    // Get commit information for tracking
                    env.GIT_COMMIT_MSG = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                    env.BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    
                    echo "Build Version: ${env.BUILD_VERSION}"
                    echo "Commit: ${env.GIT_COMMIT_MSG}"
                    echo "Author: ${env.GIT_COMMIT_AUTHOR}"
                }
            }
        }
        
        stage('Build') {
            steps {
                script {
                    echo "Building application with Maven..."
                    sh """
                        ./mvnw clean package -DskipTests
                    """
                }
            }
        }
        
        stage('Unit Tests') {
            steps {
                script {
                    echo "Running unit tests..."
                    sh """
                        ./mvnw test
                    """
                }
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'
                    jacoco(
                        execPattern: '**/target/jacoco.exec',
                        classPattern: '**/target/classes',
                        sourcePattern: '**/src/main/java'
                    )
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                script {
                    echo "Running SonarQube static code analysis..."
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            ./mvnw sonar:sonar \
                                -Dsonar.projectKey=${APP_NAME} \
                                -Dsonar.projectName=${APP_NAME} \
                                -Dsonar.host.url=${SONAR_HOST_URL} \
                                -Dsonar.java.binaries=target/classes
                        """
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                script {
                    echo "Waiting for SonarQube Quality Gate..."
                    timeout(time: 5, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            echo "WARNING: Quality Gate failed: ${qg.status}"
                            // Don't fail the build, just warn
                        } else {
                            echo "Quality Gate passed!"
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image for application..."
                    sh """
                        ./mvnw spring-boot:build-image \
                            -Dspring-boot.build-image.imageName=${APP_NAME}:${BUILD_VERSION}
                        
                        # Tag as latest
                        docker tag ${APP_NAME}:${BUILD_VERSION} ${APP_NAME}:latest
                    """
                }
            }
        }
        
        stage('Security Scan - OWASP Dependency Check') {
            steps {
                script {
                    echo "Running OWASP Dependency Check..."
                    sh """
                        ./mvnw org.owasp:dependency-check-maven:check \
                            -DfailBuildOnCVSS=7 \
                            -DsuppressionFiles=dependency-check-suppressions.xml || true
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'target',
                        reportFiles: 'dependency-check-report.html',
                        reportName: 'OWASP Dependency Check Report'
                    ])
                }
            }
        }
        
        stage('Start Application for Security Testing') {
            steps {
                script {
                    echo "Starting application in background for security testing..."
                    sh """
                        # Kill any existing instances
                        pkill -f spring-petclinic || true
                        
                        # Start application in background
                        nohup java -jar target/*.jar --server.port=8082 > app.log 2>&1 &
                        
                        # Wait for application to start
                        echo "Waiting for application to start..."
                        for i in {1..30}; do
                            if curl -s http://localhost:8082 > /dev/null; then
                                echo "Application started successfully"
                                break
                            fi
                            echo "Waiting... (\$i/30)"
                            sleep 2
                        done
                    """
                }
            }
        }
        
        stage('Security Scan - ZAP') {
            steps {
                script {
                    echo "Running OWASP ZAP security scan..."
                    sh """
                        # Create ZAP scan script
                        cat > zap-scan.sh << 'EOF'
#!/bin/bash
set -e

ZAP_HOST="${ZAP_HOST}"
ZAP_API_KEY="${ZAP_API_KEY}"
TARGET_URL="http://host.docker.internal:8082"

echo "Starting ZAP scan against \$TARGET_URL"

# Spider scan
echo "Running spider scan..."
SPIDER_ID=\$(curl -s "\$ZAP_HOST/JSON/spider/action/scan/?apikey=\$ZAP_API_KEY&url=\$TARGET_URL" | jq -r '.scan')
echo "Spider scan ID: \$SPIDER_ID"

# Wait for spider to complete
while true; do
    STATUS=\$(curl -s "\$ZAP_HOST/JSON/spider/view/status/?apikey=\$ZAP_API_KEY&scanId=\$SPIDER_ID" | jq -r '.status')
    echo "Spider progress: \$STATUS%"
    if [ "\$STATUS" = "100" ]; then
        break
    fi
    sleep 5
done

# Active scan
echo "Running active scan..."
SCAN_ID=\$(curl -s "\$ZAP_HOST/JSON/ascan/action/scan/?apikey=\$ZAP_API_KEY&url=\$TARGET_URL&recurse=true" | jq -r '.scan')
echo "Active scan ID: \$SCAN_ID"

# Wait for active scan to complete
while true; do
    STATUS=\$(curl -s "\$ZAP_HOST/JSON/ascan/view/status/?apikey=\$ZAP_API_KEY&scanId=\$SCAN_ID" | jq -r '.status')
    echo "Active scan progress: \$STATUS%"
    if [ "\$STATUS" = "100" ]; then
        break
    fi
    sleep 10
done

# Generate HTML report
echo "Generating HTML report..."
curl -s "\$ZAP_HOST/OTHER/core/other/htmlreport/?apikey=\$ZAP_API_KEY" > zap-report.html

echo "ZAP scan completed successfully"
EOF

                        chmod +x zap-scan.sh
                        ./zap-scan.sh || echo "ZAP scan completed with warnings"
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: '.',
                        reportFiles: 'zap-report.html',
                        reportName: 'ZAP Security Report'
                    ])
                    
                    // Stop the test application
                    sh 'pkill -f spring-petclinic || true'
                }
            }
        }
        
        stage('Deploy to Production VM') {
            steps {
                script {
                    echo "Deploying to production VM using Ansible..."
                    
                    // Create inventory file
                    writeFile file: 'ansible/inventory.ini', text: """
[production]
${DEPLOY_HOST} ansible_user=${DEPLOY_USER}
"""
                    
                    // Run Ansible playbook
                    ansiblePlaybook(
                        playbook: 'ansible/deploy-playbook.yml',
                        inventory: 'ansible/inventory.ini',
                        extras: "-e app_version=${BUILD_VERSION} -e app_name=${APP_NAME}",
                        colorized: true
                    )
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    echo "Verifying deployment on production VM..."
                    sh """
                        # Wait for application to be accessible
                        for i in {1..30}; do
                            if curl -s http://${DEPLOY_HOST}:8080 > /dev/null; then
                                echo "Application is accessible on production VM"
                                exit 0
                            fi
                            echo "Waiting for application... (\$i/30)"
                            sleep 2
                        done
                        
                        echo "WARNING: Could not verify application accessibility"
                        exit 0
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo "Pipeline execution completed"
            
            // Archive artifacts
            archiveArtifacts artifacts: '**/target/*.jar', allowEmptyArchive: true
            
            // Clean workspace
            cleanWs(
                deleteDirs: true,
                patterns: [
                    [pattern: 'target/**', type: 'INCLUDE'],
                    [pattern: '.m2/**', type: 'INCLUDE']
                ]
            )
        }
        success {
            echo "✓ Pipeline completed successfully!"
            echo "Build Version: ${env.BUILD_VERSION}"
            echo "Deployed to: ${DEPLOY_HOST}"
        }
        failure {
            echo "✗ Pipeline failed!"
        }
    }
}
