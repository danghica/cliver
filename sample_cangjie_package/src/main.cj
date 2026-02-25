/**
 * Sample Cangjie package for package-to-cli testing.
 * Contains Student class (name, id with get/set) and Lesson class
 * (collection of students with add, remove by reference, print).
 */
package lesson_demo

// ---------------------------------------------------------------------------
// Student: name (String), id (Int64); getters and setters
// ---------------------------------------------------------------------------
public class Student {
    private var studentName: String
    private var studentId: Int64
    private let identityId: Int64
    static var nextIdentityId: Int64 = 0

    public init(name: String, id: Int64) {
        this.studentName = name
        this.studentId = id
        this.identityId = Student.nextIdentityId
        Student.nextIdentityId++
    }

    public func getName(): String {
        studentName
    }

    public func setName(name: String): Unit {
        this.studentName = name
    }

    public func getId(): Int64 {
        studentId
    }

    public func setId(id: Int64): Unit {
        this.studentId = id
    }

    public operator func ==(other: Student): Bool {
        this.identityId == other.identityId
    }
}

// ---------------------------------------------------------------------------
// Lesson: collection of Student; add, remove by reference, print list
// Uses fixed-capacity Array because ArrayList.add is not available for class types in this SDK.
// ---------------------------------------------------------------------------
public class Lesson {
    private var students: Array<Student> = Array<Student>(64, { _ => Student("", 0) })
    private var count: Int64 = 0

    public init() {}

    public func add(student: Student): Unit {
        if (count < students.size) {
            students[count] = student
            count++
        }
    }

    public func remove(student: Student): Bool {
        var i: Int64 = 0
        while (i < count) {
            if (students[i] == student) {
                var j = i
                while (j + 1 < count) {
                    students[j] = students[j + 1]
                    j++
                }
                count--
                return true
            }
            i++
        }
        return false
    }

    public func printStudents(): Unit {
        var i: Int64 = 0
        while (i < count) {
            let s = students[i]
            println("${s.getName()}, ${s.getId()}")
            i++
        }
    }
}

// ---------------------------------------------------------------------------
// Demo: add, print, remove by reference (call demo() to run; CLI uses generated main)
// ---------------------------------------------------------------------------
public func demo(): Unit {
    let lesson = Lesson()
    let alice = Student("Alice", 1001)
    let bob = Student("Bob", 1002)
    let carol = Student("Carol", 1003)

    lesson.add(alice)
    lesson.add(bob)
    lesson.add(carol)

    println("=== After adding three students ===")
    lesson.printStudents()

    lesson.remove(bob)

    println("=== After removing Bob (by reference) ===")
    lesson.printStudents()
}
