/// Gives an enum of diagnostic codes a `number` and a `message`, made from the `@Code` on each of its
/// cases.
@attached(member, names: named(number), named(message))
public macro Diagnostics() = #externalMacro(module: "RayoDiagnosticsMacros", type: "DiagnosticsMacro")

/// Gives a case of a `@Diagnostics` enum its number and its message, in which `{label}` stands for the
/// case's value of that label, and `{label.property}` for that property of the value.
@attached(peer)
public macro Code(_ number: Int, error message: String) =
    #externalMacro(module: "RayoDiagnosticsMacros", type: "CodeMacro")
