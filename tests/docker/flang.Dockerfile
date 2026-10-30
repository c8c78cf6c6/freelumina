FROM freelumina-validation:local
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends flang-19 \
    && rm -rf /var/lib/apt/lists/*
