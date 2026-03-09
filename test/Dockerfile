FROM amazon/aws-cli:latest

# When building inside the Docker sandbox, sandbox/test.sh places the MITM
# proxy CA cert here. The glob makes COPY a no-op when the file is absent.
COPY proxy-ca.cr[t] /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust

RUN yum install -y --allowerasing jq curl

COPY test-executor.sh /test-executor.sh
RUN chmod +x /test-executor.sh

ENTRYPOINT ["/bin/bash", "/test-executor.sh"]
