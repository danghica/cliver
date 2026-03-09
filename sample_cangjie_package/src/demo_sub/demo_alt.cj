/**
 * Sub-package demo for testing nested layout.
 * Same signature as root demo() but uses students David, Eugen, Flora.
 */
package lesson_demo

// Demo with same signature as main demo ((): Unit) but different student names
public func demoAlt(): Unit {
    let lesson = Lesson()
    let david = Student("David", 2001)
    let eugen = Student("Eugen", 2002)
    let flora = Student("Flora", 2003)

    lesson.add(david)
    lesson.add(eugen)
    lesson.add(flora)

    println("=== After adding three students (David, Eugen, Flora) ===")
    lesson.printStudents()

    lesson.remove(eugen)

    println("=== After removing Eugen (by reference) ===")
    lesson.printStudents()
}
