FROM rust:1.79 AS compiler

WORKDIR /project

RUN apt-get update \
    && apt-get install -y --no-install-recommends musl-tools \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add x86_64-unknown-linux-musl

# Cache dependencies before copying application sources
COPY Cargo.toml Cargo.lock ./

RUN mkdir src \
    && printf 'fn main() {}\n' > src/main.rs \
    && cargo build --locked --release \
       --target x86_64-unknown-linux-musl \
    && rm -rf src

# Compile the actual application using cached dependencies
COPY src/ ./src/

RUN cargo clean -p camera_audit \
       --release \
       --target x86_64-unknown-linux-musl \
    && cargo build --locked --release \
       --target x86_64-unknown-linux-musl


FROM scratch

COPY --from=compiler \
    /project/target/x86_64-unknown-linux-musl/release/camera_audit \
    /camera-audit

ENTRYPOINT ["/camera-audit"]
