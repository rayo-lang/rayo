# 04 · Types

```swift
struct Particle(var pos: Vec3, var vel: Vec3, var life: Float)     // 28 bytes, with no padding

let dt: Float = 0.016                             // a literal takes its type from context; with none, 0.016 is a Double
let n: Int32 = 1000
let total: Int = n                                // lossless widening is implicit
let scale = Float(total) / 1024                   // a conversion that may round is spelled out

var particles = SoA<Particle>(capacity: 100_000)  // one buffer per field, still used with field syntax
for p in &particles {
    p.pos += p.vel * dt                           // vector math: no hidden calls
}

var widgets = List<Box<any Widget>>()             // dynamic dispatch and its heap allocation, both in the type
log("scale \(scale)")                             // formatted straight into the log: no allocation
```

## Subchapters

- [Numbers and math](04-types/numbers-and-math.md)
- [Structs and layout](04-types/structs.md)
- [Enums and control flow](04-types/enums.md)
- [Collections and iteration](04-types/collections.md)
- [Plain and specialized data layouts](04-types/data-layout.md)
