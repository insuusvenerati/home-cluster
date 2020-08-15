#!/usr/bin/env bash

shopt -s globstar

# Get Absolute Path of the base repo
export REPO_ROOT=$(git rev-parse --show-toplevel)
# Get Absolute Path of where Flux looks for manifests
export CLUSTER_ROOT="${REPO_ROOT}/deployments"

need() {
    if ! [ -x "$(command -v $1)" ]; then
      echo "Error: Unable to find binary $1"
      exit 1
    fi
}

# Verify we have dependencies
need "kubeseal"
need "kubectl"
need "sed"
need "envsubst"
need "yq"

# Work-arounds for MacOS
if [ "$(uname)" == "Darwin" ]; then
  # brew install gnu-sed
  need "gsed"
  # use sed as alias to gsed
  export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
  # Source secrets.env
  set -a
  . "${REPO_ROOT}/.cluster-secrets.env"
  set +a
else
  . "${REPO_ROOT}/.cluster-secrets.env"
fi

echo "~~~~~~~~~~~~~~~~~~~~~~"
echo ">>> ${TEST_SECRET} <<<"
echo "~~~~~~~~~~~~~~~~~~~~~~"

# Path to Public Cert
PUB_CERT="${REPO_ROOT}/pub-cert.pem"

# Path to generated secrets file
GENERATED_SECRETS="${CLUSTER_ROOT}/zz_generated_secrets.yaml"

{
  echo "#"
  echo "# Manifests auto-generated by secrets.sh -- DO NOT EDIT."
  echo "#"
  echo "---"
} > "${GENERATED_SECRETS}"

#
# Helm Secrets
#

# Generate Helm Secrets
for file in "${CLUSTER_ROOT}"/**/*.txt
do
  # Get the path and basename of the txt file
  # e.g. "deployments/default/pihole/pihole"
  secret_path="$(dirname "$file")/$(basename -s .txt "$file")"
  # Get the filename without extension
  # e.g. "pihole"
  secret_name=$(basename "${secret_path}")  
  # Get the relative path of deployment
  deployment=${file#"${CLUSTER_ROOT}"}
  # Get the namespace (based on folder path of manifest)
  namespace=$(echo ${deployment} | awk -F/ '{print $2}')
  echo "  Generating helm secret '${secret_name}' in namespace '${namespace}'..."
  # Create secret
  envsubst < "$file" \
    | \
  kubectl -n "${namespace}" create secret generic "${secret_name}-helm-values" \
    --from-file=/dev/stdin --dry-run=client -o json \
    | \
  kubeseal --format=yaml --cert="${PUB_CERT}" \
    >> "${GENERATED_SECRETS}"
  echo "---" >> "${GENERATED_SECRETS}"
done

# Replace stdin with values.yaml
sed -i 's/stdin\:/values.yaml\:/g' "${GENERATED_SECRETS}"

#
# Generic Secrets
#

{
  echo "#"
  echo "# Generic Secrets auto-generated by secrets.sh -- DO NOT EDIT."
  echo "#"
} >> "${GENERATED_SECRETS}"

# NginX Basic Auth - default namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# NginX Basic Auth - kube-system namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace kube-system --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# NginX Basic Auth - monitoring namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Cloudflare API Key - cert-manager namespace
kubectl create secret generic cloudflare-api-key \
  --from-literal=api-key="${CF_API_KEY}" \
  --namespace cert-manager --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# qBittorrent Prune - default namespace
kubectl create secret generic qbittorrent-prune \
  --from-literal=username="${QB_USERNAME}" \
  --from-literal=password="${QB_PASSWORD}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# sonarr episode prune - default namespace
kubectl create secret generic sonarr-episode-prune \
  --from-literal=api-key="${SONARR_APIKEY}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# sonarr exporter
kubectl create secret generic sonarr-exporter \
  --from-literal=api-key="${SONARR_APIKEY}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# radarr exporter
kubectl create secret generic radarr-exporter \
  --from-literal=api-key="${RADARR_APIKEY}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# uptimerobot heartbeat
kubectl create secret generic uptimerobot-heartbeat \
  --from-literal=url="${UPTIMEROBOT_HEARTBEAT_URL}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# longhorn backup secret
kubectl create secret generic longhorn-backup-secret \
  --from-literal=AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY}" \
  --from-literal=AWS_ENDPOINTS="http://192.168.1.39:9000" \
  --namespace longhorn-system --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Fluxcloud
kubectl create secret generic fluxcloud \
  --from-literal=discord_webhook_url="${DISCORD_FLUXCLOUD_WEBHOOK_URL}" \
  --namespace flux --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Github Runner
kubectl create secret generic controller-manager \
  --from-literal=github_token="${GITHUB_RUNNER_ACCESS_TOKEN}" \
  --namespace actions-runner-system --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Remove empty new-lines
sed -i '/^[[:space:]]*$/d' "${GENERATED_SECRETS}"

# Validate Yaml
# if ! yq validate "${GENERATED_SECRETS}" > /dev/null 2>&1; then
#     echo "Errors in YAML"
#     exit 1
# fi
