#!/bin/bash

######################################################################################
## Installing Prometheus Operator on the server defined in $KUBECONFIG
######################################################################################
function install_prometheus_operator() {
  echo "ℹ️  installing Prometheus Operator on Host cluster in namespace '$TOOLCHAIN_HOST_OPERATOR_NS'..."
  login_to_cluster "host"
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "connecting to $SERVER (Y/n)? " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

  oc process -f config/monitoring/prometheus.tmpl.yaml \
    -p SA_NAME=prometheus-k8s \
    -p NAMESPACE="$TOOLCHAIN_HOST_OPERATOR_NS" \
    | oc apply -f -

  # approve the install plan, stick to Prometheus version 0.32 for now
  echo "approving the installplan..."
  oc patch -n "$TOOLCHAIN_HOST_OPERATOR_NS" "$(oc get installplan -l operators.coreos.com/prometheus.$TOOLCHAIN_HOST_OPERATOR_NS -o name)" --type='merge' -p '{"spec":{"approved":true}}'

  # at this point, there should be some new pods in the `toolchain-$CLUSTER-monitoring` namespace
  echo "✅ done installing Prometheus Operator"
  echo ""
}

######################################################################################
## Deploying Grafana on the server defined in $KUBECONFIG
######################################################################################
function deploy_grafana() {
  echo "🚛 deploying Grafana..."
  
  # fetch route to prometheus on member cluster and retrieve SA token to use to connect to it
  login_to_cluster "member"
  PROMETHEUS_URL_MEMBER="https://$(oc get route/prometheus -n $TOOLCHAIN_MEMBER_OPERATOR_NS -o json | jq -r '.status.ingress[0].host')"
  export PROMETHEUS_URL_MEMBER
  echo "Prometheus route on Member cluster: $PROMETHEUS_URL_MEMBER"
  BEARER_TOKEN_MEMBER="$(oc serviceaccounts get-token prometheus-k8s -n $TOOLCHAIN_MEMBER_OPERATOR_NS)"
  export BEARER_TOKEN_MEMBER
  
  
  # fetch "local" route to thanos on host cluster and retrieve SA token to use to connect to it
  login_to_cluster "host"
  
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_HOST_OPERATOR_NS" \
    -p NAME=grafana \
    | oc apply -f -
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n "$TOOLCHAIN_HOST_OPERATOR_NS"
  
  BEARER_TOKEN_HOST="$(oc serviceaccounts get-token prometheus-k8s -n $TOOLCHAIN_HOST_OPERATOR_NS)"
  export BEARER_TOKEN_HOST

  PROMETHEUS_URL_HOST="http://prometheus-operated.xcoulon-host-operator.svc:9091"
  export PROMETHEUS_URL_HOST
  
  # use the 'oc create' commands along with the 'oc apply' to make sure the resources can be created or updated when they already exist
  oc create configmap -n "$TOOLCHAIN_HOST_OPERATOR_NS" grafana-sandbox-dashboard \
    --from-file=sandbox.json=config/monitoring/sandbox-dashboard.json \
    -o yaml --dry-run=client | oc apply -f - 
  oc process -f config/monitoring/grafana_app.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_HOST_OPERATOR_NS" \
    -p SA_NAME=grafana \
    -p BEARER_TOKEN_HOST="$BEARER_TOKEN_HOST" \
    -p PROMETHEUS_URL_HOST="$PROMETHEUS_URL_HOST" \
    -p BEARER_TOKEN_MEMBER="$BEARER_TOKEN_MEMBER" \
    -p PROMETHEUS_URL_MEMBER="$PROMETHEUS_URL_MEMBER" \
    | oc apply -f -
  echo "✅ done with deploying Grafana on $SERVER"
  echo ""
  echo "🖥 https://$(oc get route/grafana -n $TOOLCHAIN_HOST_OPERATOR_NS -o json | jq -r '.status.ingress[0].host')"
}

######################################################################################
## Login (ie, using the appropriate KUBECONFIG file)
######################################################################################
function login_to_cluster() {
  if [[ $1 == "host" ]]; then
    export KUBECONFIG=$KUBECONFIG_HOST
  elif [[ $1 == "member" ]]; then
    export KUBECONFIG=$KUBECONFIG_MEMBER
  else
    echo "unknown cluster: '$1'"
  fi
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
elif [[ -z ${TOOLCHAIN_HOST_OPERATOR_NS} ]]; then
  echo "Missing 'TOOLCHAIN_HOST_OPERATOR_NS' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_MEMBER_OPERATOR_NS} ]]; then
  echo "Missing 'TOOLCHAIN_MEMBER_OPERATOR_NS' env var"
  exit 1
fi


install_prometheus_operator
deploy_grafana