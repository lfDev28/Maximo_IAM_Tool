FROM docker.io/bitnami/kubectl:1.29

USER root
RUN install_packages gettext-base \
  && mkdir -p /deploy/manifests \
  && chmod -R 755 /deploy
COPY install.sh /deploy/install.sh
COPY manifests /deploy/manifests
RUN chmod +x /deploy/install.sh

USER 1001
ENTRYPOINT ["/deploy/install.sh"]
