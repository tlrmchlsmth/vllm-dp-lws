set dotenv-load
set dotenv-required

NAMESPACE := "$NAMESPACE"
HF_TOKEN := "$HF_TOKEN"
GH_TOKEN := "$GH_TOKEN"

#MODEL := "deepseek-ai/DeepSeek-R1-0528"
#MODEL := "deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct"
#MODEL := "Qwen/Qwen3-235B-A22B-FP8"
MODEL := "Qwen/Qwen3-30B-A3B-FP8"

KN := "kubectl -n $NAMESPACE"

# Print table of nodes on Coreweave. Quiet recipe since the command is messy
@cks_nodes:
  kubectl get nodes -o=custom-columns="NAME:metadata.name,IP:status.addresses[?(@.type=='InternalIP')].address,TYPE:metadata.labels['node\.coreweave\.cloud\/type'],LINK:metadata.labels['ethernet\.coreweave\.cloud/speed'],READY:status.conditions[?(@.type=='Ready')].status,CORDON:spec.unschedulable,TAINT:spec.taints[?(@.key=='qos.coreweave.cloud/interruptable')].effect,RELIABILITY:metadata.labels['node\.coreweave\.cloud\/reliability'],LG:metadata.labels['ib\.coreweave\.cloud\/leafgroup'],VERSION:metadata.labels['node\.coreweave\.cloud\/version'],IB:metadata.labels['ib\.coreweave\.cloud\/speed'],STATE:metadata.labels['node\.coreweave\.cloud\/state'],RESERVED:metadata.labels['node\.coreweave\.cloud\/reserved']"

gpu_pods:
  kubectl get pods -A \
  -o=custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,GPUs:.spec.containers[*].resources.requests.nvidia\.com/gpu' \
  | grep -v '<none>'


logs POD:
  kubectl logs -f {{POD}} | grep -v "GET /metrics HTTP/1.1"

install:
  kubectl create namespace {{NAMESPACE}} \
  && kubectl create secret generic hf-secret --from-literal=HF_TOKEN={{HF_TOKEN}} -n {{NAMESPACE}} \
  && kubectl create secret generic gh-token-secret --from-literal=GH_TOKEN={{GH_TOKEN}} -n {{NAMESPACE}} \
  && {{KN}} apply -f state/hf-cache.yaml \
  && {{KN}} apply -f state/vllm.yaml

uninstall:
  just stop \
  && kubectl delete namespace {{NAMESPACE}} --ignore-not-found

create-configmaps:
  {{KN}} create configmap vllm-init-scripts-config \
    --from-file=install-scripts/ \
    --dry-run=client -o yaml > .tmp/init-scripts-cm.yaml.tmp \
  && {{KN}} apply -f .tmp/init-scripts-cm.yaml.tmp

rm-configmaps:
  {{KN}} create configmap vllm-init-scripts-config \
    --from-file=install-scripts/ \
    --dry-run=client -o yaml > .tmp/init-scripts-cm.yaml.tmp \

build-vllm:
  just create-configmaps \
  && {{KN}} apply -f vllm-builder.yaml

start:
  mkdir -p ./.tmp \
  && just create-configmaps \
  && sed -e 's#__SERVICE_NAME__#vllm-leader#g' \
         -e 's#__LWS_NAME__#vllm#g' \
         -e 's#__MODEL__#{{MODEL}}#g' lws.yaml \
      > .tmp/lws.yaml.tmp \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote.tmp \
  && sed -e 's#__BASE_URL__#\"http://vllm-leader:8080\"#g' Justfile.remote >> .tmp/Justfile.remote.tmp \
  && {{KN}} apply -f .tmp/lws.yaml.tmp \
  && {{KN}} apply -f benchmark-interactive-pod.yaml

start-pd:
  mkdir -p ./.tmp \
  && just create-configmaps \
  && sed -e 's#__SERVICE_NAME__#vllm-prefill-leader#g' \
         -e 's#__LWS_NAME__#vllm-prefill#g' \
         -e 's#__MODEL__#{{MODEL}}#g' lws.yaml \
      > .tmp/lws.prefill.yaml.tmp \
  && sed -e 's#__SERVICE_NAME__#vllm-decode-leader#g' \
         -e 's#__LWS_NAME__#vllm-decode#g' \
         -e 's#__MODEL__#"{{MODEL}}"#g' lws.yaml \
      > .tmp/lws.decode.yaml.tmp \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote.tmp \
  && sed -e 's#__BASE_URL__#\"http://toy-proxy-service:8080\"#g' Justfile.remote >> .tmp/Justfile.remote.tmp \
  && {{KN}} apply -f .tmp/lws.prefill.yaml.tmp \
  && {{KN}} apply -f .tmp/lws.decode.yaml.tmp \
  && {{KN}} apply -f benchmark-interactive-pod.yaml \
  && {{KN}} apply -f proxy/toy-proxy-deployment.yaml \
  && {{KN}} apply -f proxy/toy-proxy-service.yaml

stop:
  {{KN}} delete leaderworkerset.leaderworkerset.x-k8s.io/vllm --ignore-not-found \
  && {{KN}} delete service vllm-leader --ignore-not-found \
  && {{KN}} delete pod --all \
    --grace-period=0 \
    --force \
  && {{KN}} delete configmap vllm-init-scripts-config --ignore-not-found \
  && {{KN}} delete --now deployment toy-llm-proxy --ignore-not-found

restart:
  just stop; just start 

restart-pd:
  just stop; just start-pd

# TODO: It would be nicer to copy during install-pd if possible
exec-bench:
    kubectl cp .tmp/Justfile.remote.tmp {{NAMESPACE}}/benchmark-interactive:/app/Justfile \
    && {{KN}} exec -it benchmark-interactive -- /bin/bash
