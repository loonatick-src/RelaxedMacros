import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct RelaxedPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RelaxedExpressionMacro.self,
    ]
}
