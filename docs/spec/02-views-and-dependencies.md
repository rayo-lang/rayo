# 02 · Views and dependencies

A **view** borrows memory that another value owns. **`Scoped`** limits where a value can live. A view into memory that can be freed is scoped, but a view of immortal data can be unscoped, and a type can be scoped without borrowing memory ([Scoped values](02-views-and-dependencies/scoped-values.md#scoped-values)). The view's type says what kind of access it permits; its dependencies say which owner's memory must remain available while the view is used. This chapter defines both, then describes the accessors that lend a place or return a view.

## Subchapters

- [Scoped values and types](02-views-and-dependencies/scoped-values.md)
- [Dependency rules](02-views-and-dependencies/dependency-rules.md)
- [Destruction, precise dependencies and `rebind`](02-views-and-dependencies/dependency-lifetimes.md)
- [Projections and accessors](02-views-and-dependencies/projections-and-accessors.md)
