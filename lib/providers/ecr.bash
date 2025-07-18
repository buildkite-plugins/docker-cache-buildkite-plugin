#!/bin/bash

# AWS ECR provider for Docker cache plugin

setup_ecr_environment() {
  local region="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION:-}"
  local account_id="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID:-}"
  local registry_url="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL:-}"

  if ! command_exists aws; then
    log_error "AWS CLI is required for ECR provider"
    exit 1
  fi

  if [[ -z "$region" ]]; then
    region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    log_info "Using AWS region: $region"
  fi
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION="$region"

  if [[ -z "$account_id" ]]; then
    log_info "Auto-detecting AWS account ID..."
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
      log_error "Failed to auto-detect AWS account ID. Please provide it in the configuration."
      exit 1
    fi
    log_info "Using AWS account ID: $account_id"
  fi
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID="$account_id"

  if [[ -z "$registry_url" ]]; then
    registry_url="${account_id}.dkr.ecr.${region}.amazonaws.com"
  fi
  export DOCKER_CACHE_ECR_REGISTRY_URL="$registry_url"

  log_info "ECR registry URL: $registry_url"

  log_info "Authenticating with ECR..."
  if aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry_url"; then
    log_success "Successfully authenticated with ECR"
  else
    log_error "Failed to authenticate with ECR"
    exit 1
  fi
}

restore_ecr_cache() {
  local cache_key="$1"
  local cache_image

  cache_image=$(build_cache_image_name "ecr" "$cache_key")

  if image_exists_in_registry "$cache_image"; then
    log_info "Cache hit! Restoring from $cache_image"
    if pull_image "$cache_image"; then
      tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
      log_success "Cache restored successfully from ECR"
      return 0
    else
      log_warning "Failed to pull cache image from ECR"
      return 1
    fi
  else
    log_info "Cache miss. No cached image found for key $cache_key in ECR. Proceeding without cache."
    return 0
  fi
}

save_ecr_cache() {
  local cache_key="$1"
  local cache_image
  local source_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  cache_image=$(build_cache_image_name "ecr" "$cache_key")

  if ! image_exists_locally "$source_image"; then
    log_error "Source image not found locally: $source_image"
    return 1
  fi

  local repository_name="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
  log_info "Ensuring ECR repository exists: $repository_name"

  if ! aws ecr describe-repositories --repository-names "$repository_name" --region "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}" >/dev/null 2>&1; then
    log_info "Creating ECR repository: $repository_name"
    if aws ecr create-repository --repository-name "$repository_name" --region "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}" >/dev/null; then
      log_success "ECR repository created successfully"
    else
      log_error "Failed to create ECR repository"
      return 1
    fi
  fi

  if tag_image "$source_image" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to ECR: $cache_image"
      return 0
    else
      log_error "Failed to save cache to ECR"
      return 1
    fi
  else
    log_error "Failed to tag cache image for ECR"
    return 1
  fi
}
