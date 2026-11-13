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
    public func add<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildAdd(ref, left.ref, right.ref, ""))
    }

    /// Builds `sub`, which wraps on overflow.
    public func subtract<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildSub(ref, left.ref, right.ref, ""))
    }

    /// Builds `mul`, which wraps on overflow.
    public func multiply<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildMul(ref, left.ref, right.ref, ""))
    }

    /// Builds `sdiv`, which LLVM leaves undefined for a zero divisor and for the one quotient that overflows.
    public func signedDivide<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildSDiv(ref, left.ref, right.ref, ""))
    }

    /// Builds `srem`, whose result takes the dividend's sign, and which LLVM leaves undefined where `sdiv` is.
    public func signedRemainder<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildSRem(ref, left.ref, right.ref, ""))
    }

    /// Builds `and`.
    public func and<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildAnd(ref, left.ref, right.ref, ""))
    }

    /// Builds `xor`.
    public func xor<Width>(_ left: IntValue<Width>, _ right: IntValue<Width>) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildXor(ref, left.ref, right.ref, ""))
    }

    /// Builds `icmp`, which gives whether `predicate` holds of `left` and `right`.
    public func compare<Width>(
        _ predicate: IntegerPredicate, _ left: IntValue<Width>, _ right: IntValue<Width>,
    ) -> IntValue<I1> {
        IntValue(unchecked: LLVMBuildICmp(ref, predicate.llvmPredicate, left.ref, right.ref, ""))
    }

    /// Builds `select`, which gives `then` where `condition` holds and `otherwise` where it doesn't.
    public func select<Width>(
        _ condition: IntValue<I1>, _ then: IntValue<Width>, _ otherwise: IntValue<Width>,
    ) -> IntValue<Width> {
        IntValue(unchecked: LLVMBuildSelect(ref, condition.ref, then.ref, otherwise.ref, ""))
    }

    // MARK: Integer conversions

    /// Builds `trunc`, which keeps the low bits of `value` that `type` holds. `type` must be narrower than `value`.
    public func truncate<From, To>(_ value: IntValue<From>, to type: IntegerType<To>) -> IntValue<To> {
        precondition(To.bitWidth < From.bitWidth, "LLVM truncates an integer only to a narrower one")
        return IntValue(unchecked: LLVMBuildTrunc(ref, value.ref, type.ref, ""))
    }

    /// Builds `zext`, which pads `value` with zero bits to the width of `type`. `type` must be wider than `value`.
    public func zeroExtend<From, To>(_ value: IntValue<From>, to type: IntegerType<To>) -> IntValue<To> {
        precondition(To.bitWidth > From.bitWidth, "LLVM zero-extends an integer only to a wider one")
        return IntValue(unchecked: LLVMBuildZExt(ref, value.ref, type.ref, ""))
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
        parameterAttributes.forEachAttribute(in: context.ref) { LLVMAddCallSiteAttribute(call, $0, $1) }

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
