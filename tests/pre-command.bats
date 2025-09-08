#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_TAG='test-tag'
}

@test "Pre-command hook runs cache operations with ECR provider" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-west-2'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  stub aws \
    "ecr get-login-password --region us-west-2 : echo password"

  # N.B: Using function override instead of stub for docker commands because
  # stub patterns like "build *" don't reliably match complex argument sequences
  # with multiple flags like "--cache-from". Function overrides provide more
  # reliable pattern matching for complex docker command scenarios.
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "--username" ]]; then
          cat > /dev/null  # Read stdin and discard
          echo "Login Succeeded"
          return 0
        fi
        ;;
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'ECR registry URL'

  unstub aws
}

@test "Pre-command hook runs cache operations with GAR provider" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT='test-project'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION='us'

  stub gcloud \
    "auth configure-docker us.gcr.io --quiet : exit 0"

  # N.B: Using function override instead of stub for docker commands because
  # stub patterns don't handle complex multi-argument docker commands reliably.
  # This approach provides better control over command simulation.
  function docker() {
    case "$1" in
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'GAR project'

  unstub gcloud
}

@test "artifact strategy with cache hit pulls complete image" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='artifact'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-east-1'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  stub aws \
    "ecr get-login-password --region us-east-1 : echo password"

  # N.B: Using function override for docker commands because stub patterns
  # cannot handle complex docker operations like piped authentication
  # (aws ecr get-login-password | docker login) and manifest inspect scenarios.
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "--username" ]]; then
          # Read from stdin and discard it
          cat > /dev/null
          echo "Login Succeeded"
          return 0
        fi
        ;;
      manifest)
        echo '{"schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json"}'
        return 0
        ;;
      pull)
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'Complete cache hit'

  unstub aws
}

@test "artifact strategy with cache miss continues with build" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='artifact'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-east-1'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  stub aws \
    "ecr get-login-password --region us-east-1 : echo password" \
    "ecr describe-repositories --repository-names test-app --region us-east-1 : exit 1" \
    "ecr create-repository --repository-name test-app --region us-east-1 : echo '{\"repository\":{\"repositoryUri\":\"123456789012.dkr.ecr.us-east-1.amazonaws.com/test-app\"}}'"

  # N.B: Hybrid approach - AWS stubs work fine for simple commands, but docker
  # function override needed for complex scenarios including cache miss simulation
  # (manifest inspect), ECR repository operations, and multi-step build processes.
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "--username" ]]; then
          cat > /dev/null  # Read stdin and discard
          echo "Login Succeeded"
          return 0
        fi
        ;;
      manifest)
        if [[ "$2" == "inspect" ]]; then
          return 1  # Simulate cache miss
        fi
        ;;
      build)
        # N.B: Must handle both simple builds and builds with --cache-from flag
        # since the build strategy uses cache optimization
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        echo "Successfully tagged image"
        return 0
        ;;
      save)
        echo "Successfully saved image"
        return 0
        ;;
      images)
        if [[ "$*" =~ "test-app" ]]; then
          echo "test-app    126bd2e6951485ee73e6a92d02e4a78e1541ce1c    abc123"
          return 0
        fi
        ;;
      push)
        echo "Successfully pushed image"
        return 0
        ;;
      image)
        if [[ "$2" == "inspect" && "$3" == "test-app" ]]; then
          return 0  # Image exists locally
        fi
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'Cache miss'

  unstub aws
}

@test "build strategy sets up layer caching" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='build'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-east-1'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  # N.B: Only stubbing the AWS commands actually called by the build strategy.
  # Removed 'sts get-caller-identity' stub as it's not used in this test scenario,
  # preventing 'unused stub' failures in bats-mock.
  stub aws \
    "ecr get-login-password --region us-east-1 : echo password"

  # N.B: Function override approach used instead of docker stubs because
  # build strategy requires handling complex --cache-from arguments that
  # stub wildcard patterns cannot match reliably.
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "--username" ]]; then
          cat > /dev/null  # Read stdin and discard
          echo "Login Succeeded"
          return 0
        fi
        ;;
      manifest)
        echo '{"schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json"}'
        return 0
        ;;
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        echo "Successfully tagged image"
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'build strategy'

  unstub aws
}

@test "hybrid strategy falls back to layer caching on pull failure" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='hybrid'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-east-1'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  # N.B: Minimal AWS stubs - only mocking commands actually invoked by hybrid strategy.
  # This prevents bats-mock 'unused stub' errors while maintaining test reliability.
  stub aws \
    "ecr get-login-password --region us-east-1 : echo password"

  # N.B: Function override required for hybrid strategy testing because we need
  # to simulate pull failure (return 1) followed by successful build with cache.
  # Stub patterns cannot simulate this conditional failure scenario reliably.
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "--username" ]]; then
          cat > /dev/null  # Read stdin and discard
          echo "Login Succeeded"
          return 0
        fi
        ;;
      manifest)
        echo '{"schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json"}'
        return 0
        ;;
      pull)
        return 1  # Simulate pull failure
        ;;
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        echo "Successfully tagged image"
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'hybrid strategy'

  unstub aws
}

@test "Pre-command hook runs cache operations with Buildkite provider" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  export BUILDKITE_API_TOKEN='fake-token'

  # N.B: Using function override instead of stub for buildkite-agent and docker 
  # commands to handle complex authentication and build scenarios
  function buildkite-agent() {
    return 0
  }
  
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "packages.buildkite.com/my-org/test-image" ]]; then
          echo "Login Succeeded"
          return 0
        fi
        ;;
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f buildkite-agent docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'Buildkite registry URL'
}

@test "Buildkite provider with OIDC authentication works" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-image'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_AUTH_METHOD='oidc'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'

  function buildkite-agent() {
    if [[ "$1" == "oidc" && "$2" == "request-token" ]]; then
      echo "fake-oidc-token"
      return 0
    fi
    return 0
  }
  
  function docker() {
    case "$1" in
      login)
        if [[ "$2" == "packages.buildkite.com/my-org/test-image" ]]; then
          cat > /dev/null  # Read token from stdin
          echo "Login Succeeded"
          return 0
        fi
        ;;
      build)
        if [[ "$*" =~ "--cache-from" ]]; then
          echo "Successfully built with cache layers abc123"
        else
          echo "Successfully built abc123"
        fi
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f buildkite-agent docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'Authentication method: oidc'
  assert_output --partial 'Successfully authenticated with Buildkite Packages using OIDC'
}

@test "Buildkite provider handles cache hit with artifact strategy" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='test-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='artifact'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  export BUILDKITE_API_TOKEN='fake-token'

  function buildkite-agent() { return 0; }
  
  function docker() {
    case "$1" in
      login)
        echo "Login Succeeded"
        return 0
        ;;
      manifest)
        echo '{"schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json"}'
        return 0
        ;;
      pull)
        return 0
        ;;
      tag)
        return 0
        ;;
      *)
        command docker "$@"
        ;;
    esac
  }
  export -f buildkite-agent docker

  run "$PWD"/hooks/pre-command

  assert_success
  assert_output --partial 'Docker cache build'
  assert_output --partial 'Complete cache hit'
}
