/// Gives an enum of diagnostic codes a `number`, a `message`, a `severity` and `labels`, made from the `@Code` on
/// each of its cases, and a `Label` enum with a case for each label any code declares.
@attached(member, names: named(number), named(message), named(severity), named(labels), named(Label))
public macro Diagnostics() = #externalMacro(module: "RayoDiagnosticsMacros", type: "DiagnosticsMacro")

/// Gives a case of a `@Diagnostics` enum its number, and its message as an error, in which `{label}` stands for the
/// case's value of that label, and `{label.property}` for that property of the value. `labels` gives, by name, the
/// text of each label that the code's diagnostics put on a place beside their own; a text may name the case's
/// values as the message does.
@attached(peer)
public macro Code(_ number: Int, error message: String, labels: [String: String] = [:]) =
    #externalMacro(module: "RayoDiagnosticsMacros", type: "CodeMacro")

/// Gives a case of a `@Diagnostics` enum its number, its message as a warning, and its labels, as the `@Code` for an
/// error does.
@attached(peer)
public macro Code(_ number: Int, warning message: String, labels: [String: String] = [:]) =
    #externalMacro(module: "RayoDiagnosticsMacros", type: "CodeMacro")
