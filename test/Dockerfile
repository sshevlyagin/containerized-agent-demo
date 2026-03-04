FROM amazon/aws-cli:latest

RUN yum install -y --allowerasing jq curl

COPY test-executor.sh /test-executor.sh
RUN chmod +x /test-executor.sh

ENTRYPOINT ["/bin/bash", "/test-executor.sh"]
