FROM jenkins/jenkins:lts-jdk17

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends ansible curl docker.io docker-cli docker-compose git jq openssh-client \
 && mkdir -p /usr/local/lib/docker/cli-plugins \
 && ln -sf /usr/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
