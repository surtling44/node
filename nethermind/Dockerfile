FROM golang:1.23 AS op

WORKDIR /app

ENV REPO=https://github.com/ethereum-optimism/optimism.git
ENV VERSION=v1.13.3
ENV COMMIT=b1e7c63bb2ffea46771c302bcb05f72ba1a7bf61
RUN git clone $REPO --branch op-node/$VERSION --single-branch . && \
    git switch -c branch-$VERSION && \
    bash -c '[ "$(git rev-parse HEAD)" = "$COMMIT" ]'

# Install 'just'
RUN curl -sSfL 'https://just.systems/install.sh' | bash -s -- --to /usr/local/bin

RUN cd op-node && \
    just VERSION=$VERSION op-node

FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS build

ARG BUILD_CONFIG=release
ARG TARGETARCH

WORKDIR /app

ENV REPO=https://github.com/NethermindEth/nethermind.git
ENV VERSION=1.31.11
ENV COMMIT=2be1890ee4f21f921a471de058dcb57937bd9b90
RUN git clone $REPO --branch $VERSION --single-branch . && \
    git switch -c $VERSION 
RUN bash -c '[ "$(git rev-parse HEAD)" = "$COMMIT" ]'
RUN TARGETARCH=${TARGETARCH#linux/} && \
    arch=$([ "$TARGETARCH" = "amd64" ] && echo "x64" || echo "$TARGETARCH") && \
    echo "Using architecture: $arch" && \
    dotnet publish src/Nethermind/Nethermind.Runner -c $BUILD_CONFIG -a $arch -o /publish --sc false

FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble

RUN apt-get update && \
    apt-get install -y jq curl supervisor && \
    rm -rf /var/lib/apt/lists

RUN mkdir -p /var/log/supervisor

WORKDIR /app

COPY --from=build /publish ./
COPY --from=op /app/op-node/bin/op-node ./
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY nethermind/nethermind-entrypoint ./execution-entrypoint
COPY op-node-entrypoint .

CMD ["/usr/bin/supervisord"]
