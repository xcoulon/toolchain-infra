#!/bin/bash

######################################################################################
## Deploying Grafana on the server defined in $KUBECONFIG
######################################################################################
function deploy_grafana() {
  echo "🚛 deploying Grafana..."
  
  # fetch the route to prometheus on member cluster and retrieve SA token to use to connect to it
  export KUBECONFIG=$KUBECONFIG_MEMBER
  PROMETHEUS_URL_MEMBER="https://$(oc get route/prometheus -n $TOOLCHAIN_OPERATOR_NS_MEMBER -o json | jq -r '.status.ingress[0].host')"
  export PROMETHEUS_URL_MEMBER
  echo "Prometheus route on Member cluster: $PROMETHEUS_URL_MEMBER"
 
  # create a `grafana` serviceaccount which is allowed to access Prometheus (via the kube-rbac-proxy)
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE="$NAMESPACE" \
    -p NAME=grafana \
    | oc apply -f -
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n "$NAMESPACE"
  BEARER_TOKEN_MEMBER="$(oc serviceaccounts get-token grafana -n $TOOLCHAIN_OPERATOR_NS_MEMBER)"
  export BEARER_TOKEN_MEMBER
  
  # fetch the "local" route to Grafana on host cluster and retrieve SA token to use to connect to it
  export KUBECONFIG=$KUBECONFIG_HOST
  PROMETHEUS_URL_HOST="https://prometheus-operated.$TOOLCHAIN_OPERATOR_NS_HOST.svc:9091"
  export PROMETHEUS_URL_HOST
  echo "Prometheus route on Host cluster: $PROMETHEUS_URL_HOST"
  BEARER_TOKEN_HOST="$(oc serviceaccounts get-token prometheus-k8s -n $TOOLCHAIN_OPERATOR_NS_HOST)"
  export BEARER_TOKEN_HOST

  
  # use the 'oc create' commands along with the 'oc apply' to make sure the resources can be created or updated when they already exist
  oc create configmap -n "$TOOLCHAIN_OPERATOR_NS_HOST" grafana-sandbox-dashboard \
    --from-file=sandbox.json=config/monitoring/sandbox-dashboard.json \
    -o yaml --dry-run=client | oc apply -f - 
  oc process -f config/monitoring/grafana_app.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_OPERATOR_NS_HOST" \
    -p SA_NAME=grafana \
    -p BEARER_TOKEN_HOST="$BEARER_TOKEN_HOST" \
    -p PROMETHEUS_URL_HOST="$PROMETHEUS_URL_HOST" \
    -p BEARER_TOKEN_MEMBER="$BEARER_TOKEN_MEMBER" \
    -p PROMETHEUS_URL_MEMBER="$PROMETHEUS_URL_MEMBER" \
    | oc apply -f -
  echo "✅ done with deploying Grafana on $SERVER"
  echo ""
  echo "🖥 https://$(oc get route/grafana -n $TOOLCHAIN_OPERATOR_NS_HOST -o json | jq -r '.status.ingress[0].host')"
}

######################################################################################
## Main
######################################################################################
if [[ -z ${KUBECONFIG_HOST} ]]; then
  echo "Missing 'KUBECONFIG_HOST' env var"
  exit 1
elif [[ -z ${KUBECONFIG_MEMBER} ]]; then
  echo "Missing 'KUBECONFIG_MEMBER' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_OPERATOR_NS_HOST} ]]; then
  echo "Missing 'TOOLCHAIN_OPERATOR_NS_HOST' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_OPERATOR_NS_MEMBER} ]]; then
  echo "Missing 'TOOLCHAIN_OPERATOR_NS_MEMBER' env var"
  exit 1
fi

deploy_grafana