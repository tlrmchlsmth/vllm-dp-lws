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
  mkdir -p ./.tmp \
  && kubectl create namespace {{NAMESPACE}} \
  && kubectl create secret generic hf-secret --from-literal=HF_TOKEN={{HF_TOKEN}} -n {{NAMESPACE}} \
  && kubectl create secret generic gh-token-secret --from-literal=GH_TOKEN={{GH_TOKEN}} -n {{NAMESPACE}} \
  && {{KN}} create configmap vllm-init-scripts-config \
    --from-file=init-vllm.sh \
    --dry-run=client -o yaml > .tmp/init-scripts-cm.yaml.tmp \
  && {{KN}} apply -f .tmp/init-scripts-cm.yaml.tmp \
  && sed -e 's/__SERVICE_NAME__/vllm-leader/g' \
         -e 's/__LWS_NAME__/vllm/g' lws.yaml \
      > .tmp/lws.yaml.tmp \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote.tmp \
  && sed -e 's/__BASE_URL__/\"http:\/\/vllm-leader:8080\"/g' Justfile.remote >> .tmp/Justfile.remote.tmp \
  && {{KN}} apply -f .tmp/lws.yaml.tmp \
  && {{KN}} apply -f benchmark-interactive-pod.yaml \
  && echo "Installation Complete."

install-pd:
  mkdir -p ./.tmp \
  && kubectl create namespace {{NAMESPACE}} \
  && kubectl create secret generic hf-secret --from-literal=HF_TOKEN={{HF_TOKEN}} -n {{NAMESPACE}} \
  && kubectl create secret generic gh-token-secret --from-literal=GH_TOKEN={{GH_TOKEN}} -n {{NAMESPACE}} \
  && {{KN}} create configmap vllm-init-scripts-config \
    --from-file=init-vllm.sh \
    --dry-run=client -o yaml > .tmp/init-scripts-cm.yaml.tmp \
  && {{KN}} apply -f .tmp/init-scripts-cm.yaml.tmp \
  && sed -e 's/__SERVICE_NAME__/vllm-prefill-leader/g' \
         -e 's/__LWS_NAME__/vllm-prefill/g' lws.yaml \
      > .tmp/lws.prefill.yaml.tmp \
  && sed -e 's/__SERVICE_NAME__/vllm-decode-leader/g' \
         -e 's/__LWS_NAME__/vllm-decode/g' lws.yaml \
      > .tmp/lws.decode.yaml.tmp \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote.tmp \
  && sed -e 's/__BASE_URL__/\"http:\/\/toy-proxy-service:8080\"/g' Justfile.remote >> .tmp/Justfile.remote.tmp \
  && {{KN}} apply -f .tmp/lws.prefill.yaml.tmp \
  && {{KN}} apply -f .tmp/lws.decode.yaml.tmp \
  && {{KN}} apply -f benchmark-interactive-pod.yaml \
  && {{KN}} apply -f proxy/toy-proxy-deployment.yaml \
  && {{KN}} apply -f proxy/toy-proxy-service.yaml \
  && echo "Installation Complete."

uninstall:
  {{KN}} delete leaderworkerset.leaderworkerset.x-k8s.io/vllm --ignore-not-found \
  && {{KN}} delete service vllm-leader --ignore-not-found \
  && {{KN}} delete pod --all \
    --grace-period=0 \
    --force \
  && {{KN}} delete configmap vllm-init-scripts-config --ignore-not-found \
  && {{KN}} delete --now deployment toy-llm-proxy --ignore-not-found \
  && kubectl delete namespace {{NAMESPACE}} --ignore-not-found \
  echo "Uninstall Complete."

reinstall:
  just uninstall; just install

reinstall-pd:
  just uninstall; just install-pd

# TODO: It would be nicer to copy during install-pd if possible
exec-bench:
    kubectl cp .tmp/Justfile.remote.tmp {{NAMESPACE}}/benchmark-interactive:/app/Justfile \
    && {{KN}} exec -it benchmark-interactive -- /bin/bash
