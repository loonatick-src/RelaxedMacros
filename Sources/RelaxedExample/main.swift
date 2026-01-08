import Relaxed
import Foundation

@inlinable
func saxpyFoldRelaxed(_ x: [Float], _ y: [Float], _ a: Float) -> Float {
    precondition(x.count == y.count)
    var result: Float = 0
    for i in x.indices {
        #relaxed(result += a * x[i] + y[i])
    }
    return result
}

@inlinable
func saxpyFold(_ x: [Float], _ y: [Float], _ a: Float) -> Float {
    precondition(x.count == y.count)
    var result: Float = 0
    for i in x.indices {
        result += a * x[i] + y[i]
    }
    return result
}

@inlinable
func benchmark(_ name: String, iterations: Int, _ body: () -> Float) {
    var wallTimeMillis: [Double] = []
    wallTimeMillis.reserveCapacity(iterations)

    var result: Float = 0
    for _ in 0..<iterations {
        let start = DispatchTime.now()
        result = body()
        let end = DispatchTime.now()
        let nanos = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
        wallTimeMillis.append(nanos / 1_000_000) // Convert to milliseconds
    }

    let mean = wallTimeMillis.reduce(0, +) / Double(wallTimeMillis.count)
    let variance = wallTimeMillis.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(wallTimeMillis.count - 1)
    let stddev = variance.squareRoot()

    print("\(name):")
    print("  Mean:   \(String(format: "%.3f", mean)) ms")
    print("  Stddev: \(String(format: "%.3f", stddev)) ms")
    print("  Result: \(result)")
}

// Generate random input data
let n = 10_000_000
print("Generating \(n) random elements...")
let x = (0..<n).map { _ in Float.random(in: -1.0...1.0) }
let y = (0..<n).map { _ in Float.random(in: -1.0...1.0) }
let a = Float.random(in: -1.0...1.0)

let iterations = 10
print("Running \(iterations) iterations each...\n")

benchmark("saxpyFold", iterations: iterations) {
    saxpyFold(x, y, a)
}

print()

benchmark("saxpyFoldRelaxed", iterations: iterations) {
    saxpyFoldRelaxed(x, y, a)
}
