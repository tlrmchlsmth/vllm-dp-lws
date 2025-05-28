set dotenv-load

NAMESPACE := "$NAMESPACE"
HF_TOKEN := "$HF_TOKEN"
GH_TOKEN := "$GH_TOKEN"
MODEL := "$MODEL"

logs POD:
    kubectl logs -f {{POD}} | grep -v "GET /metrics HTTP/1.1"

hf-token:
  kubectl create secret generic hf-secret --from-literal=HF_TOKEN={{HF_TOKEN}} -n {{NAMESPACE}}
gh-token:
    kubectl create secret generic gh-token-secret --from-literal=GH_TOKEN={{GH_TOKEN}} -n {{NAMESPACE}}

#FIXME(tms): need a generic get-pods command
get-ips:
    just get-pods | awk '/^redhatai-llama-4-maverick-17b-128e-instruct-fp8-(decode|prefill)/ {print $6}'
get-pods:
    kubectl get pods -n {{NAMESPACE}} -o wide


[working-directory: 'llm-d-deployer/quickstart']
install VALUES="values.yaml":
    ./llmd-installer.sh \
        --namespace {{NAMESPACE}} \
        --storage-class shared-vast --storage-size 300Gi \
        --values-file $PWD/../../{{VALUES}}

start VALUES="values.yaml": 
    just install {{VALUES}} && \
    just hf-token {{HF_TOKEN}} && \
    just start-bench

[working-directory: 'llm-d-deployer/quickstart']
uninstall VALUES="values.yaml":
    ./llmd-installer.sh \
        --namespace {{NAMESPACE}} \
        --storage-class shared-vast  --storage-size 300Gi \
        --values-file $PWD/../../{{VALUES}} \
        --uninstall

# Interactive benchmark commands:
start-bench:
    kubectl apply -n {{NAMESPACE}} -f benchmark-interactive-pod.yaml

delete-bench:
    kubectl delete pod -n {{NAMESPACE}} benchmark-interactive

exec-bench:
    kubectl cp reset_prefixes.sh {{NAMESPACE}}/benchmark-interactive:/app/reset_prefixes.sh && \
    echo "MODEL := \"{{MODEL}}\"" > .Justfile.remote.tmp && \
    cat Justfile.remote >> .Justfile.remote.tmp && \
    kubectl cp .Justfile.remote.tmp {{NAMESPACE}}/benchmark-interactive:/app/Justfile && \
    kubectl exec -it -n {{NAMESPACE}} benchmark-interactive -- /bin/bash

init-scripts-configmap:
  kubectl create configmap vllm-init-scripts-config \
    --from-file=init-vllm.sh \
    --namespace={{NAMESPACE}} \
    --dry-run=client -o yaml > init-scripts-cm.yaml && \
  kubectl apply -f init-scripts-cm.yaml \
    --namespace={{NAMESPACE}}

