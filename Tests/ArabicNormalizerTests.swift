import XCTest
@testable import LGChannelSearch

final class ArabicNormalizerTests: XCTestCase {
    func testStripsTashkeelAndTatweel() {
        let input = "الـقَـاهِـرَةُ الإِخْـبَـارِيَّـةُ"
        let normalized = ArabicNormalizer.normalize(input)
        XCTAssertEqual(normalized, "القاهره الاخباريه")
    }

    func testUnifiesAlefForms() {
        let input = "أحمد إبراهيم آفاق ٱلأولى"
        let normalized = ArabicNormalizer.normalize(input)
        XCTAssertEqual(normalized, "احمد ابراهيم افاق الاولي")
    }

    func testUnifiesYaAndAlefMaqsuraAndTaMarbuta() {
        let input = "موسيقى القناة المصرية الأولى"
        let normalized = ArabicNormalizer.normalize(input)
        XCTAssertEqual(normalized, "موسيقي القناه المصريه الاولي")
    }

    func testNormalizesArabicIndicAndEasternArabicDigits() {
        let arabicIndic = "١٦٢٦"
        let easternIndic = "۱۶۲۶"
        XCTAssertEqual(ArabicNormalizer.normalize(arabicIndic), "1626")
        XCTAssertEqual(ArabicNormalizer.normalize(easternIndic), "1626")
        XCTAssertEqual(ArabicNormalizer.normalizeChannelNumber(" ١٦٢٥ "), "1625")
    }

    func testCollapsesNonBreakingSpaceAndMultipleSpaces() {
        // Real channel 528 on LG 55UP7760PVB has U+00A0 non-breaking space: "Horus \u{00A0}Drama"
        let input = "  Horus \u{00A0}  Drama  "
        XCTAssertEqual(ArabicNormalizer.normalize(input), "horus drama")
    }

    func testFoldsLatinDiacriticsAndCaseWithoutBreakingArabic() {
        let input = "France 24 (Édition العربية)"
        XCTAssertEqual(ArabicNormalizer.normalize(input), "france 24 (edition العربيه)")
    }
}
