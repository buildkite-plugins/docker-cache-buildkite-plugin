# Docker Cache Buildkite Plugin [![Build status](https://badge.buildkite.com/a3851ab6b8e918f7a29d1d43fd8a410308fd5a50455b8a4ab3.svg)](https://buildkite.com/buildkite/plugins-docker-cache)

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) for caching [Docker](https://docker.com) images across builds using various registry providers (ECR and GAR currently supported).

This plugin speeds up your Docker builds by caching images between pipeline runs. Instead of rebuilding the same Docker image every time, it stores built images in ECR or Google Artifact Registry and reuses them when nothing has changed.

The plugin will check if a cached version of your image already exists. If it does, it pulls that instead of rebuilding. If not, it builds the image and saves it for next time. It automatically creates the necessary repositories in your registry if they don't exist.

Cache keys are generated based on your Dockerfile content and build context, so the cache automatically invalidates when you make changes to your code or build configuration.

Also see the [Docker Buildkite Plugin](https://github.com/buildkite-plugins/docker-buildkite-plugin) for running pipeline steps in Docker containers.

## Example

### ECR Provider

The following pipeline will cache Docker builds in Amazon ECR.

```yaml
steps:
  - label: "🐳 Build with ECR cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### GAR Provider

The following pipeline will cache Docker builds in Google Artifact Registry:

```yaml
steps:
  - label: "🐳 Build with GAR cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: gar
          image: my-app
          gar:
            project: my-gcp-project
            region: us
```

### Cache Strategies

You can control how the cache is used with different strategies:

#### Artifact Strategy

Pulls the complete cached image if available, builds from scratch if not:

```yaml
steps:
  - label: "🐳 Artifact strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: artifact
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

#### Build Strategy

Uses layer caching during the build process:

```yaml
steps:
  - label: "🐳 Build strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: build
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

#### Hybrid Strategy

Tries artifact strategy first, falls back to build strategy if pull fails:

```yaml
steps:
  - label: "🐳 Hybrid strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: hybrid
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### Multi-stage Builds

For multi-stage Dockerfiles, you can specify the target stage:

```yaml
steps:
  - label: "🐳 Multi-stage build"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          target: production
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### Build Arguments

You can pass build arguments to Docker:

```yaml
steps:
  - label: "🐳 Build with args"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          build-args:
            - NODE_ENV=production
            - API_URL=https://api.example.com
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

## Configuration

### Required

#### `provider` (required, string)

Which registry provider to use for caching: `ecr` or `gar`.

#### `image` (required, string)

Name of your Docker image.

Example: `my-app`

### Optional

#### `strategy` (optional, string)

How to use the cache:

- `artifact`: Pull complete cached image if available, build from scratch if not
- `build`: Use layer caching during build process
- `hybrid`: Try artifact strategy first, fall back to build strategy if pull fails

Default: `hybrid`

#### `dockerfile` (optional, string)

Path to your Dockerfile.

Default: `Dockerfile`

#### `dockerfile-inline` (optional, string)

Inline Dockerfile content instead of reading from a file.

#### `context` (optional, string)

Docker build context path.

Default: `.`

#### `target` (optional, string)

Target stage for multi-stage builds.

#### `build-args` (optional, array)

Build arguments to pass to Docker.

Example: `["NODE_ENV=production", "VERSION=1.0.0"]`

#### `additional-build-args` (optional, string)

Additional docker build arguments as a single string.

Example: `"--network=host --build-arg CUSTOM_ARG=value"`

#### `secrets` (optional, array)

Build secrets to pass to Docker (requires BuildKit).

Example: `["id=mysecret,src=/local/secret", "id=mypassword"]`

#### `cache-from` (optional, array)

Additional cache sources for Docker build.

Example: `["my-base-image:latest"]`

#### `skip-pull-from-cache` (optional, boolean)

Skip pulling from cache (useful for testing).

Default: `false`

#### `save` (optional, boolean)

Whether to save cache after build.

Default: `true`

#### `restore` (optional, boolean)

Whether to restore cache before build.

Default: `true`

#### `max-age-days` (optional, number)

Maximum age in days for cached images.

Default: `30`

#### `cache-key` (optional, string or array)

Custom cache key. If not provided, automatically generated from Dockerfile content and build context.

Example: `["my-key", "v1.0"]` or `"custom-key"`

#### `export-env-variable` (optional, string)

Environment variable name for exporting the final image reference.

Default: `BUILDKITE_PLUGIN_DOCKER_IMAGE`

#### `verbose` (optional, boolean)

Enable verbose logging.

Default: `false`

#### `tag` (optional, string)

Custom tag for the cached image.

Default: Generated from git commit or pipeline context

### ECR Provider Options

When using `provider: ecr`, these options are available:

#### `ecr.region` (required, string)

AWS region for ECR registry.

Example: `us-east-1`

#### `ecr.account-id` (required, string)

AWS account ID (12 digits).

Example: `123456789012`

#### `ecr.registry-url` (optional, string)

Custom ECR registry URL. If not provided, will be constructed from account ID and region.

Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com`

### GAR Provider Options

When using `provider: gar`, these options are available:

#### `gar.project` (required, string)

Google Cloud project ID.

Example: `my-gcp-project`

#### `gar.region` (required, string)

GAR region.

Valid values: `us`, `europe`, `asia`, or specific regional endpoints like `us-central1-docker.pkg.dev`

Example: `us`

#### `gar.repository` (optional, string)

Artifact Registry repository name. If not provided, defaults to the image name.

Example: `docker` (for repository name, results in full path like `us-docker.pkg.dev/project/docker/image`)

## Authentication

### ECR Authentication

The plugin handles ECR authentication automatically using your existing AWS credentials. Make sure your build environment has AWS credentials configured through:

- IAM roles (recommended for EC2/ECS)
- AWS credentials file
- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

Required permissions:

- `sts:GetCallerIdentity`
- `ecr:GetAuthorizationToken`
- `ecr:DescribeRepositories`
- `ecr:CreateRepository`
- `ecr:BatchGetImage`
- `ecr:GetDownloadUrlForLayer`
- `ecr:BatchCheckLayerAvailability`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`

### GAR Authentication

The plugin uses gcloud for GAR authentication with your existing Google Cloud credentials. Make sure your build environment has Google Cloud credentials configured through:

- Service account keys
- Workload Identity (recommended for GKE)
- Application Default Credentials

Required permissions:

- `artifactregistry.repositories.get`
- `artifactregistry.repositories.create`
- `artifactregistry.docker.images.get`
- `artifactregistry.docker.images.push`
- `artifactregistry.docker.images.pull`

## Cache Key Generation

Cache keys are automatically generated from:

- Dockerfile content hash (primary)
- Build context hash (if different from Dockerfile location)
- Build arguments
- Target stage (for multi-stage builds)

This ensures the cache is invalidated whenever anything that affects the build changes.

## Developing

To run testing, shellchecks and plugin linting use `bk run` with the [Buildkite CLI](https://github.com/buildkite/cli).

```bash
bk run
```

Or if you want to run just the tests, you can use the docker [Plugin Tester](https://github.com/buildkite-plugins/buildkite-plugin-tester):

```bash
docker run --rm -ti -v "${PWD}":/plugin buildkite/plugin-tester:latest
```

## License

MIT (see [LICENSE](LICENSE))
