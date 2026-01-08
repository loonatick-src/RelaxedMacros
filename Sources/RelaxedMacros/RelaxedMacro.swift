import SwiftSyntax
import SwiftSyntaxMacros

/// An expression macro that transforms arithmetic operators to use
/// `Relaxed.sum` and `Relaxed.product` from swift-numerics.
///
/// This enables the compiler to perform more aggressive floating-point
/// optimizations by using relaxed IEEE 754 semantics.
public struct RelaxedExpressionMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            throw MacroExpansionError.missingArgument
        }

        return rewriteExpression(argument)
    }
}

/// Recursively rewrites binary arithmetic operators to Relaxed function calls.
/// Handles the following cases:
/// (1) `InfixOperatorExprSyntax` - expressions with infix operators such as `x + y`, `2 * a - b` etc
/// (2) `TupleExprSyntax` - (e, e), (e, e, e) etc where e := InfixOperatorSyntax | TupleExprSyntax | FunctionCallExprSyntax
/// (3) `FunctionCallExprSyntax` - f(e), f(e, e) etc where e := InfixOperatorSyntax | TupleExprSyntax | FunctionCallExprSyntax
///
/// See https://swiftpackageindex.com/swiftlang/swift-syntax/602.0.0/documentation/swiftsyntax/exprsyntax for a complete list of
/// possible `ExprSyntax` subtypes.
private func rewriteExpression(_ expr: ExprSyntax) -> ExprSyntax {
    // (1) Handle infix operator expressions (binary operators)
    if let infixExpr = expr.as(InfixOperatorExprSyntax.self) {
        return rewriteInfixOperator(infixExpr)
    }

    // (2) Handle tuple expressions (parenthesized expressions)
    if let tupleExpr = expr.as(TupleExprSyntax.self) {
        let rewrittenElements = tupleExpr.elements.map { element in
            element.with(\.expression, rewriteExpression(element.expression))
        }
        return ExprSyntax(tupleExpr.with(\.elements, LabeledExprListSyntax(rewrittenElements)))
    }

    // (3) Handle function call expressions (to rewrite arguments)
    if let callExpr = expr.as(FunctionCallExprSyntax.self) {
        let rewrittenArgs = callExpr.arguments.map { arg in
            arg.with(\.expression, rewriteExpression(arg.expression))
        }
        return ExprSyntax(callExpr.with(\.arguments, LabeledExprListSyntax(rewrittenArgs)))
    }

    // Return unchanged for other expression types
    return expr
}

/// Rewrites a single infix operator expression.
private func rewriteInfixOperator(_ node: InfixOperatorExprSyntax) -> ExprSyntax {
    // Recursively process the left and right operands
    let leftOperand = rewriteExpression(node.leftOperand)
    let rightOperand = rewriteExpression(node.rightOperand)

    // Get the operator token
    guard let operatorExpr = node.operator.as(BinaryOperatorExprSyntax.self) else {
        // Not a binary operator we recognize, return with rewritten operands
        return ExprSyntax(
            node.with(\.leftOperand, leftOperand)
                .with(\.rightOperand, rightOperand)
        )
    }

    let operatorText = operatorExpr.operator.text

    switch operatorText {
    case "+":
        // a + b → Relaxed.sum(a, b)
        return makeRelaxedCall("sum", leftOperand, rightOperand)

    case "-":
        // a - b → Relaxed.sum(a, -b)
        let negatedRight = ExprSyntax(
            PrefixOperatorExprSyntax(
                operator: .prefixOperator("-"),
                expression: parenthesizeIfNeeded(rightOperand)
            )
        )
        return makeRelaxedCall("sum", leftOperand, negatedRight)

    case "*":
        // a * b → Relaxed.product(a, b)
        return makeRelaxedCall("product", leftOperand, rightOperand)

    case "+=":
        // x += y → x = Relaxed.sum(x, y)
        return makeAssignment(leftOperand, makeRelaxedCall("sum", leftOperand, rightOperand))

    case "-=":
        // x -= y → x = Relaxed.sum(x, -y)
        let negatedRight = ExprSyntax(
            PrefixOperatorExprSyntax(
                operator: .prefixOperator("-"),
                expression: parenthesizeIfNeeded(rightOperand)
            )
        )
        return makeAssignment(leftOperand, makeRelaxedCall("sum", leftOperand, negatedRight))

    case "*=":
        // x *= y → x = Relaxed.product(x, y)
        return makeAssignment(leftOperand, makeRelaxedCall("product", leftOperand, rightOperand))

    default:
        // Unknown operator, preserve it but with rewritten operands
        return ExprSyntax(
            node.with(\.leftOperand, leftOperand)
                .with(\.rightOperand, rightOperand)
        )
    }
}

/// Creates a `Relaxed.functionName(left, right)` call expression.
private func makeRelaxedCall(
    _ functionName: String,
    _ left: ExprSyntax,
    _ right: ExprSyntax
) -> ExprSyntax {
    let memberAccess = MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier("Relaxed")),
        period: .periodToken(),
        declName: DeclReferenceExprSyntax(baseName: .identifier(functionName))
    )

    let arguments = LabeledExprListSyntax([
        LabeledExprSyntax(
            expression: left.trimmed,
            trailingComma: .commaToken(trailingTrivia: .space)
        ),
        LabeledExprSyntax(
            expression: right.trimmed
        )
    ])

    return ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(memberAccess),
            leftParen: .leftParenToken(),
            arguments: arguments,
            rightParen: .rightParenToken()
        )
    )
}

/// Creates an assignment expression: `target = value`
private func makeAssignment(_ target: ExprSyntax, _ value: ExprSyntax) -> ExprSyntax {
    ExprSyntax(
        InfixOperatorExprSyntax(
            leftOperand: target.trimmed,
            operator: ExprSyntax(AssignmentExprSyntax()),
            rightOperand: value
        )
    )
}

/// Wraps an expression in parentheses if it's a complex expression.
private func parenthesizeIfNeeded(_ expr: ExprSyntax) -> ExprSyntax {
    // If it's already simple (identifier, literal, or already parenthesized), return as-is
    if expr.is(DeclReferenceExprSyntax.self) ||
       expr.is(IntegerLiteralExprSyntax.self) ||
       expr.is(FloatLiteralExprSyntax.self) ||
       expr.is(TupleExprSyntax.self) ||
       expr.is(FunctionCallExprSyntax.self) {
        return expr
    }

    // Wrap complex expressions in parentheses
    return ExprSyntax(
        TupleExprSyntax(
            leftParen: .leftParenToken(),
            elements: LabeledExprListSyntax([
                LabeledExprSyntax(expression: expr.trimmed)
            ]),
            rightParen: .rightParenToken()
        )
    )
}

enum MacroExpansionError: Error, CustomStringConvertible {
    case missingArgument

    var description: String {
        switch self {
        case .missingArgument:
            return "#relaxed requires an expression argument"
        }
    }
}
