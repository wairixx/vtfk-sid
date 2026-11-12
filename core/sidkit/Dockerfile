FROM rust:1.79-slim-bookworm AS builder

WORKDIR /project

# Cache dependencies before copying application sources
COPY Cargo.toml Cargo.lock ./

RUN mkdir src \
    && printf 'fn main() {}\n' > src/main.rs \
    && cargo build --locked --release \
    && rm -rf src

# Compile the actual application using cached dependencies
COPY src/ ./src/

RUN touch src/main.rs \
    && cargo build --locked --release

FROM debian:12-slim

COPY --from=builder /project/target/release/sidkit /usr/local/bin/sidkit

ENTRYPOINT ["/usr/local/bin/sidkit"]
