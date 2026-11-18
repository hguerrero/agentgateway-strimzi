#!/usr/bin/env bash
# Produce and consume a message through the gateway from the host with kafkactl (no port-forward).
# Install kafkactl: brew install deviceinsight/packages/kafkactl
# Config: ../.kafkactl.yml (context "agentgateway"), which needs ../ca.crt
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl --context kind-kafka-tlsroute -n kafka get secret my-cluster-cluster-ca-cert \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

kafkactl --context agentgateway get brokers # advertised address is broker-0.kafka.localtest.me:9094
kafkactl --context agentgateway delete topic demo 2>/dev/null || true # make reruns start clean
kafkactl --context agentgateway create topic demo
echo "hello through agentgateway" | kafkactl --context agentgateway produce demo
kafkactl --context agentgateway consume demo --from-beginning --exit
