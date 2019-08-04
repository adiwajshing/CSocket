import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ConnectingTests.allTests),
        testCase(ReadingTests.allTests)
    ]
}
#endif
