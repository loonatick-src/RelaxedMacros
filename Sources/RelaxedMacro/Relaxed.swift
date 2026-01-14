// Re-export RealModule so users get access to Relaxed operations
@_exported import RealModule

/// Transforms arithmetic expressions to use relaxed floating-point operations.
///
/// The `#relaxed` macro rewrites binary arithmetic operators to use
/// `Relaxed.sum` and `Relaxed.product` from swift-numerics, enabling
/// more aggressive compiler optimizations.
///
/// ## Example
/// ```swift
/// let x1 = #relaxed(a + b * c)
/// // Expands to: Relaxed.sum(a, Relaxed.product(b, c))
/// let x2 = #relaxed(a * b / c)
/// // Expands to: Relaxed.product(a, b / c)
/// let x3 = #relaxed(sin(a + b * c))
/// // Expands to: sin(Relaxed.sum(a, Relaxed.product(b, c)))
/// ```
///
/// ## Supported Operators
/// - `+` → `Relaxed.sum(a, b)`
/// - `-` → `Relaxed.sum(a, -b)`
/// - `*` → `Relaxed.product(a, b)`
///
/// ## Notes
/// Relaxed operations allow the compiler to reorder and reassociate
/// floating-point operations, which can improve performance but may
/// produce slightly different results due to floating-point semantics.
@freestanding(expression)
public macro relaxed<T>(_ expression: T) -> T = #externalMacro(
    module: "RelaxedMacroImplementation",
    type: "RelaxedExpressionMacro"
)
