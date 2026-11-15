package import CLLVM

/// An LLVM IR builder, which adds instructions at the end of the block it is positioned at.
public struct Builder: ~Copyable {
    package let ref: LLVMBuilderRef
    private let context: OwnedContext

    init(_ ref: LLVMBuilderRef, in context: OwnedContext) {
        self.ref = ref
        self.context = context
    }

    deinit {
        LLVMDisposeBuilder(ref)
    }

    /// Positions the builder at the end of `block`, so that each instruction it builds goes after the block's last.
    public func position(atEndOf block: BasicBlock) {
        LLVMPositionBuilderAtEnd(ref, block.ref)
    }

    /// The block the builder adds instructions to, which it must have been positioned at.
    public var insertionBlock: BasicBlock {
        BasicBlock(LLVMGetInsertBlock(ref))
    }

    // MARK: Integer arithmetic

    /// Builds `add`, which wraps on overflow.
    public func add<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildAdd(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `sub`, which wraps on overflow.
    public func subtract<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildSub(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `mul`, which wraps on overflow.
    public func multiply<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildMul(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `sdiv`, which LLVM leaves undefined for a zero divisor and for the one quotient that overflows.
    public func signedDivide<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildSDiv(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `srem`, whose result takes the dividend's sign, and which LLVM leaves undefined where `sdiv` is.
    public func signedRemainder<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildSRem(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `udiv`, which LLVM leaves undefined for a zero divisor.
    public func unsignedDivide<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildUDiv(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `urem`, which LLVM leaves undefined for a zero divisor.
    public func unsignedRemainder<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildURem(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `and`.
    public func and<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildAnd(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `or`.
    public func or<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildOr(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `xor`.
    public func xor<Integer: IntegerHandle>(_ left: Integer, _ right: Integer) -> Integer {
        integer(LLVMBuildXor(ref, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `icmp`, which gives whether `predicate` holds of `left` and `right`.
    public func compare<Integer: IntegerHandle>(
        _ predicate: IntegerPredicate, _ left: Integer, _ right: Integer,
    ) -> IntValue<I1> {
        IntValue(unchecked: LLVMBuildICmp(ref, predicate.llvmPredicate, left.anyValue.ref, right.anyValue.ref, ""))
    }

    /// Builds `select`, which gives `then` where `condition` holds and `otherwise` where it doesn't.
    public func select<Integer: IntegerHandle>(
        _ condition: IntValue<I1>, _ then: Integer, _ otherwise: Integer,
    ) -> Integer {
        integer(LLVMBuildSelect(ref, condition.ref, then.anyValue.ref, otherwise.anyValue.ref, ""))
    }

    // MARK: Integer conversions

    /// Builds `trunc`, which keeps the low bits of `value` that `type` holds. `type` must be narrower than `value`.
    public func truncate<To: IntegerTypeHandle>(_ value: some IntegerHandle, to type: To) -> To.Value {
        precondition(width(of: type) < width(of: value), "LLVM truncates an integer only to a narrower one")
        return integer(LLVMBuildTrunc(ref, value.anyValue.ref, type.anyType.ref, ""))
    }

    /// Builds `zext`, which pads `value` with zero bits to the width of `type`. `type` must be wider than `value`.
    public func zeroExtend<To: IntegerTypeHandle>(_ value: some IntegerHandle, to type: To) -> To.Value {
        precondition(width(of: type) > width(of: value), "LLVM zero-extends an integer only to a wider one")
        return integer(LLVMBuildZExt(ref, value.anyValue.ref, type.anyType.ref, ""))
    }

    /// Builds `sext`, which pads `value` with copies of its top bit to the width of `type`. `type` must be wider than
    /// `value`.
    public func signExtend<To: IntegerTypeHandle>(_ value: some IntegerHandle, to type: To) -> To.Value {
        precondition(width(of: type) > width(of: value), "LLVM sign-extends an integer only to a wider one")
        return integer(LLVMBuildSExt(ref, value.anyValue.ref, type.anyType.ref, ""))
    }

    /// The instruction `ref`, which gives an integer, as the kind of handle that holds it.
    private func integer<Integer: IntegerHandle>(_ ref: LLVMValueRef) -> Integer {
        // Each instruction that calls this gives an integer of its operands' width, or of the type it converts to,
        // which the handle's Swift type was inferred from.
        guard let integer = Integer(AnyValue(ref)) else { preconditionFailure("LLVM gives an integer of another width") }
        return integer
    }

    /// The width in bits of `value`, an integer.
    private func width(of value: some IntegerHandle) -> UInt32 {
        LLVMGetIntTypeWidth(LLVMTypeOf(value.anyValue.ref))
    }

    /// The width in bits of `type`, an integer type.
    private func width(of type: some IntegerTypeHandle) -> UInt32 {
        LLVMGetIntTypeWidth(type.anyType.ref)
    }

    // MARK: Aggregates and calls

    /// Builds `extractvalue`, which gives the field at `index` of `aggregate`.
    public func extractValue(from aggregate: AggregateValue, at index: Int) -> AnyValue {
        AnyValue(LLVMBuildExtractValue(ref, aggregate.ref, UInt32(index), ""))
    }

    /// Builds `insertvalue`, which gives `aggregate` with `value` in place of its field at `index`. `value` must be of
    /// that field's type.
    public func insertValue(
        _ value: some ValueHandle, into aggregate: AggregateValue, at index: Int,
    ) -> AggregateValue {
        AggregateValue(unchecked: LLVMBuildInsertValue(ref, aggregate.ref, value.anyValue.ref, UInt32(index), ""))
    }

    /// Builds `call`, which calls `function` with `arguments`, and gives its result, or nil where it returns
    /// nothing. The arguments carry `parameterAttributes`, a list for each in order, which may stop short of the last.
    @discardableResult
    public func call(
        _ function: Function, _ arguments: [any ValueHandle], parameterAttributes: [[Attribute]] = [],
    ) -> AnyValue? {
        // Build the call, whose instruction is its result, and give its arguments their attributes.
        var arguments = arguments.map { Optional($0.anyValue.ref) }
        let count = UInt32(arguments.count)
        let call = LLVMBuildCall2(ref, function.type.ref, function.ref, &arguments, count, "")!
        Attribute.forEach(of: parameterAttributes, in: context.ref) { LLVMAddCallSiteAttribute(call, $0, $1) }

        // A call of a function that returns nothing gives no value.
        let result = AnyValue(call)
        return result.type.isVoid ? nil : result
    }

    // MARK: Memory

    /// Builds `alloca`, which gives a stack slot for a value of `type`, aligned to `alignment` bytes.
    public func allocate(_ type: some TypeHandle, alignment: Int) -> PointerValue {
        let slot = LLVMBuildAlloca(ref, type.anyType.ref, "")!
        LLVMSetAlignment(slot, UInt32(alignment))
        return PointerValue(slot)
    }

    /// Builds `load`, which gives the value of `type` that `pointer` points to, aligned to `alignment` bytes.
    public func load(_ type: some TypeHandle, from pointer: PointerValue, alignment: Int) -> AnyValue {
        let load = LLVMBuildLoad2(ref, type.anyType.ref, pointer.ref, "")!
        LLVMSetAlignment(load, UInt32(alignment))
        return AnyValue(load)
    }

    /// Builds `getelementptr`, which gives a pointer to the field at `index` of the value of `type` that `pointer`
    /// points to.
    public func fieldPointer(to index: Int, of type: StructType, at pointer: PointerValue) -> PointerValue {
        PointerValue(LLVMBuildStructGEP2(ref, type.ref, pointer.ref, UInt32(index), "")!)
    }

    /// Builds `getelementptr`, which gives a pointer to the element at `index` of the values of type `element` that
    /// lie end to end from where `pointer` points. The element must lie inside the memory that `pointer` reaches.
    public func elementPointer(
        to index: some IntegerHandle, of element: some TypeHandle, at pointer: PointerValue,
    ) -> PointerValue {
        var indices: [LLVMValueRef?] = [index.anyValue.ref]
        return PointerValue(LLVMBuildInBoundsGEP2(ref, element.anyType.ref, pointer.ref, &indices, 1, "")!)
    }

    /// Builds `store`, which stores `value` where `pointer` points, aligned to `alignment` bytes.
    public func store(_ value: some ValueHandle, to pointer: PointerValue, alignment: Int) {
        let store = LLVMBuildStore(ref, value.anyValue.ref, pointer.ref)!
        LLVMSetAlignment(store, UInt32(alignment))
    }

    /// Builds a call of `llvm.memcpy`, which copies `size` bytes from where `source` points to where `destination`
    /// points, both aligned to `alignment` bytes. The two must be the same memory or share none of it.
    public func copyMemory(to destination: PointerValue, from source: PointerValue, size: Int, alignment: Int) {
        let size = LLVMConstInt(LLVMInt64TypeInContext(context.ref), UInt64(size), 0)
        let align = UInt32(alignment)
        LLVMBuildMemCpy(ref, destination.ref, align, source.ref, align, size)
    }

    // MARK: Terminators

    /// Builds `br`, which goes on to `target`.
    public func branch(to target: BasicBlock) {
        LLVMBuildBr(ref, target.ref)
    }

    /// Builds a conditional `br`, which goes on to `then` where `condition` holds and to `otherwise` where it
    /// doesn't.
    public func branch(if condition: IntValue<I1>, then: BasicBlock, else otherwise: BasicBlock) {
        LLVMBuildCondBr(ref, condition.ref, then.ref, otherwise.ref)
    }

    /// Builds `ret`.
    public func `return`(_ value: some ValueHandle) {
        LLVMBuildRet(ref, value.anyValue.ref)
    }

    /// Builds `ret void`, which returns from a function that returns nothing.
    public func returnVoid() {
        LLVMBuildRetVoid(ref)
    }

    /// Builds `unreachable`, which ends a block that no run reaches the end of.
    public func unreachable() {
        LLVMBuildUnreachable(ref)
    }
}
