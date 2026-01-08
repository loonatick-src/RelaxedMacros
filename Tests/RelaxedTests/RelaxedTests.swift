import Testing
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import RelaxedMacros
@testable import Relaxed

private let testMacros: [String: Macro.Type] = [
    "relaxed": RelaxedExpressionMacro.self,
]

@Suite("Relaxed Macro Tests")
struct RelaxedMacroTests {

    @Test("Addition transforms to Relaxed.sum")
    func additionTransform() {
        assertMacroExpansion(
            "#relaxed(a + b)",
            expandedSource: "Relaxed.sum(a, b)",
            macros: testMacros
        )
    }

    @Test("Multiplication transforms to Relaxed.product")
    func multiplicationTransform() {
        assertMacroExpansion(
            "#relaxed(a * b)",
            expandedSource: "Relaxed.product(a, b)",
            macros: testMacros
        )
    }

    @Test("Subtraction transforms to Relaxed.sum with negation")
    func subtractionTransform() {
        assertMacroExpansion(
            "#relaxed(a - b)",
            expandedSource: "Relaxed.sum(a, -b)",
            macros: testMacros
        )
    }

    @Test("Division is preserved")
    func divisionPreserved() {
        assertMacroExpansion(
            "#relaxed(a / b)",
            expandedSource: "a / b",
            macros: testMacros
        )
    }

    @Test("Nested expressions are transformed correctly")
    func nestedExpressions() {
        assertMacroExpansion(
            "#relaxed(a + b * c)",
            expandedSource: "Relaxed.sum(a, Relaxed.product(b, c))",
            macros: testMacros
        )
    }

    @Test("Complex nested expressions")
    func complexNestedExpressions() {
        assertMacroExpansion(
            "#relaxed((a + b) * (c + d))",
            expandedSource: "(Relaxed.product(Relaxed.sum(a, b), Relaxed.sum(c, d)))",
            macros: testMacros
        )
    }

    @Test("Mixed operations")
    func mixedOperations() {
        assertMacroExpansion(
            "#relaxed(a * b + c * d)",
            expandedSource: "Relaxed.sum(Relaxed.product(a, b), Relaxed.product(c, d))",
            macros: testMacros
        )
    }

    @Test("Function call")
    func functionCall() {
        assertMacroExpansion(
            "#relaxed(f(a + b, c * d))",
            expandedSource: "f(Relaxed.sum(a, b), Relaxed.product(c, d))",
            macros: testMacros
        )
    }

    @Test("Compound addition assignment")
    func compoundAdditionAssignment() {
        assertMacroExpansion(
            "#relaxed(x += y)",
            expandedSource: "x = Relaxed.sum(x, y)",
            macros: testMacros
        )
    }

    @Test("Compound subtraction assignment")
    func compoundSubtractionAssignment() {
        assertMacroExpansion(
            "#relaxed(x -= y)",
            expandedSource: "x = Relaxed.sum(x, -y)",
            macros: testMacros
        )
    }

    @Test("Compound multiplication assignment")
    func compoundMultiplicationAssignment() {
        assertMacroExpansion(
            "#relaxed(x *= y)",
            expandedSource: "x = Relaxed.product(x, y)",
            macros: testMacros
        )
    }

    @Test("Compound assignment with complex expression")
    func compoundAssignmentComplexExpression() {
        assertMacroExpansion(
            "#relaxed(x += a * b + c)",
            expandedSource: "x = Relaxed.sum(x, Relaxed.sum(Relaxed.product(a, b), c))",
            macros: testMacros
        )
    }
}

@Suite("Relaxed Runtime Tests")
struct RelaxedRuntimeTests {

    @Test("Macro produces correct runtime results for addition")
    func runtimeAddition() {
        let a: Double = 1.5
        let b: Double = 2.5
        let result = #relaxed(a + b)
        #expect(result == 4.0)
    }

    @Test("Macro produces correct runtime results for multiplication")
    func runtimeMultiplication() {
        let a: Double = 2.0
        let b: Double = 3.0
        let result = #relaxed(a * b)
        #expect(result == 6.0)
    }

    @Test("Macro produces correct runtime results for complex expressions")
    func runtimeComplexExpression() {
        let a: Double = 1.0
        let b: Double = 2.0
        let c: Double = 3.0
        let result = #relaxed(a + b * c)
        #expect(result == 7.0)
    }

    @Test("Macro produces correct runtime results for compound assignment")
    func runtimeCompoundAssignment() {
        var x: Double = 10.0
        let y: Double = 5.0
        #relaxed(x += y)
        #expect(x == 15.0)
    }

    @Test("Macro produces correct runtime results for compound assignment with complex expression")
    func runtimeCompoundAssignmentComplex() {
        var x: Double = 1.0
        let a: Double = 2.0
        let b: Double = 3.0
        let c: Double = 4.0
        #relaxed(x += a * b + c)
        #expect(x == 11.0)  // 1 + (2 * 3 + 4) = 1 + 10 = 11
    }
}
