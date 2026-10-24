import XCTest
@testable import LGChannelSearch

private struct TestChannel: SearchableChannel, Equatable {
    let id: String
    let number: String
    let name: String
    let nameNormalized: String
    var isFavorite: Bool

    init(id: String, number: String, name: String, isFavorite: Bool = false) {
        self.id = id
        self.number = number
        self.name = name
        self.nameNormalized = ArabicNormalizer.normalize(name)
        self.isFavorite = isFavorite
    }
}

final class SearchEngineTests: XCTestCase {
    private let sampleChannels: [TestChannel] = [
        TestChannel(id: "c1", number: "1", name: "WAAR HD"),
        TestChannel(id: "c16", number: "16", name: "Al Jazeera Documentary"),
        TestChannel(id: "c162", number: "162", name: "Nat Geo Wild"),
        TestChannel(id: "c1626", number: "1626", name: "AD Nat Geo HD"),
        TestChannel(id: "c10", number: "10", name: "القاهرة الإخبارية HD"),
        TestChannel(id: "c12", number: "12", name: "الأولى المصرية"),
        TestChannel(id: "c528", number: "528", name: "Horus \u{00A0}Drama")
    ]

    func testExactChannelNumberRanksFirstAndSupportsArabicIndicDigits() {
        let resultsASCII = SearchEngine.search(sampleChannels, query: "16")
        XCTAssertEqual(resultsASCII.first?.id, "c16")

        let resultsArabicDigits = SearchEngine.search(sampleChannels, query: "١٦٢٦")
        XCTAssertEqual(resultsArabicDigits.first?.id, "c1626")
    }

    func testRankingOrderExactBeforePrefixBeforeTokenBeforeSubstring() {
        let channels = [
            TestChannel(id: "substring", number: "400", name: "Super Sportz Network"),
            TestChannel(id: "token", number: "300", name: "AD Sport HD"),
            TestChannel(id: "prefix", number: "200", name: "Sport One"),
            TestChannel(id: "exact", number: "100", name: "Sport")
        ]

        let results = SearchEngine.search(channels, query: "sport")
        XCTAssertEqual(results.map(\.id), ["exact", "prefix", "token", "substring"])
    }

    func testArabicNormalizedSearchMatchesUnvocalizedAndVariantQuery() {
        // Query uses plain 'ا' instead of 'إ' and 'ه' instead of 'ة'
        let results = SearchEngine.search(sampleChannels, query: "القاهره الاخباريه")
        XCTAssertEqual(results.map(\.id), ["c10"])

        // Query uses 'ي' instead of 'ى' and plain 'ا' instead of 'أ'
        let egyptResults = SearchEngine.search(sampleChannels, query: "الاولي المصريه")
        XCTAssertEqual(egyptResults.map(\.id), ["c12"])
    }

    func testTokenMatchingAcrossNonBreakingSpace() {
        let results = SearchEngine.search(sampleChannels, query: "horus drama")
        XCTAssertEqual(results.map(\.id), ["c528"])
    }

    func testFavoritesTieBreakWithinSameRankTier() {
        let channels = [
            TestChannel(id: "nonFav", number: "10", name: "Nile Cinema", isFavorite: false),
            TestChannel(id: "fav", number: "50", name: "Nile Drama", isFavorite: true)
        ]

        let results = SearchEngine.search(channels, query: "nile")
        XCTAssertEqual(results.map(\.id), ["fav", "nonFav"])
    }
}
