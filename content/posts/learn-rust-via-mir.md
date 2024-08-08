+++
title = 'Learn Rust via MIR'
date = 2024-08-07T22:48:38-04:00
draft = false
+++

## Background 

MIR stands for Mid-Level-IR and is an Intermediate representation that sits between Rust HIR and LLVM IR. An excellent source for learning more about MIR is [Introducing MIR](https://blog.rust-lang.org/2016/04/19/MIR.html). 


I am a systems programmer whose prior systems languages are C and C++. As a systems programmer I am always curious to understand the cost of things and to have some idea of how they are implemented internally. Recently I have been learning Rust and have been looking to bootstrap my understanding of Rust semantics and how they are implemented. One technique that worked well for me is to look at the MIR emitted by Rust for simple snippets of code and understand the semantics of what is going on from the MIR. Given how readable and explicit MIR is, I found this approach a much faster way of piercing through syntax and implementation to the underlying semantics. Will share some examples that illustrate this process.


### Empty function

```rust
fn f() {}

fn main() {}
```

translates to
```rust
fn f() -> () {
    let mut _0: ();

    bb0: {
        return;
    }
}

fn main() -> () {
    let mut _0: ();

    bb0: {
        return;
    }
}

```

### Identity function

```rust
fn f(x: i32) -> i32 {
    x
}

fn main() {}
```

translates to 
```rust
fn f(_1: i32) -> i32 {
    debug x => _1;
    let mut _0: i32;

    bb0: {
        _0 = _1;
        return;
    }
}

fn main() -> () {
    let mut _0: ();

    bb0: {
        return;
    }
}
```
