FROM nginx:1.28.0

RUN apt-get update && \
  apt-get install -y \
    wget \
    jq

# https://docs.datadoghq.com/tracing/trace_collection/proxy_setup/?tab=nginx#module-installation
RUN get_latest_release() { \
      curl --silent "https://api.github.com/repos/$1/releases/latest" | jq --raw-output .tag_name; \
    } && \
    NGINX_VERSION=1.28.0 && \
    RELEASE_TAG=$(get_latest_release DataDog/nginx-datadog) && \
    ARCH=$(uname -m) && \
    case $ARCH in \
      x86_64) ARCH=amd64 ;; \
      aarch64) ARCH=arm64 ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    tarball="ngx_http_datadog_module-${ARCH}-${NGINX_VERSION}.so.tgz" && \
    wget "https://github.com/DataDog/nginx-datadog/releases/download/$RELEASE_TAG/$tarball" && \
    tar -xzf "$tarball" && \
    mv ngx_http_datadog_module.so /usr/lib/nginx/modules/ && \
    rm "$tarball"
