/**
 * Sample Cangjie package for package-to-cli testing.
 * Contains Student class (name, id with get/set) and Lesson class
 * (collection of students with add, remove by reference, print).
 */
package lesson_demo

// Pull in nested subpackage so cjpm links multi-level lib (like deepnames: demo_sub/nested).
import lesson_demo.demo_sub.nested.demo as _nestedDemoRef
import std.fs.*
func _linkNested(): Unit { _nestedDemoRef() }

func _reportSubstring(s: String, start: Int64, end: Int64): String {
    let sb: StringBuilder = StringBuilder()
    var i: Int64 = start
    while (i < end && i < s.size) {
        sb.append(Rune(UInt32(s.get(i).getOrThrow())))
        i++
    }
    sb.toString()
}

func _basename(path: String): String {
    var lastSlash: Int64 = -1
    var i: Int64 = 0
    while (i < path.size) {
        if (Int64(path.get(i).getOrThrow()) == 47) {
            lastSlash = i
        }
        i++
    }
    _reportSubstring(path, lastSlash + 1, path.size)
}

func _countLines(s: String): Int64 {
    if (s.size == 0) { return 0 }
    var count: Int64 = 0
    var i: Int64 = 0
    while (i < s.size) {
        if (Int64(s.get(i).getOrThrow()) == 10) {
            count++
        }
        i++
    }
    if (Int64(s.get(s.size - 1).getOrThrow()) != 10) {
        count++
    }
    count
}

func _firstLine(s: String): String {
    var i: Int64 = 0
    while (i < s.size) {
        let c: Int64 = Int64(s.get(i).getOrThrow())
        if (c == 10 || c == 13) {
            return _reportSubstring(s, 0, i)
        }
        i++
    }
    s
}

func _asciiUppercase(s: String): String {
    let sb: StringBuilder = StringBuilder()
    var i: Int64 = 0
    while (i < s.size) {
        let c: Int64 = Int64(s.get(i).getOrThrow())
        if (c >= 97 && c <= 122) {
            sb.append(Rune(UInt32(c - 32)))
        } else {
            sb.append(Rune(UInt32(c)))
        }
        i++
    }
    sb.toString()
}

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

    public func printStudentNames(): Unit {
        var i: Int64 = 0
        while (i < count) {
            let s = students[i]
            println(s.getName())
            i++
        }
    }

    public func getStudentCount(): Int64 {
        count
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

// ---------------------------------------------------------------------------
// Public functions for CLI: add student to lesson, print lesson student names
// ---------------------------------------------------------------------------
public func addStudentToLesson(student: Student, lesson: Lesson): Unit {
    lesson.add(student)
}

public func printLessonStudentNames(lesson: Lesson): Unit {
    println("=== Lesson student names ===")
    lesson.printStudentNames()
    println("=== End of lesson student names ===")
}

public func lessonStudentCount(lesson: Lesson): Int64 {
    lesson.getStudentCount()
}

public func buildUploadReport(inputPath: String): String {
    let inputBytes: Array<Byte> = File.readFrom(Path(inputPath))
    let inputText: String = String.fromUtf8(inputBytes)
    let outputDir: String = "/tmp/cliver/outputs"
    try { Directory.create(outputDir, recursive: true) } catch (_) { }

    let outputPath: String = outputDir + "/" + _basename(inputPath) + ".report.txt"
    let report: String =
        "INPUT_PATH=" + inputPath + "\n" +
        "BYTE_COUNT=" + inputBytes.size.toString() + "\n" +
        "CHAR_COUNT=" + inputText.size.toString() + "\n" +
        "LINE_COUNT=" + _countLines(inputText).toString() + "\n" +
        "UPPERCASE_PREVIEW=" + _asciiUppercase(_firstLine(inputText)) + "\n"

    var outputFile: File = File(Path(outputPath), Write)
    outputFile.write(report.toArray())
    outputFile.close()
    outputPath
}
