# cdc-relay

Reference zero-trust tokenisation relay for `CDCSecureFields`. Read `docs/ZERO_TRUST.md` first.

The relay generates a P-256 key at boot, publishes it inside an attestation document, decrypts the
JWE payloads the iOS SDK produces, optionally requires Apple App Attest proof that the request came
from a genuine build of your app, validates the card, forwards it to a payment provider and returns
only the provider's token. It stores nothing and never logs card data.

## Run in development

```bash
cd relay
go run ./cmd/relay
# in another shell
curl -s "localhost:8080/v1/attestation?nonce=$(openssl rand -hex 32)" -o doc.cbor
curl -s localhost:8080/v1/attestation/dev-root   # pin this in NitroAttestationPolicy.trustedRootSHA256 for dev
curl -s localhost:8080/v1/attestation/pcrs       # pin PCR0 in NitroAttestationPolicy.expectedPCRs
```

In `dev` mode the document is signed by an in-process P-384 chain with the same shape as a Nitro
document, so the whole iOS flow, including attestation verification and PCR pinning, runs against a
laptop. Compute the dev root fingerprint from the DER certificate on your test machine:

```sh
curl -fsS http://127.0.0.1:8080/v1/attestation/dev-root | openssl x509 -outform DER | openssl dgst -sha256
```

Pass the 32 fingerprint bytes to `trustedRootSHA256` and the 48 PCR0 bytes to `expectedPCRs[0]`. The iOS client requires HTTPS, so a dev client also needs a trusted local TLS endpoint in front of the relay.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `RELAY_ADDR` | `127.0.0.1:8080` | Listen address |
| `RELAY_MODE` | `dev` | `dev` or `nitro` |
| `RELAY_VERSION` | `dev` | Reported in `user_data` and used for dev PCRs |
| `RELAY_PSP` | `echo` | `echo` (HMAC dev tokens) or `stripe` |
| `STRIPE_SECRET_KEY` | | Required for `stripe`; needs raw card data APIs enabled on the account |
| `APP_ATTEST` | `off` | `required` to demand App Attest headers on `/v1/tokenize` |
| `APP_ATTEST_APP_ID` | | `TEAMID.bundle.identifier` |
| `APP_ATTEST_ENV` | `production` | `development` accepts the `appattestdevelop` environment |

Nitro mode requires `APP_ATTEST=required` and `APP_ATTEST_ENV=production`. Enrollment uses a fresh 32-byte challenge from this relay. A single process owns challenge, key and counter state.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/attestation?nonce=<hex>` | COSE_Sign1 attestation document (`application/cbor`) binding nonce, version and the relay's public JWK |
| GET | `/v1/attestation/dev-root` | Dev-mode root certificate PEM (404 in nitro mode) |
| GET | `/v1/attestation/pcrs` | Dev-mode PCR values (404 in nitro mode; use `nitro-cli describe-eif`) |
| POST | `/v1/challenge` | One-time challenge for App Attest key attestation |
| POST | `/v1/tokenize` | JWE body (`application/jose+json`); returns `{token, provider, brand, bin, last4, exp_month, exp_year}` |

Rejections: `400` undecryptable or expired payload, `401` App Attest failure, `409` replayed
nonce, `422` card fails Luhn or expiry, `502` provider rejected the card. Bodies never echo input.

## Run inside a Nitro enclave

```bash
docker build -f Dockerfile.enclave -t cdc-relay:enclave .
nitro-cli build-enclave --docker-uri cdc-relay:enclave --output-file cdc-relay.eif
nitro-cli describe-eif --eif-path cdc-relay.eif      # record PCR0, PCR1, PCR2 for the app to pin
nitro-cli run-enclave --eif-path cdc-relay.eif --cpu-count 2 --memory 1024 --enclave-cid 16
```

Enclaves have no network. Run a vsock proxy on the parent for ingress to the relay's port and
`vsock-proxy` egress restricted to your payment provider's host, for example
`vsock-proxy 8001 api.stripe.com 443`. Give the enclave the provider secret through KMS with an
attestation-gated key policy rather than an environment variable. Build with `-tags nitro` so the
attestation comes from `/dev/nsm`.

This path is written to the AWS NSM API but has not yet been run on real Nitro hardware; the dev
mode has. Treat the first enclave deployment as a verification step.

## Tests

```bash
go test ./...
```

`cmd/relay/main_test.go` includes a fixture encrypted by the Swift SDK
(`testdata/swift_jwe.json`, produced by `RelayFixtureExportTests`) that the Go relay must decrypt
with no shared code. Regenerate it with:

```bash
CDC_RELAY_FIXTURE_OUT=$PWD/relay/testdata/swift_jwe.json \
CDC_RELAY_PUBLIC_JWK=<public jwk path> swift test --filter RelayFixtureExportTests
```
