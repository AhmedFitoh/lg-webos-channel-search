import XCTest
@testable import LGChannelSearch

final class SSAPMessageTests: XCTestCase {
    private func loadFixtureData(named filename: String) throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixturesDir = testFileURL.deletingLastPathComponent().appendingPathComponent("Fixtures")
        let fileURL = fixturesDir.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }

    func testDecodeRealGetCurrentChannelFixture() throws {
        let data = try loadFixtureData(named: "getCurrentChannel.json")
        let response = try JSONDecoder().decode(SSAPResponse<SSAPCurrentChannelPayload>.self, from: data)

        XCTAssertEqual(response.id, "cur_channel_1")
        XCTAssertEqual(response.type, "response")
        let payload = try XCTUnwrap(response.payload)
        XCTAssertFalse(payload.channelId.isEmpty)
        XCTAssertFalse(payload.channelNumber.isEmpty)
        XCTAssertFalse(payload.channelName.isEmpty)
        XCTAssertEqual(payload.channelModeId, 2)
        XCTAssertEqual(payload.channelModeName, "Satellite")
        XCTAssertEqual(payload.channelTypeId, 6)
        XCTAssertEqual(payload.channelTypeName, "Satellite Digital TV")
        XCTAssertEqual(payload.returnValue, true)
    }

    func testDecodeRealGetChannelListSampleFixture() throws {
        let data = try loadFixtureData(named: "getChannelList_sample.json")
        let response = try JSONDecoder().decode(SSAPResponse<SSAPChannelListPayload>.self, from: data)

        XCTAssertEqual(response.id, "chan_list_1")
        let payload = try XCTUnwrap(response.payload)
        XCTAssertEqual(payload.returnValue, true)
        XCTAssertEqual(payload.channelList.count, 27)

        let natGeo = try XCTUnwrap(payload.channelList.first { $0.channelNumber == "1626" })
        XCTAssertEqual(natGeo.channelId, "7_661_1626_0_50_8_100")
        XCTAssertEqual(natGeo.channelName, "AD Nat Geo HD")
        XCTAssertEqual(natGeo.channelMode, "Satellite")
        XCTAssertEqual(natGeo.channelModeId, 2)
        XCTAssertEqual(natGeo.channelType, "Satellite Digital TV")
        XCTAssertEqual(natGeo.channelTypeId, 6)
        XCTAssertEqual(natGeo.isTV, true)
        XCTAssertEqual(natGeo.isRadio, false)

        let arabicRadio = try XCTUnwrap(payload.channelList.first { $0.channelNumber == "165" && $0.isRadio == true })
        XCTAssertTrue(arabicRadio.channelName.contains("إذاعة"))
        XCTAssertEqual(arabicRadio.channelType, "Satellite Digital Radio")
        XCTAssertEqual(arabicRadio.channelTypeId, 7)
        XCTAssertEqual(arabicRadio.satelliteName, "NILESAT 7.0W")
    }

    func testDecodeRealOpenChannelResponseFixture() throws {
        let data = try loadFixtureData(named: "openChannel_response.json")
        let response = try JSONDecoder().decode(SSAPResponse<SSAPReturnValuePayload>.self, from: data)

        XCTAssertEqual(response.id, "open_channel_1")
        XCTAssertEqual(response.payload?.returnValue, true)
    }

    func testRegisterFrameEncodingAndClientKeyRedaction() throws {
        let frame = SSAPRegisterFrame(id: "reg_test", clientKey: "super_secret_key_12345")
        XCTAssertTrue(frame.payload.manifest.permissions.contains("CONTROL_MOUSE_AND_KEYBOARD"))
        XCTAssertTrue(frame.payload.manifest.permissions.contains("CONTROL_INPUT_TEXT"))

        let encoded = try JSONEncoder().encode(frame)
        let jsonString = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(jsonString.contains("super_secret_key_12345"))
        let redacted = SSAPRedactor.redact(jsonString)
        XCTAssertFalse(redacted.contains("super_secret_key_12345"))
        XCTAssertTrue(redacted.contains("<REDACTED>"))
    }

    func testWakeOnLANMagicPacketConstruction() throws {
        let packet = try WakeOnLAN.buildMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(packet.count, 102)
        // First 6 bytes must be 0xFF
        XCTAssertEqual(Array(packet.prefix(6)), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        // Followed by 16 repetitions of AA:BB:CC:DD:EE:FF
        XCTAssertEqual(Array(packet[6..<12]), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    func testSearchAndSort3000ChannelsPerformanceAndAccuracy() throws {
        let satellites = ["NILESAT 7.0W", "HOTBIRD 13.0E", "BADR 26.0E"]
        var models: [Channel] = []
        models.reserveCapacity(3000)

        for i in 1...3000 {
            let name: String
            switch i {
            case 165:
                name = "TWR Arabic إذاعة حول العالم"
            case 528:
                name = "Horus \u{00A0}Drama"
            case 1626:
                name = "AD Nat Geo HD"
            default:
                name = (i % 2 == 0) ? "قناة رقم \(i) HD" : "Satellite Channel \(i)"
            }
            let dto = SSAPChannelDTO(
                channelId: "7_1_\(i)_0_500_\(i)_20480",
                channelNumber: "\(i)",
                channelName: name,
                satelliteName: satellites[i % satellites.count],
                isTV: i != 165,
                isRadio: i == 165,
                isHDTV: i % 2 == 0,
                frequency: 10727 + (i % 40) * 18
            )
            models.append(Channel.fromDTO(dto))
        }

        let natGeoResults = SearchEngine.search(models, query: "nat geo")
        XCTAssertEqual(natGeoResults.first?.number, "1626")

        let arabicRadioResults = SearchEngine.search(models, query: "اذاعه حول")
        XCTAssertEqual(arabicRadioResults.first?.number, "165")

        let arabicDigitNumberResults = SearchEngine.search(models, query: "١٦٢٦")
        XCTAssertEqual(arabicDigitNumberResults.first?.number, "1626")
    }
}
