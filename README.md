# Relaxed

A Swift macro that transforms arithmetic expressions to use relaxed floating-point operations from [swift-numerics](https://github.com/apple/swift-numerics).

## Overview

The `#relaxed` macro rewrites binary arithmetic operators to use `Relaxed.sum` and `Relaxed.product`, enabling more aggressive compiler optimizations. Relaxed operations allow the compiler to reorder and reassociate floating-point operations, which can improve performance but may produce slightly different results due to floating-point semantics.

## Usage

Add `RelaxedMacros` to your `Package.swift` (**TODO:** cut a release tag)

```swift
dependencies: [
    .package(url: "https://github.com/loonatick-src/RelaxedMacros.git", branch: "main")
]
```
or to use a specific commit
```swift
dependencies: [
    .package(url: "https://github.com/loonatick-src/RelaxedMacros.git", revision: "1bfad5b375fc46755f71c99ee39808a04f12f63a")
]
```


Then add it as a dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Relaxed"]
)
```

Import the module and wrap floating point arithmetic expressions with the `#relaxed` macro:

```swift
import Relaxed

let a: Double = 1.0
let b: Double = 2.0
let c: Double = 3.0

let x1 = #relaxed(a + b * c)
// Expands to: Relaxed.sum(a, Relaxed.product(b, c))
let x2 = #relaxed(a * b / c)
// Expands to: Relaxed.product(a, b / c)
let x3 = #relaxed(sin(a + b * c))
// Expands to: sin(Relaxed.sum(a, Relaxed.product(b, c)))
```

## Why Use Relaxed Operations?

Standard IEEE 754 floating-point arithmetic requires strict ordering of operations, which can prevent certain compiler optimizations. Relaxed operations tell the compiler it's okay to:

- Reorder additions and multiplications
- Reassociate nested operations
- Use fused multiply-add (FMA) instructions

This can lead to significant performance improvements in numerical code, especially in tight loops and vector operations.

Consider the following example.

```swift
import Relaxed

public func f1(_ a: Float, _ b: Float, _ c: Float) -> Float {
    #relaxed(a * b + c)
}

public func f2(_ a: Float, _ b: Float, _ c: Float) -> Float {
    a * b + c
}
```

This is the generated code on an ARMv8-A machine when the `fmadd` is available.
```
<_$s14RelaxedExample2f2yS2f_S2ftF>:
fmul    s0, s0, s1
fadd    s0, s0, s2
ret

<_$s14RelaxedExample2f1yS2f_S2ftF>:
fmadd   s0, s0, s1, s2
ret
```

Consider a more involved example. We have two implementations of the same function - the only difference between them being that one wraps
the floating point arithmetic operations in a `#relaxed` macro invocation.
```swift
@inlinable
func saxpyFold(_ x: [Float], _ y: [Float], _ a: Float) -> Float {
    precondition(x.count == y.count)
    var result: Float = 0
    for i in x.indices {
        result += a * x[i] + y[i]
    }
    return result
}

/// Same function, but uses `#relaxed`
@inlinable
func saxpyFoldRelaxed(_ x: [Float], _ y: [Float], _ a: Float) -> Float {
    precondition(x.count == y.count)
    var result: Float = 0
    for i in x.indices {
        #relaxed(result += a * x[i] + y[i])
    }
    return result
}
```

Benchmark result (M3Max MacBook Pro):

```
saxpyFold:
  Mean:   7.835 ± 0.744 ms
  Result: 641.4162

saxpyFoldRelaxed:
  Mean:   0.994 ± 0.017 ms
  Result: 641.35
```

~7.8x speedup, with the result matching up to two decimal places for this particular randomly generated input.
Why does this happen? Consider the primary loop within the generated code for both of those functions.


```
;; saxpyFold
loop:
ldp     q2, q3, [x10, #-0x10]
fmul.4s v2, v2, v0[0]         ;; v2 = a * x[i:i+4]
fmul.4s v3, v3, v0[0]         ;; v3 = a * x[i+4:i+8]  (loop unrolling)
ldp     q4, q5, [x11, #-0x10]
fadd.4s v2, v2, v4            ;; v2 = v2 + y[i:i+4]
mov     s4, v2[3]
mov     s6, v2[2]
mov     s7, v2[1]
fadd.4s v3, v3, v5            ;; v3 = v3 + y[i+4:i+8]
mov     s5, v3[3]
mov     s16, v3[2]
mov     s17, v3[1]
fadd    s1, s1, s2            ;; horizontal add (hadd) v2 and v3 (∵ reassociation forbidden)
fadd    s1, s1, s7
fadd    s1, s1, s6
fadd    s1, s1, s4
fadd    s1, s1, s3
fadd    s1, s1, s17
fadd    s1, s1, s16
fadd    s1, s1, s5
add     x10, x10, #0x20
add     x11, x11, #0x20
subs    x12, x12, #0x8
b.ne    loop
```
SIMD instructions `fmul.4s` and `fadd.4s` can be seen in the codegen of `saxpyFold` (i.e. without relaxed operations), but
immediately afterwards it performs individual scalar additions
([horizontal adds](https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html#techs=AVX_512&text=_mm512_reduce_add_ps&ig_expand=5303)).
The implementation using relaxed operations lowers to FMA instructions where possible, and the horizontal add is moved outside the loop (not shown in the codegen).
See also a simulated execution of equivalent x86-64 machine code at uica.uops.info for a deeper analysis
([link](https://uica.uops.info/?code=%23%20Register%20mapping%3A%0D%0A%20%20%23%20xmm0%20%3D%20a%20(broadcast%20to%20all%20lanes)%0D%0A%20%20%23%20rdi%20%3D%20x%20array%20pointer%0D%0A%20%20%23%20rsi%20%3D%20y%20array%20pointer%0D%0A%20%20%23%20rcx%20%3D%20loop%20counter%0D%0A%20%20%23%20xmm1%20%3D%20scalar%20accumulator%0D%0A%0D%0A%20%20.loop%3A%0D%0A%20%20%20%20%20%20vmovups%20xmm2%2C%20%5Brdi%5D%20%20%20%20%20%20%20%20%20%20%20%23%20v2%20%3D%20x%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm3%2C%20%5Brdi%2B16%5D%20%20%20%20%20%20%20%20%23%20v3%20%3D%20x%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vmulps%20%20xmm2%2C%20xmm2%2C%20xmm0%20%20%20%20%20%20%23%20v2%20%3D%20a%20*%20x%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vmulps%20%20xmm3%2C%20xmm3%2C%20xmm0%20%20%20%20%20%20%23%20v3%20%3D%20a%20*%20x%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm4%2C%20%5Brsi%5D%20%20%20%20%20%20%20%20%20%20%20%23%20v4%20%3D%20y%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm5%2C%20%5Brsi%2B16%5D%20%20%20%20%20%20%20%20%23%20v5%20%3D%20y%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vaddps%20%20xmm2%2C%20xmm2%2C%20xmm4%20%20%20%20%20%20%23%20v2%20%3D%20v2%20%2B%20y%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vaddps%20%20xmm3%2C%20xmm3%2C%20xmm5%20%20%20%20%20%20%23%20v3%20%3D%20v3%20%2B%20y%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20%23%20Horizontal%20add%20(reassociation%20forbidden)%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm2%20%20%20%20%20%20%23%20add%20v2%5B0%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm2%2C%200x55%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v2%5B1%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm2%2C%200xAA%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v2%5B2%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm2%2C%200xFF%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v2%5B3%5D%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm3%20%20%20%20%20%20%23%20add%20v3%5B0%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm3%2C%200x55%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v3%5B1%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm3%2C%200xAA%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v3%5B2%5D%0D%0A%20%20%20%20%20%20vpshufd%20xmm6%2C%20xmm3%2C%200xFF%0D%0A%20%20%20%20%20%20vaddss%20%20xmm1%2C%20xmm1%2C%20xmm6%20%20%20%20%20%20%23%20add%20v3%5B3%5D%0D%0A%20%20%20%20%20%20add%20%20%20%20%20rdi%2C%2032%0D%0A%20%20%20%20%20%20add%20%20%20%20%20rsi%2C%2032%0D%0A%20%20%20%20%20%20sub%20%20%20%20%20rcx%2C%208%0D%0A%20%20%20%20%20%20jne%20%20%20%20%20.loop&syntax=asIntel&uArchs=RKL&tools=uiCA&alignment=0)).
Click "Run!", and then "Open Trace"

Now, consider the codegen on using relaxed operations.
```
;; saxpyFoldRelaxed
vloop:
ldp     q4, q5, [x10, #-0x10]
ldp     q6, q7, [x11, #-0x10]
fmla.4s v6, v1, v4            ;; v6 = a * x[i:i+4] + y[i:i+4]
fmla.4s v7, v1, v5            ;; v7 = a * x[i+4:i+8] + y[i+4:i+8]
fadd.4s v2, v2, v6            ;; a1[i:i+4] += v6    (vector register accumulator)
fadd.4s v3, v3, v7            ;; a2[i+i+4] += v7    (vector register accumulator)
add     x10, x10, #0x20
add     x11, x11, #0x20
subs    x12, x12, #0x8
b.ne    vloop

;; result = hadd(a1) + hadd(a2) after the loop
```

Two important differences from the previous codegen.
1. The loop is fully vectorized, there are no scalar operations (for horizontal adds) in the loop itself
2. Fused multiply add (FMA) instructions (`fmla.4s`) are used instead of individual multiply (`fmul.4s`) and add (`fadd.4s`) instructions

See also the equivalent x86-64 simulation: [link](https://uica.uops.info/?code=%23%20Register%20mapping%3A%0D%0A%20%20%23%20xmm0%20%3D%20a%20(broadcast%20to%20all%20lanes)%0D%0A%20%20%23%20rdi%20%3D%20x%20array%20pointer%0D%0A%20%20%23%20rsi%20%3D%20y%20array%20pointer%0D%0A%20%20%23%20rcx%20%3D%20loop%20counter%0D%0A%20%20%23%20xmm2%2C%20xmm3%20%3D%20vector%20accumulators%0D%0A%0D%0A%20%20.vloop%3A%0D%0A%20%20%20%20%20%20vmovups%20xmm4%2C%20%5Brdi%5D%20%20%20%20%20%20%20%20%20%20%20%23%20x%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm5%2C%20%5Brdi%2B16%5D%20%20%20%20%20%20%20%20%23%20x%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm6%2C%20%5Brsi%5D%20%20%20%20%20%20%20%20%20%20%20%23%20y%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vmovups%20xmm7%2C%20%5Brsi%2B16%5D%20%20%20%20%20%20%20%20%23%20y%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vfmadd231ps%20xmm6%2C%20xmm0%2C%20xmm4%20%20%23%20v6%20%3D%20a%20*%20x%5Bi%3Ai%2B4%5D%20%2B%20y%5Bi%3Ai%2B4%5D%0D%0A%20%20%20%20%20%20vfmadd231ps%20xmm7%2C%20xmm0%2C%20xmm5%20%20%23%20v7%20%3D%20a%20*%20x%5Bi%2B4%3Ai%2B8%5D%20%2B%20y%5Bi%2B4%3Ai%2B8%5D%0D%0A%20%20%20%20%20%20vaddps%20%20xmm2%2C%20xmm2%2C%20xmm6%20%20%20%20%20%20%23%20acc1%20%2B%3D%20v6%0D%0A%20%20%20%20%20%20vaddps%20%20xmm3%2C%20xmm3%2C%20xmm7%20%20%20%20%20%20%23%20acc2%20%2B%3D%20v7%0D%0A%20%20%20%20%20%20add%20%20%20%20%20rdi%2C%2032%0D%0A%20%20%20%20%20%20add%20%20%20%20%20rsi%2C%2032%0D%0A%20%20%20%20%20%20sub%20%20%20%20%20rcx%2C%208%0D%0A%20%20%20%20%20%20jne%20%20%20%20%20.vloop%0D%0A%20%20%20%20%20%20%23%20result%20%3D%20hsum(xmm2)%20%2B%20hsum(xmm3)%20after%20loop&syntax=asIntel&uArchs=RKL&tools=uiCA&alignment=0&uiCAHtmlOptions=traceTable).


## Supported Operators

| Operator | Transformation |
|----------|----------------|
| `+` | `Relaxed.sum(a, b)` |
| `-` | `Relaxed.sum(a, -b)` |
| `*` | `Relaxed.product(a, b)` |
| others | Preserved as-is |

## Examples

### Basic Operations

```swift
// Addition
#relaxed(a + b)
// Expands to: Relaxed.sum(a, b)

// Subtraction
#relaxed(a - b)
// Expands to: Relaxed.sum(a, -b)

// Multiplication
#relaxed(a * b)
// Expands to: Relaxed.product(a, b)

// Division (not transformed)
#relaxed(a / b)
// Expands to: a / b
```

### Nested Expressions

```swift
// Mixed operations
#relaxed(a + b * c)
// Expands to: Relaxed.sum(a, Relaxed.product(b, c))

// Parenthesized expressions
#relaxed((a + b) * (c + d))
// Expands to: Relaxed.product(Relaxed.sum(a, b), Relaxed.sum(c, d))

// Complex expressions
#relaxed(a * b + c * d)
// Expands to: Relaxed.sum(Relaxed.product(a, b), Relaxed.product(c, d))
```

### Function Calls

Arithmetic expressions inside function calls are also transformed:

```swift
#relaxed(sin(a + b * c))
// Expands to: sin(Relaxed.sum(a, Relaxed.product(b, c)))

#relaxed(f(a + b, c * d))
// Expands to: f(Relaxed.sum(a, b), Relaxed.product(c, d))
```



## Wishlist/Near-Term Future Work
1. Support for `+=`, `-=`, `*=`
2. Rewrite references to operators, e.g. `array.reduce(0, +)` to `array.reduce(0, Relaxed.sum)` 

## License

3-Clause BSD License
