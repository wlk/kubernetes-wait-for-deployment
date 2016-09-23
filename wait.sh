#!/bin/bash
# Waits for a deployment to complete.
#
# Includes a three-steps approach:
#
# 1. Wait for the observed generation to match the specified one.
# 2. Wait for the expected number of available replicas to match the specified one.
# 3. Wait for the expected number of available pods to be in 'Ready' state
#
# Spawn from the answer to this StackOverflow question: http://stackoverflow.com/questions/37448357/ensure-kubernetes-deployment-has-completed-and-all-pods-are-updated-and-availabl
#
set -o errexit
set -o pipefail

DEFAULT_TIMEOUT=60

monitor_timeout() {
  sleep ${timeout}
  echo "Timeout ${timeout} exceeded" >&2
  kill $1
}

get_generation() {
  get_deployment_jsonpath '{.metadata.generation}'
}

get_observed_generation() {
  get_deployment_jsonpath '{.status.observedGeneration}'
}

get_replicas() {
  get_deployment_jsonpath '{.spec.replicas}'
}

get_available_replicas() {
  get_deployment_jsonpath '{.status.availableReplicas}'
}

get_deployment_jsonpath() {
  local readonly _jsonpath="$1"

  kubectl get deployment "${deployment}" -o "jsonpath=${_jsonpath}"
}

get_statuses_for_deployment() {
  kubectl get pods --selector=app=${deployment} -o 'jsonpath={.items[*].status.conditions[*].type}'
}

count_ready_pods() {
  get_statuses_for_deployment | tr ' ' '\n' | grep Ready | wc -l
}


if [[ $# -lt 1 ]]; then
  echo "usage: $(basename $0) <deployment> [timeout]" >&2
  exit 1
fi

if [[ $2 -gt 0 ]]; then
  export timeout=$2
else 
  export timeout=$DEFAULT_TIMEOUT
fi

echo "Waiting for deployment with timeout: ${timeout} seconds"

monitor_timeout $$ &
readonly timeout_monitor_pid=$!

readonly deployment="$1"

readonly generation=$(get_generation)
echo "Waiting for specified generation: ${generation} for deployment ${deployment} to be observed"

current_generation=$(get_observed_generation)
while [[ ${current_generation} -lt ${generation} ]]; do
  sleep .5
  echo "Current generation: ${current_generation}, expected generation: ${generation}, waiting"
  current_generation=$(get_observed_generation)
done
echo "Observed expected generation: ${generation}"

readonly replicas="$(get_replicas)"
echo "Expected replicas: ${replicas}"

available=$(get_available_replicas)
while [[ ${available} -lt ${replicas} ]]; do
  sleep .5
  echo "Available replicas: ${available}, waiting"
  available=$(get_available_replicas)
done
echo "Observed expected number of availabe replicas: ${available}"

ready_pods=$(count_ready_pods)
while [[ ${ready_pods} -lt ${replicas} ]]; do
  sleep .5
  echo "Ready pods: ${ready_pods}, expected pods to be ready: ${replicas}, waiting"
  ready_pods=$(count_ready_pods)
done

kill ${timeout_monitor_pid} #Stop timeout monitor
echo "Deployment of service ${deployment} successful. All ${ready_pods} ready"
