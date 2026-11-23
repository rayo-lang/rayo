import RayoCheckedProgram

/// A state that says which locals some path to a point retired, as the local-life check carries it through a body.
protocol RetiredLocalSet: DataflowState where Function == Void {
    func contains(_ local: LocalID) -> Bool
}
