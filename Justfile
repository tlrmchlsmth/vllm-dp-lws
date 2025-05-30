set dotenv-load
set dotenv-required

NAMESPACE := "$NAMESPACE"
HF_TOKEN := "$HF_TOKEN"
GH_TOKEN := "$GH_TOKEN"
MODEL := "$MODEL"

KN := "kubectl -n $NAMESPACE"

logs POD:
  kubectl logs -f {{POD}} | grep -v "GET /metrics HTTP/1.1"

install:
  kubectl create namespace {{NAMESPACE}} && \
  kubectl create secret generic hf-secret --from-literal=HF_TOKEN={{HF_TOKEN}} -n {{NAMESPACE}} && \
  kubectl create secret generic gh-token-secret --from-literal=GH_TOKEN={{GH_TOKEN}} -n {{NAMESPACE}} && \
  {{KN}} create configmap vllm-init-scripts-config \
    --from-file=init-vllm.sh \
    --dry-run=client -o yaml > .init-scripts-cm.yaml.tmp && \
  {{KN}} apply -f .init-scripts-cm.yaml.tmp && \
  rm .init-scripts-cm.yaml.tmp && \
  {{KN}} apply -f lws.yaml && \
  {{KN}} apply -f benchmark-interactive-pod.yaml


uninstall:
  {{KN}} delete leaderworkerset.leaderworkerset.x-k8s.io/vllm ; \
  {{KN}} delete service vllm ; \
  {{KN}} delete service vllm-leader ; \
  {{KN}} delete pod vllm-0 vllm-0-1 \
    --grace-period=0 \
    --force \
  {{KN}} delete configmap init-scripts-cm ; \
  {{KN}} delete pod benchmark-interactive ; \
  kubectl delete namespace {{NAMESPACE}} ; \
  echo "Uninstall Complete."

reinstall:
  just uninstall; just install

exec-bench:
    echo "MODEL := \"{{MODEL}}\"" > .Justfile.remote.tmp && \
    cat Justfile.remote >> .Justfile.remote.tmp && \
    kubectl cp .Justfile.remote.tmp {{NAMESPACE}}/benchmark-interactive:/app/Justfile && \
    rm .Justfile.remote.tmp && \
    {{KN}} exec -it benchmark-interactive -- /bin/bash
