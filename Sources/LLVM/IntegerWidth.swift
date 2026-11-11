/// The width of an integer type, which types its values so that an operation takes two integers of one width.
public protocol IntegerWidth {
    static var bitWidth: UInt32 { get }
}

/// One bit: a Bool, and the result of a comparison.
public enum I1: IntegerWidth {
    public static var bitWidth: UInt32 { 1 }
}

/// Eight bits: a byte.
public enum I8: IntegerWidth {
    public static var bitWidth: UInt32 { 8 }
}

public enum I32: IntegerWidth {
    public static var bitWidth: UInt32 { 32 }
}

public enum I64: IntegerWidth {
    public static var bitWidth: UInt32 { 64 }
}
