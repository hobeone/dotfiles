---
name: rust-async-patterns
description: Best practices and design patterns for asynchronous Rust using tokio, async-std, futures, and async/await syntax.
---

# Rust Async Patterns

Best practices for asynchronous programming in Rust.

## Core Concepts

- **Futures & Poll**: `Future` trait execution model driven by `Waker` and executors.
- **Tokio Runtime**: Multi-threaded work-stealing executor and I/O driver.
- **Pin & Unpin**: Guaranteeing memory location stability for self-referential async states.

## Key Guidelines

1. Never hold standard `std::sync::Mutex` across an `.await` boundary — use `tokio::sync::Mutex` or restructure scope.
2. Handle cancellation safely — futures can be dropped at any `.await` point.
3. Prefer `tokio::spawn` for independent concurrent tasks, or `futures::join!` / `tokio::select!` for co-located tasks.
4. Avoid blocking the async reactor loop — offload CPU-intensive or blocking synchronous I/O to `tokio::task::spawn_blocking`.
