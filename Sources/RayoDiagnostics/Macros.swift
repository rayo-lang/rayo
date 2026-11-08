/// Gives an enum of diagnostic codes a `number` and a `message`, made from the `@Code` on each of its
/// cases.
@attached(member, names: named(number), named(message))
public macro Diagnostics() = #externalMacro(module: "RayoDiagnosticsMacros", type: "DiagnosticsMacro")

/// Gives a case of a `@Diagnostics` enum its number and its message, in which `{label}` stands for the
/// case's value of that label.
@attached(peer)
public macro Code(_ number: Int, error message: String) =
    #externalMacro(module: "RayoDiagnosticsMacros", type: "CodeMacro")

/// Gives a case of a `@Diagnostics` enum its number, and a message that names what isn't supported yet
/// and says so. `{label}` in `what` stands for the case's value of that label.
@attached(peer)
public macro Code(_ number: Int, notSupported what: String) =
    #externalMacro(module: "RayoDiagnosticsMacros", type: "CodeMacro")
