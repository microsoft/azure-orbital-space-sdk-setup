# Dockerfile.app is used to build a full payload-app container image.  It includes content from spacesdk-base, which will have a distroless operating system with dotnet

ARG APP_NAME="spacesdk-app"
ARG APP_VERSION="0.0.1"
ARG SPACEFX_VERSION="0.0.1"
ARG APP_BUILDDATE="20010101T000000"
ARG ARCHITECTURE=""
ARG CONTAINER_REGISTRY="ghcr.io/microsoft/azure-orbital-space-sdk"
ARG WORKING_DIRECTORY="/workspaces/${APP_NAME}"

# Setup the version of ASPNET and DOTNET we're using.  No need to change this
ARG ASPNET_VERSION=6.0.16
ARG DOTNET_VERSION=6.0

# This is the payload-app output from a dotnet build
FROM ${CONTAINER_REGISTRY}/${APP_NAME}:${SPACEFX_VERSION}_base as app-base
ARG APP_NAME="spacesdk-app"
ARG APP_VERSION="0.0.1"
ARG SPACEFX_VERSION="0.0.1"
ARG APP_BUILDDATE="20010101T000000"
ARG ARCHITECTURE=""
ARG CONTAINER_REGISTRY="ghcr.io/microsoft/azure-orbital-space-sdk"
ARG APP_NAME="spacesdk-app"
ARG WORKING_DIRECTORY="/workspaces/${APP_NAME}"

ENV APP_NAME=${APP_NAME}
ENV WORKING_DIRECTORY=${WORKING_DIRECTORY}


# Grab spacesdk-base image from our container repository
FROM ${CONTAINER_REGISTRY}/spacesdk-base:${SPACEFX_VERSION} as spacesdk-base
ARG APP_NAME="spacesdk-app"
ARG APP_VERSION="0.0.1"
ARG SPACEFX_VERSION="0.0.1"
ARG APP_BUILDDATE="20010101T000000"
ARG ARCHITECTURE=""
ARG CONTAINER_REGISTRY="ghcr.io/microsoft/azure-orbital-space-sdk"
ARG WORKING_DIRECTORY="/workspaces/${APP_NAME}"

ENV APP_NAME=${APP_NAME}
ENV SPACEFX_VERSION=${SPACEFX_VERSION}
ENV APP_VERSION=${APP_VERSION}
ENV APP_BUILDDATE=${BUILD_DATE}
ENV ARCHITECTURE=${ARCHITECTURE}
ENV WORKING_DIRECTORY=${WORKING_DIRECTORY}

USER root

# Copy everything from app-base to local image
COPY --from=app-base --chmod=0755 ${WORKING_DIRECTORY} ${WORKING_DIRECTORY}

USER root
WORKDIR ${WORKING_DIRECTORY}