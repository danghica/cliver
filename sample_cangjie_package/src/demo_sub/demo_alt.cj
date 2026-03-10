/**
 * Sub-package demo for testing nested layout.
 * Same signature as root demo() ((): Unit) but uses different student names.
 * Does not import root package so the project can stay output-type = "executable".
 */
package lesson_demo.demo_sub

// Demo with same signature as main demo ((): Unit) but different student names (David, Eugen, Flora).
public func demo(): Unit {
    println("=== demo_sub/demoAlt: David, Eugen, Flora ===")
    println("Students: David (2001), Eugen (2002), Flora (2003)")
}
