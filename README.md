# Kafka ingress with agentgateway TLSRoute

A minimal example: [agentgateway](https://agentgateway.dev) is the ingress for a [Strimzi](https://strimzi.io) Kafka cluster on Kubernetes. Kafka clients on your machine connect to `localhost:9094`. No `kubectl port-forward`.

```
host (kafkactl, any Kafka client)
   │  TLS, SNI = bootstrap.kafka.localtest.me / broker-0.kafka.localtest.me
   ▼
127.0.0.1:9094 ──kind extraPortMappings──▶ node:30094 (NodePort)
   ▼
agentgateway Gateway "kafka-gateway"   listener 9094, protocol TLS, mode Passthrough
   ▼  TLSRoute per hostname (created by Strimzi)
Kafka bootstrap Service / broker-0 Service
```

## How it works

- **Passthrough, routed by SNI.** The Gateway listener does not terminate TLS. It reads the SNI name from the TLS handshake and forwards the bytes to the matching backend. Kafka's own certificates stay end to end.
- **One hostname per broker.** Kafka clients connect to the bootstrap address, then to each broker at its advertised address. Each broker needs its own name that routes to that broker.
- **Strimzi writes the TLSRoutes.** The `tlsroute` listener type (Strimzi 1.1+) creates one TLSRoute for the bootstrap and one for each broker, and sets the advertised addresses. You only create the Gateway.
- **No DNS setup.** `*.localtest.me` resolves to `127.0.0.1`.
- **Host access.** `kind-config.yaml` maps host port 9094 to node port 30094. An `AgentgatewayParameters` overlay sets the generated Service to `NodePort` 30094.

## Prerequisites

`docker`, `kind`, `kubectl`, `helm` and `kafkactl` (or only Docker for Option B).

## Run

```sh
kind create cluster --name kafka-tlsroute --config kind-config.yaml

# Gateway API CRDs (TLSRoute is in the standard channel since v1.5)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml

# agentgateway
helm upgrade -i --create-namespace -n agentgateway-system --version v1.7.0 \
  agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds
helm upgrade -i -n agentgateway-system --version v1.7.0 --wait \
  agentgateway oci://cr.agentgateway.dev/charts/agentgateway

# Strimzi (after the Gateway API CRDs, so the operator finds TLSRoute at startup)
kubectl create ns kafka
helm upgrade -i -n kafka --version 1.3.1 --wait \
  strimzi oci://quay.io/strimzi-helm/strimzi-kafka-operator

# Gateway and a single-node Kafka cluster
kubectl apply -f manifests/gateway.yaml -f manifests/kafka.yaml
kubectl -n kafka wait kafka/my-cluster --for=condition=Ready --timeout=300s
kubectl -n kafka get tlsroute
```

## Test from the host

**Option A: kafkactl (recommended)**

```sh
brew install deviceinsight/packages/kafkactl   # or: go install github.com/deviceinsight/kafkactl@latest
./scripts/test.sh
```

The script extracts the Strimzi cluster CA to `ca.crt`, then uses the `agentgateway` context in [`.kafkactl.yml`](.kafkactl.yml) to list brokers, create a topic, produce a message and consume it, all through `bootstrap.kafka.localtest.me:9094`. `get brokers` shows the advertised address, `broker-0.kafka.localtest.me:9094`, which goes through the gateway too. Run `kafkactl` from the repo root to use the same config:

```sh
kafkactl get brokers
kafkactl get topics
```

**Option B: Kafka CLI in a container**

```sh
./scripts/test-docker.sh
```

For hosts without kafkactl. The container reaches the host's published port with `--add-host`.

Any other client works too. Use the cluster CA (`kubectl -n kafka get secret my-cluster-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d`), `security.protocol=SSL` and `bootstrap.servers=bootstrap.kafka.localtest.me:9094`.

A quick check of the SNI routing, without Kafka:

```sh
echo | openssl s_client -connect 127.0.0.1:9094 -servername broker-0.kafka.localtest.me   # Kafka certificate
echo | openssl s_client -connect 127.0.0.1:9094 -servername other.kafka.localtest.me      # no route: connection closed
```

## Scaling out

Raise `replicas` in the `KafkaNodePool`. Strimzi adds a `broker-N.kafka.localtest.me` TLSRoute for each new broker. Nothing else changes, except the `--add-host` list in `scripts/test.sh`, which exists only for the test container.

## Clean up

```sh
./scripts/cleanup.sh
```

## Notes

- The Gateway listener and the host port are both 9094. Strimzi's `advertisedPortTemplate` must be the port clients use on the host.
- The Gateway and the Kafka cluster share the `kafka` namespace so the TLSRoutes can attach with `allowedRoutes.from: Same`.
- This is a demo setup: ephemeral storage, one broker, no authentication.
- Versions tested: kind v0.33.0, Gateway API v1.6.3, agentgateway v1.7.0, Strimzi 1.3.1.
