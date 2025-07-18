#!/bin/bash

# Docker Hub provider for Docker cache plugin

setup_dockerhub_environment() {
  local username="${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERHUB_USERNAME:-}"
  local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERHUB_REPOSITORY:-}"

  if [[ -z "$username" ]]; then
    log_error "Docker Hub username is required"
    exit 1
  fi

  log_info "Using Docker Hub username: $username"

  if [[ -n "$repository" ]]; then
    log_info "Using Docker Hub repository: $repository"
  else
    log_info "Using Docker Hub repository: ${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
  fi

  # Check if already authenticated
  if docker info | grep -q "Username: $username"; then
    log_success "Already authenticated with Docker Hub"
    return 0
  fi

  # Try to authenticate using environment variables
  if [[ -n "${DOCKER_HUB_TOKEN:-}" ]]; then
    log_info "Authenticating with Docker Hub using token..."
    if echo "$DOCKER_HUB_TOKEN" | docker login --username "$username" --password-stdin; then
      log_success "Successfully authenticated with Docker Hub"
    else
      log_error "Failed to authenticate with Docker Hub"
      exit 1
    fi
  elif [[ -n "${DOCKER_HUB_PASSWORD:-}" ]]; then
    log_info "Authenticating with Docker Hub using password..."
    if echo "$DOCKER_HUB_PASSWORD" | docker login --username "$username" --password-stdin; then
      log_success "Successfully authenticated with Docker Hub"
    else
      log_error "Failed to authenticate with Docker Hub"
      exit 1
    fi
  else
    log_warning "No Docker Hub credentials found in environment (DOCKER_HUB_TOKEN or DOCKER_HUB_PASSWORD)"
    log_warning "Assuming already authenticated or using public repositories"
  fi
}

restore_dockerhub_cache() {
  local cache_key="$1"
  local cache_image

  cache_image=$(build_cache_image_name "dockerhub" "$cache_key")

  if image_exists_in_registry "$cache_image"; then
    log_info "Cache hit! Restoring from $cache_image"
    if pull_image "$cache_image"; then
      tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
      log_success "Cache restored successfully from Docker Hub"
      return 0
    else
      log_warning "Failed to pull cache image from Docker Hub"
      return 1
    fi
  else
    log_info "Cache miss. No cached image found for key $cache_key in Docker Hub. Proceeding without cache."
    return 0
  fi
}

save_dockerhub_cache() {
  local cache_key="$1"
  local cache_image
  local source_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  cache_image=$(build_cache_image_name "dockerhub" "$cache_key")

  # Check if source image exists locally
  if ! image_exists_locally "$source_image"; then
    log_error "Source image not found locally: $source_image"
    return 1
  fi

  # Tag and push the cache image
  if tag_image "$source_image" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to Docker Hub: $cache_image"
      return 0
    else
      log_error "Failed to save cache to Docker Hub"
      return 1
    fi
  else
    log_error "Failed to tag cache image for Docker Hub"
    return 1
  fi
}
