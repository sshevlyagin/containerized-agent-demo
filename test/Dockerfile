FROM amazon/aws-cli:latest

# Proxy CA cert (empty placeholder — sandbox/test.sh replaces with real cert at runtime)
# Must be trusted BEFORE yum so HTTPS through MITM proxy works
COPY proxy-ca.crt /etc/pki/ca-trust/source/anchors/proxy-ca.crt
RUN update-ca-trust

RUN yum install -y --allowerasing jq curl

COPY test-executor.sh /test-executor.sh
RUN chmod +x /test-executor.sh

ENTRYPOINT ["/bin/bash", "/test-executor.sh"]
