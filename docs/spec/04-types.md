# 04 · Types

Types tell the compiler what a value contains and which operations are valid. They also make many costs visible in Rayo: a conversion that may lose information is explicit, and an owning collection is a different type from a view of its elements. The examples below show those choices in declarations, arithmetic and iteration.

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
```

`Particle` fixes the fields of each value. The type on `dt` gives its literal a `Float` value; widening `n` to `Int` is implicit, while converting that `Int` back to `Float` is written out because it may round. `SoA<Particle>` changes how the particles are stored, with one buffer per field, but the loop still uses the fields declared on `Particle`.

## Subchapters

- [Numbers and math](04-types/numbers-and-math.md)
- [Structs and layout](04-types/structs.md)
- [Enums and control flow](04-types/enums.md)
- [Collections and iteration](04-types/collections.md)
- [Plain and specialized data layouts](04-types/data-layout.md)
