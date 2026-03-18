package minimal_pkg

public func hello(name: String): String {
    "Hello, " + name
}

public class Box {
    var value: String
    public init(value: String) {
        this.value = value
    }
}
