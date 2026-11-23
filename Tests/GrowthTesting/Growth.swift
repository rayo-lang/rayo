/// The fastest time `measure` gives over `short` and over `long`, of `runs` runs each. The runs take the two in turn,
/// so that a runner busy with other work during one run slows neither one's time.
package func fastestTimes<Input, Failure: Error>(
    over short: Input, _ long: Input, runs: Int, measuring measure: (Input) throws(Failure) -> Duration,
) throws(Failure) -> (short: Duration, long: Duration) {
    var shortTime = Duration.seconds(Int64.max)
    var longTime = Duration.seconds(Int64.max)
    for _ in 0..<runs {
        shortTime = min(shortTime, try measure(short))
        longTime = min(longTime, try measure(long))
    }
    return (shortTime, longTime)
}
