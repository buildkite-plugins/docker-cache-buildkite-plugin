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
  esac

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install the missing dependencies and try again."
    exit 1
  fi
}

build_cache_image_name() {
  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${BUILDKITE_PLUGIN_DOCKER_CACHE_TAG:-cache}-${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY}"
      ;;
    gar)
      if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" =~ \.pkg\.dev$ ]]; then
        # Google Artifact Registry host already specified
        echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${BUILDKITE_PLUGIN_DOCKER_CACHE_TAG:-cache}-${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY}"
      else
        echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}.gar.io/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}/${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${BUILDKITE_PLUGIN_DOCKER_CACHE_TAG:-cache}-${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY}"
      fi
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
