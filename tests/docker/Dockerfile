FROM gcc:13
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends cmake ninja-build python3 git ca-certificates curl xz-utils libncurses-dev libffi-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /source
