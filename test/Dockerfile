FROM amazon/aws-cli:latest

RUN yum install -y --allowerasing jq curl

# Proxy CA cert (empty placeholder — sandbox/test.sh replaces with real cert at runtime)
COPY proxy-ca.crt /etc/pki/ca-trust/source/anchors/proxy-ca.crt
RUN update-ca-trust

COPY test-executor.sh /test-executor.sh
RUN chmod +x /test-executor.sh

ENTRYPOINT ["/bin/bash", "/test-executor.sh"]
