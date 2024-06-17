# Only the service name needs to be updated.  Everything else is default
ARG APP_NAME="na"

# Setup the version of ASPNET and DOTNET we're using.  No need to change this
ARG ASPNET_VERSION=6.0.16
ARG DOTNET_VERSION=6.0

# This is the base service target image to be used with build service and to use for plugins
FROM scratch as svc-base
ARG APP_NAME="na"
ENV APP_NAME=${APP_NAME}

WORKDIR /workspaces/${APP_NAME}
COPY . .

# This is spacesdk_base
FROM mcr.microsoft.com/dotnet/nightly/aspnet:${DOTNET_VERSION}-jammy-chiseled as spacesdk-base
ARG APP_NAME="na"
ENV APP_NAME=${APP_NAME}

# DotNet flags used across the services
ENV ASPNET_VERSION=${ASPNET_VERSION} \
    DOTNET_VERSION=${DOTNET_VERSION} \
    DOTNET_CLI_TELEMETRY_OPTOUT=true \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    DOTNET_NOLOGO=true \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
USER root


# This is the final full service target image that includes spacesdk-base and service-base
FROM scratch as full-service
ARG APP_NAME="na"
ENV APP_NAME=${APP_NAME}
# Copy everything from spacesdk-base to local
COPY --from=spacesdk-base / /

# Copy everything from svc-base to local image
COPY --from=svc-base --chmod=0755 / /

USER root
WORKDIR /workspaces/${APP_NAME}