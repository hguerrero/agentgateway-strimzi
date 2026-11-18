# Kafka ingress with agentgateway TLSRoute

A minimal example: [agentgateway](https://agentgateway.dev) is the ingress for a [Strimzi](https://strimzi.io) Kafka cluster on Kubernetes. Kafka clients on your machine connect to `localhost:9094`. No `kubectl port-forward`.

```
host (kcat, Kafka CLI, your app)
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

`docker`, `kind`, `kubectl`, `helm`.

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

# Strimzi (install the CRDs before the operator needs TLSRoute: Gateway API goes first, as above)
kubectl create ns kafka
helm upgrade -i -n kafka --version 1.3.1 --wait \
  strimzi oci://quay.io/strimzi-helm/strimzi-kafka-operator

# Gateway and a single-node Kafka cluster
kubectl apply -f manifests/gateway.yaml -f manifests/kafka.yaml
kubectl -n kafka wait kafka/my-cluster --for=condition=Ready --timeout=300s
kubectl -n kafka get tlsroute
```

## Test from the host

```sh
./scripts/test.sh
```

The script creates a topic, produces one message and consumes it, all through `bootstrap.kafka.localtest.me:9094`. The Kafka CLI runs in a container only to avoid installing it. The container is pointed at the host's published port with `--add-host`.

To use your own client, get the cluster CA and connect with `security.protocol=SSL`:

```sh
kubectl -n kafka get secret my-cluster-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
# bootstrap.servers=bootstrap.kafka.localtest.me:9094
# ssl.truststore.type=PEM  ssl.truststore.location=ca.crt
```

A quick check of the SNI routing, without Kafka:

```sh
echo | openssl s_client -connect 127.0.0.1:9094 -servername broker-0.kafka.localtest.me   # Kafka certificate
echo | openssl s_client -connect 127.0.0.1:9094 -servername other.kafka.localtest.me      # no route: connection closed
```

## Scaling out

Raise `replicas` in the `KafkaNodePool`. Strimzi adds a `broker-N.kafka.localtest.me` TLSRoute for each new broker, and the client's `--add-host` list (only needed for the container in `test.sh`) is the only thing to extend.

## Clean up

```sh
./scripts/cleanup.sh
```

## Notes

- The Gateway listener and the host port are both 9094. Strimzi's `advertisedPortTemplate` must be the port clients use on the host.
- The Gateway and the Kafka cluster share the `kafka` namespace so the TLSRoutes can attach with `allowedRoutes.from: Same`.
- This is a demo setup: ephemeral storage, one broker, no authentication.
- Versions tested: kind v0.33.0, Gateway API v1.6.3, agentgateway v1.7.0, Strimzi 1.3.1.
