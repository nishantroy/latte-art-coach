import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import LatteCore

@Suite struct BeanLabelTests {
  static var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }
  static func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d))! }
  static let today = day(2026, 11, 6)

  static func parse(_ lines: [String]) -> BeanLabel {
    BeanLabelParser.parse(lines.map { LabelLine($0) }, today: today, calendar: utc)
  }

  @Test func readsAWashedEthiopian() {
    let label = Self.parse([
      "ONYX COFFEE LAB", "Ethiopia Guji Hambela", "Washed · Heirloom", "1,900 - 2,200 MASL",
      "Jasmine, Peach & Black Tea", "Roasted on 2026-10-28", "12 oz / 340 g",
    ])
    #expect(label.origin == "Ethiopia")
    #expect(label.process == "Washed")
    #expect(label.variety == "Heirloom")
    #expect(label.altitude == "1,900–2,200 m")
    #expect(label.roastDate == Self.day(2026, 10, 28))
    #expect(label.tastingNotes == ["jasmine", "peach", "black tea"])
    #expect(label.roastLevel == .light && label.roastLevelIsGuess)
  }

  @Test func readsAChocolateyBrazilWithAPrintedRoast() {
    let label = Self.parse([
      "Brazil Cerrado Mineiro", "Natural | Yellow Bourbon", "Notes: milk chocolate, hazelnut, brown sugar",
      "Medium Roast", "Roast date", "Oct 30, 2026",
    ])
    #expect(label.origin == "Brazil")
    #expect(label.process == "Natural")
    #expect(label.variety == "Yellow Bourbon")
    #expect(label.roastDate == Self.day(2026, 10, 30))
    #expect(label.tastingNotes == ["milk chocolate", "hazelnut", "brown sugar"])
    #expect(label.roastLevel == .medium && !label.roastLevelIsGuess, "printed roast wins over the guess")
  }

  @Test func guessesDarkFromHeavyNotes() {
    let label = Self.parse(["Sumatra Wet Hulled", "Dark chocolate · molasses · cedar", "Roasted 11/02/2026"])
    #expect(label.process == "Wet-hulled")
    #expect(label.roastDate == Self.day(2026, 11, 2))
    #expect(label.roastLevel == .dark && label.roastLevelIsGuess)
  }

  @Test func ignoresBestByAndFutureDates() {
    let label = Self.parse(["Colombia Huila", "Honey process", "Best by 2027-05-01", "Caramel, red apple"])
    #expect(label.roastDate == nil, "a best-by date months ahead isn't a roast date")
    #expect(label.process == "Honey")
    #expect(!label.tastingNotes.contains("honey"))
  }

  @Test func leavesUnknownsEmpty() {
    let label = Self.parse(["House Blend", "Freshly roasted"])
    #expect(label.origin == nil && label.process == nil && label.roastDate == nil && label.roastLevel == nil)
    #expect(label.tastingNotes.isEmpty)
  }

  /// Text recognition's lines from a Huckleberry Roasters bag: the name is
  /// split over two lines with a "Trade" badge between them, and a sentence
  /// below mentions the blend again.
  @Test func readsANameAndRoasterPrintedPlainly() {
    // Heights and left edges as read at the app's 2400 px.
    let lines = [
      ("A BAG OF TASTY COFFEE", 0.022, 0.33), ("FROM YOUR FRIENDS AT", 0.018, 0.33),
      ("HUCKLEBERRY ROASTERS", 0.017, 0.32), ("DENVER, COLORADO", 0.021, 0.33), ("Civitas", 0.016, 0.33),
      ("Trade", 0.012, 0.51), ("Blend", 0.015, 0.33), ("dark sugars • chocolate • toffee", 0.013, 0.33),
      ("Our Civitas blend is meant for the fan", 0.013, 0.33), ("roasting team, we hope you enjoy our", 0.016, 0.33),
      ("ROAST/BLEND DATE", 0.014, 0.35), ("10/30/26", 0.006, 0.35),
    ].map { LabelLine($0.0, height: $0.1, left: $0.2) }
    let label = BeanLabelParser.parse(lines, today: Self.today, calendar: Self.utc)
    #expect(label.name == "Civitas Blend", "not the badge: \(label.name ?? "-")")
    #expect(label.roaster == "Huckleberry Roasters")
    #expect(label.roastDate == Self.day(2026, 10, 30))
    #expect(label.tastingNotes == ["dark sugars", "chocolate", "toffee"])
  }

  /// The same label as text recognition can also split it: the roaster over
  /// two lines with a stray letter from the big brand mark, and the date
  /// heading broken off its "ROAST/".
  @Test func readsTheSameLabelSplitDifferently() {
    let label = Self.parse(["HUCKLEBERRY", "ROASTERS U", "Civitas", "Blend", "dark sugars • chocolate • toffee",
                            "ROAST/", "BLEND DATE", "DATE", "10/30/26"])
    #expect(label.roaster == "Huckleberry Roasters")
    #expect(label.name == "Civitas Blend")
    #expect(label.tastingNotes == ["dark sugars", "chocolate", "toffee"], "a date heading isn't a note")
  }

  @Test func keepsDatesAsAFlavor() {
    #expect(Self.parse(["Notes: fig, date, cocoa"]).tastingNotes == ["fig", "date", "cocoa"])
  }

  @Test func leavesNameAndRoasterToTheModelWhenUnclear() {
    let label = Self.parse(["ONYX", "Ethiopia Guji Hambela", "Roasted on 2026-10-28", "Freshly roasted by our roasting team"])
    #expect(label.name == nil && label.roaster == nil)
  }

  /// The bag photo itself: the roast date is printed far smaller than the
  /// rest of the label.
  @Test func readsTheSmallRoastDateOffABagPhoto() async throws {
    let url = try #require(Bundle.module.url(forResource: "huckleberry-civitas", withExtension: "jpg", subdirectory: "Fixtures/labels"))
    let lines = try await LabelReader.read(imageData: Data(contentsOf: url))
    let label = BeanLabelParser.parse(lines, today: Self.today, calendar: Self.utc)
    #expect(label.roastDate == Self.day(2026, 10, 30), "\(lines.map(\.text))")
    #expect(label.name == "Civitas Blend")
    #expect(label.roaster == "Huckleberry Roasters")
  }

  /// End to end with Apple's text recognition: draws a label, reads it back.
  @Test func readsARenderedLabel() async throws {
    let image = try #require(Self.render([
      ("SEY COFFEE", 54), ("Kenya Nyeri Gatomboya", 40), ("Washed  ·  SL28, SL34", 30),
      ("Blackcurrant, grapefruit, hibiscus", 30), ("Roasted on 2026-10-25", 30),
    ]))
    let lines = try await LabelReader.read(image)
    print("OCR:", lines.map(\.text))
    let label = BeanLabelParser.parse(lines, today: Self.today, calendar: Self.utc)
    #expect(label.origin == "Kenya")
    #expect(label.process == "Washed")
    #expect(label.variety?.contains("SL28") == true)
    #expect(label.roastDate == Self.day(2026, 10, 25))
    #expect(label.tastingNotes.contains("grapefruit") && label.tastingNotes.contains("hibiscus"))
    #expect(label.roastLevel == .light)
    // Text height is a weak hint (descenders make lowercase lines taller), so
    // only check the headline is one of the two big lines; the language
    // model decides name vs roaster.
    #expect(["SEY COFFEE", "Kenya Nyeri Gatomboya"].contains(label.headline ?? ""))
  }

  /// Black text on a cream card, one line per entry, at the given point size.
  static func render(_ lines: [(String, CGFloat)]) -> CGImage? {
    let width = 1400, height = 120 + lines.count * 90
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var y = CGFloat(height - 90)
    for (text, size) in lines {
      let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
      let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
      ])
      let line = CTLineCreateWithAttributedString(attributed)
      ctx.textPosition = CGPoint(x: 60, y: y)
      CTLineDraw(line, ctx)
      y -= 90
    }
    return ctx.makeImage()
  }
}
