@testable import PBNCore

// On macOS, `import XCTest` transitively imports AppKit/ApplicationServices,
// which exposes a C `RGBColor` struct from the legacy QuickDraw (QD)
// framework. That makes bare `RGBColor` references in our tests ambiguous
// between `PBNCore.RGBColor` and `QD.RGBColor`. Shadow the C type at the
// test module level so existing tests can keep using the short name.
typealias RGBColor = PBNCore.RGBColor
