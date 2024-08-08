+++
title = 'Learn Rust via MIR'
date = 2024-08-07T22:48:38-04:00
draft = false
+++

## Background 

MIR stands for Mid-Level-IR and is an Intermediate representation that sits between Rust HIR and LLVM IR. An excellent source for learning more about MIR is [Introducing MIR](https://blog.rust-lang.org/2016/04/19/MIR.html). 


I am a systems programmer whose prior systems languages are C and C++. As a systems programmer I am always curious to understand the cost of things and to have some idea of how they are implemented internally. Recently I have been learning Rust and have been looking to bootstrap my understanding of Rust semantics. One technique that worked well for me is to look at the MIR emitted by Rust for small snippets of code and try to understand what is going in. Given how readable and explicit MIR is, I found this approach a much faster way of piercing through syntax and implementation to the underlying semantics. Will share some examples that illustrate this process.


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

### Variable declaration

```rust
fn f() {
    let x = 0;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    scope 1 {
        debug x => const 0_i32;
    }

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

### Multiple variables

```rust
fn f() {
    let x = 0;
    let y = 1;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    scope 1 {
        debug x => const 0_i32;
        scope 2 {
            debug y => const 1_i32;
        }
    }

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


### Copying


```rust
fn f() {
    let x = 1;
    let y = x;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    scope 1 {
        debug x => const 1_i32;
        let _1: i32;
        scope 2 {
            debug y => _1;
        }
    }

    bb0: {
        _1 = const 1_i32;
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

### Immutable borrowing

```rust
fn f() {
    let x = 1;
    let y = &x;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    let _1: i32;
    scope 1 {
        debug x => _1;
        let _2: &i32;
        scope 2 {
            debug y => _2;
        }
    }

    bb0: {
        _1 = const 1_i32;
        _2 = &_1;
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


### Mutable borrowing

```rust
fn f() {
    let mut x = 1;
    let y = &mut x;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    let mut _1: i32;
    scope 1 {
        debug x => _1;
        let _2: &mut i32;
        scope 2 {
            debug y => _2;
        }
    }

    bb0: {
        _1 = const 1_i32;
        _2 = &mut _1;
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

### Mutation via mutable borrow 
```rust
fn f() {
    let mut x = 1;
    let y = &mut x;
    *y = 2;
}

fn main() {}
```

expands to

```rust
fn f() -> () {
    let mut _0: ();
    let mut _1: i32;
    scope 1 {
        debug x => _1;
        let _2: &mut i32;
        scope 2 {
            debug y => _2;
        }
    }

    bb0: {
        _1 = const 1_i32;
        _2 = &mut _1;
        (*_2) = const 2_i32;
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

### Explicit drop
```rust
use std::mem;

fn f() -> i32 {
    let mut x = 1;
    let y = &mut x;
    *y = 2;
    mem::drop(y);
    let z = &mut x;
    *z = 5;
    x
}

fn main() {}
```

expands to

```rust
fn f() -> i32 {
    let mut _0: i32;
    let mut _1: i32;
    let _3: ();
    scope 1 {
        debug x => _1;
        let _2: &mut i32;
        scope 2 {
            debug y => _2;
            let _4: &mut i32;
            scope 3 {
                debug z => _4;
            }
        }
    }

    bb0: {
        _1 = const 1_i32;
        _2 = &mut _1;
        (*_2) = const 2_i32;
        _3 = std::mem::drop::<&mut i32>(move _2) -> [return: bb1, unwind continue];
    }

    bb1: {
        _4 = &mut _1;
        (*_4) = const 5_i32;
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
