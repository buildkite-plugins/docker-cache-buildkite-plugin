#!/bin/bash

# Shared utility functions for the Docker cache plugin

set -euo pipefail

log_info() {
  echo "[INFO]: $*"
}

log_success() {
  echo "[SUCCESS]: $*"
}

log_warning() {
  echo "[WARNING]: $*"
}

log_error() {
  echo "[ERROR]: $*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

unknown_provider() {
  local provider="$1"
  log_error "Unknown provider: $provider"
  exit 1
}

# Expand environment variables from plugin configuration values
# Usage: expand_env_var "raw_value" "parameter_name"
# Returns: expanded value or exits with error if variable is missing/empty
expand_env_var() {
  local raw_value="$1"
  local param_name="$2"
  local result

  # shellcheck disable=SC2016
  case "${raw_value}" in
  '$'*)
    local var_name="${raw_value#$}"
    if [[ -v "${var_name}" ]]; then
      result="${!var_name}"
      if [[ -z "$result" ]]; then
        log_error "Environment variable '${var_name}' referenced by ${param_name} parameter is empty or not set"
        exit 1
      fi
    else
      log_error "Environment variable '${var_name}' referenced by ${param_name} parameter is empty or not set"
      exit 1
    fi
    ;;
  *)
    result="${raw_value}"
    ;;
  esac

  echo "$result"
}

check_dependencies() {
  local missing_deps=()

  if ! command_exists docker; then
    missing_deps+=("docker")
  fi

  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      if ! command_exists aws; then
        missing_deps+=("aws")
      fi
      ;;
    gar)
      if ! command_exists gcloud; then
        missing_deps+=("gcloud")
      fi
      ;;
    buildkite)
      if ! command_exists buildkite-agent; then
        missing_deps+=("buildkite-agent")
      fi
      ;;
    artifactory)
      # Artifactory only requires Docker, which is already checked above
      ;;
    acr)
      if ! command_exists az; then
        missing_deps+=("az")
      fi
      ;;
  esac

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install the missing dependencies and try again."
    exit 1
  fi
}

build_cache_image_name() {
  # Optional parameter: custom tag suffix to use instead of cache-KEY pattern
  # Usage: build_cache_image_name "${BUILDKITE_PLUGIN_DOCKER_CACHE_FALLBACK_TAG}"
  local tag_suffix="${1:-${BUILDKITE_PLUGIN_DOCKER_CACHE_TAG:-cache}-${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY}}"

  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      ;;
    gar)
      if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" =~ \.pkg\.dev$ ]]; then
        # Google Artifact Registry host already specified
        echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      else
        echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}.gcr.io/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      fi
      ;;
    buildkite)
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      ;;
    artifactory)
      local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      ;;
    acr)
      local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${tag_suffix}"
      ;;
    *)
      log_error "Unknown provider: ${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}"
      exit 1
      ;;
  esac
}

image_exists_locally() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1
}

image_exists_in_registry() {
  local image="$1"

  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_VERBOSE}" == "true" ]]; then
    log_info "Checking if image exists in registry: $image"
  fi

  # Try to pull manifest without downloading the image
  docker manifest inspect "$image" >/dev/null 2>&1
}

pull_image() {
  local image="$1"

  log_info "Pulling image: $image"
  if docker pull "$image"; then
    log_success "Successfully pulled cache image"
    return 0
  else
    log_warning "Failed to pull cache image"
    return 1
  fi
}

push_image() {
  local image="$1"

  log_info "Pushing image: $image"
  if docker push "$image"; then
    log_success "Successfully pushed cache image"
    return 0
  else
    log_error "Failed to push cache image"
    return 1
  fi
}

tag_image() {
  local source_image="$1"
  local target_image="$2"

  log_info "Tagging image $source_image -> $target_image"
  if docker tag "$source_image" "$target_image"; then
    log_success "Image tagged successfully"
    return 0
  else
    log_error "Failed to tag image"
    return 1
  fi
}
