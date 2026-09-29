import Foundation
import Testing
@testable import whispermac

func localizedStrings(for identifier: String) throws -> [String: String] {
    let path = try #require(
        Bundle.module.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: identifier
        )
    )
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(propertyList as? [String: String])
}
