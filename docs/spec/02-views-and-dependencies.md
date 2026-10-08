# 02 · Views and dependencies

A view lets code work with data in place. Its type says what kind of access it permits; its dependencies say which owner's memory must remain available while the view is used. This chapter defines both, then describes the accessors that lend a place or return a view.

## Subchapters

- [Scoped values and types](02-views-and-dependencies/scoped-values.md)
- [Dependency rules](02-views-and-dependencies/dependency-rules.md)
- [Destruction, precise dependencies and `rebind`](02-views-and-dependencies/dependency-lifetimes.md)
- [Projections and accessors](02-views-and-dependencies/projections-and-accessors.md)
