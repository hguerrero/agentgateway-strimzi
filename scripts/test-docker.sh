#!/usr/bin/env bash
# Alternative to test.sh for hosts without kafkactl: produce and consume through the gateway
# with the Kafka CLI in a container (no port-forward).
# The container reaches the host, where kind publishes 9094, with --add-host for the
# *.kafka.localtest.me names.
set -euo pipefail

CTX=kind-kafka-tlsroute
BOOTSTRAP=bootstrap.kafka.localtest.me:9094
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

kubectl --context $CTX -n kafka get secret my-cluster-cluster-ca-cert \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > "$DIR/ca.crt"
cat > "$DIR/client.properties" <<PROPS
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/work/ca.crt
PROPS

kafka() {
  docker run --rm -i -v "$DIR:/work" \
    --add-host bootstrap.kafka.localtest.me:host-gateway \
    --add-host broker-0.kafka.localtest.me:host-gateway \
    --entrypoint "/opt/kafka/bin/$1" apache/kafka:4.0.0 "${@:2}"
}

kafka kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /work/client.properties \
  --create --if-not-exists --topic demo
echo "hello through agentgateway" | kafka kafka-console-producer.sh \
  --bootstrap-server $BOOTSTRAP --producer.config /work/client.properties --topic demo
kafka kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --consumer.config /work/client.properties \
  --topic demo --from-beginning --max-messages 1 --timeout-ms 30000
