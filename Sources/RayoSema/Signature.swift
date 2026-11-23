import RayoCheckedProgram

/// A function's name, its parameters' labels, conventions and types, and its result type: everything a call is
/// checked against, apart from the function's body. Each function the file declares has one, and so does each
/// struct's primary initializer, each of the prelude's built-ins, and an array's `init(repeating:)`.
struct Signature: CustomStringConvertible {
    var name: String
    var target: CallTarget
    var parameters: [Parameter]
    var result: DeclaredResult

    /// The name and the parameters, such as `f(_: Int, by: Bool)`, which tell the function apart from every other.
    var description: String {
        FunctionDeclaration.name(name, parameters: parameters.map { (label: $0.label, type: $0.spelledType) })
    }

    /// Whether the declaration failed: a parameter's type or the written result type isn't known, which was reported
    /// there.
    var hasFailed: Bool {
        parameters.contains { $0.type == nil } || result.hasFailed
    }

    /// Whether the other signature takes arguments with the same labels and types, and takes each as its own
    /// parameter does, so no call could tell the two apart. A type that isn't known matches none, since its error was
    /// already reported where it is written.
    func takesArguments(like other: Signature) -> Bool {
        parameters.count == other.parameters.count && zip(parameters, other.parameters).allSatisfy { mine, theirs in
            mine.label == theirs.label && mine.convention == theirs.convention && mine.type != nil
                && mine.type == theirs.type
        }
    }

    /// Whether a parameter that borrows its argument takes each of `arguments` that the source writes as a `&` of a
    /// place. A parameter that owns its argument takes no reference, though the place's type may fit it.
    func takesReferences(in arguments: [CheckedValue]) -> Bool {
        parameters.count == arguments.count && zip(parameters, arguments).allSatisfy { parameter, argument in
            parameter.convention == .borrowed || !argument.lendsPlace
        }
    }

    /// Whether the function takes each argument with no conversion, where `areLent` says of each in turn whether it
    /// counts as a `&` of a place: one that does goes to a parameter that borrows it, and one that doesn't to a
    /// parameter that owns it, since lending a bare place to a parameter that borrows it is a conversion.
    func takesUnconverted(_ areLent: [Bool]) -> Bool {
        parameters.count == areLent.count && zip(parameters, areLent).allSatisfy { parameter, isLent in
            (parameter.convention == .borrowed) == isLent
        }
    }

    /// Whether the function is one of the prelude's built-ins.
    var isBuiltin: Bool {
        if case .callee(.builtin) = target { true } else { false }
    }

    /// Whether values of `types`, in order, fit the parameters. A parameter whose type isn't known takes none.
    func takes(_ types: [RayoType]) -> Bool {
        parameters.count == types.count && zip(parameters, types).allSatisfy { parameter, type in
            parameter.type.map { TypeFit.fits(type, $0) } ?? false
        }
    }

    /// Whether a call may pass arguments with these labels, in this order.
    func takesLabels(_ labels: [String?]) -> Bool {
        parameters.count == labels.count && zip(parameters, labels).allSatisfy { $0.label == $1 }
    }

    /// Whether each argument the filter picks has the type of its parameter, taken in order, where `declarations`
    /// gives the members an implicit member names. A parameter whose type isn't known takes any argument, so a
    /// mistake in the declaration gives no further error at each call.
    func takes(_ arguments: [CheckedValue], in declarations: Declarations,
               where isConsidered: (CheckedValue) -> Bool) -> Bool {
        parameters.count == arguments.count && zip(parameters, arguments).allSatisfy { parameter, argument in
            guard isConsidered(argument), let type = parameter.type else { return true }
            return argument.fits(type, in: declarations)
        }
    }
}

extension Signature {
    /// The signature of a built-in function, under the name a call writes to reach it.
    init(of builtin: Builtin) {
        self.init(name: builtin.name.spelling, target: .callee(.builtin(builtin)),
                  parameters: builtin.parameters.map(Parameter.init), result: .type(builtin.result))
    }

    /// The signature of `init(repeating:)` of the array of `count` values of `element`, which makes the array with
    /// each element a copy of its one argument. Its parameter owns the argument, so a call gives a place with nothing
    /// written, as it gives any parameter that owns its argument.
    init(fillingArrayOf count: Int, _ element: RayoType) {
        let parameter = Parameter(FunctionParameter(label: "repeating", convention: .owned, type: element))
        self.init(name: Member.initializerName, target: .filledArray, parameters: [parameter],
                  result: .type(.array(count: count, element: element)))
    }
}
