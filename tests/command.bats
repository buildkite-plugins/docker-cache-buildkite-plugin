#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_TAG='test-tag'
}

@test "Fails if provider is missing" {
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER
  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'provider is required'
}

@test "Fails if image is missing" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE
  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'image is required'
}

@test "ECR provider sets up environment" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-west-2'
  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Setting up Docker cache environment'
  assert_output --partial 'Provider: ecr'
}

@test "GAR provider sets up environment" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT='test-project'
  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Setting up Docker cache environment'
  assert_output --partial 'Provider: gar'
}

@test "Fails on unsupported provider" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='unknown'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'unsupported provider'
}