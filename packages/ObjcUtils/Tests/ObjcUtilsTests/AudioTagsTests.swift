import AVFoundation
import Foundation
import ObjcUtils
import XCTest

private final class MetadataAsset: AVURLAsset {
    private let metadataFormats: [AVMetadataFormat]
    private let metadataItems: [AVMetadataFormat: [AVMetadataItem]]

    init(_ formats: [(AVMetadataFormat, [AVMetadataItem])]) {
        self.metadataFormats = formats.map { $0.0 }
        self.metadataItems = Dictionary(uniqueKeysWithValues: formats)
        super.init(url: URL(fileURLWithPath: "/audio-tags-fixture.m4a"), options: nil)
    }

    override var availableMetadataFormats: [AVMetadataFormat] {
        return metadataFormats
    }

    override func metadata(forFormat format: AVMetadataFormat) -> [AVMetadataItem] {
        return metadataItems[format] ?? []
    }
}

final class AudioTagsTests: XCTestCase {
    private func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private func tags(_ items: [AVMetadataItem]) -> [String: String] {
        return audioTags(MetadataAsset([(.iTunesMetadata, items)]))
    }

    private func fixture(_ name: String) throws -> AVURLAsset {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "m4a", subdirectory: "Fixtures"))
        return AVURLAsset(url: url)
    }

    func testM4AArtistWithoutAlbumArtist() throws {
        let asset = try fixture("artist-only")
        let identifiers = asset.metadata(forFormat: .iTunesMetadata).compactMap { $0.identifier }
        XCTAssertTrue(identifiers.contains(.iTunesMetadataArtist))
        XCTAssertFalse(identifiers.contains(.iTunesMetadataAlbumArtist))
        XCTAssertEqual(audioTags(asset), ["performer": "Test Artist", "title": "Metadata Test"])
    }

    func testM4AArtistWithAlbumArtist() throws {
        let asset = try fixture("artist-and-album-artist")
        let identifiers = asset.metadata(forFormat: .iTunesMetadata).compactMap { $0.identifier }
        XCTAssertTrue(identifiers.contains(.iTunesMetadataArtist))
        XCTAssertTrue(identifiers.contains(.iTunesMetadataAlbumArtist))
        XCTAssertEqual(audioTags(asset), ["performer": "Test Artist", "title": "Metadata Test"])
    }

    func testITunesTrackArtistAndTitle() {
        XCTAssertEqual(tags([
            item(.iTunesMetadataArtist, "Track Artist"),
            item(.iTunesMetadataSongName, "Track Title")
        ]), ["performer": "Track Artist", "title": "Track Title"])
    }

    func testTrackArtistWinsRegardlessOfFallbackOrder() {
        let artist = item(.iTunesMetadataArtist, "Track Artist")
        let albumArtist = item(.iTunesMetadataAlbumArtist, "Album Artist")
        let composer = item(.iTunesMetadataComposer, "Composer")
        let permutations = [
            [artist, albumArtist, composer],
            [artist, composer, albumArtist],
            [albumArtist, artist, composer],
            [albumArtist, composer, artist],
            [composer, artist, albumArtist],
            [composer, albumArtist, artist]
        ]
        for items in permutations {
            XCTAssertEqual(tags(items)["performer"], "Track Artist")
        }
    }

    func testAlbumArtistFallbackRemainsAvailable() {
        XCTAssertEqual(tags([
            item(.iTunesMetadataAlbumArtist, "Album Artist"),
            item(.iTunesMetadataSongName, "Track Title")
        ]), ["performer": "Album Artist", "title": "Track Title"])
    }

    func testComposerFallbackRemainsAvailable() {
        XCTAssertEqual(tags([
            item(.iTunesMetadataComposer, "Composer"),
            item(.iTunesMetadataSongName, "Track Title")
        ]), ["performer": "Composer", "title": "Track Title"])
    }

    func testEmptyTrackArtistDoesNotEraseFallback() {
        for items in [
            [item(.iTunesMetadataAlbumArtist, "Album Artist"), item(.iTunesMetadataArtist, "")],
            [item(.iTunesMetadataArtist, ""), item(.iTunesMetadataAlbumArtist, "Album Artist")]
        ] {
            XCTAssertEqual(tags(items)["performer"], "Album Artist")
        }
    }

    func testFallbackInEarlierFormatDoesNotHideTrackArtist() {
        let asset = MetadataAsset([
            (.iTunesMetadata, [item(.iTunesMetadataAlbumArtist, "Album Artist"), item(.iTunesMetadataSongName, "Track Title")]),
            (.quickTimeUserData, [item(.quickTimeUserDataArtist, "Track Artist")])
        ])
        XCTAssertEqual(audioTags(asset), ["performer": "Track Artist", "title": "Track Title"])
    }

    func testQuickTimeArtistAndTrackName() {
        let asset = MetadataAsset([
            (.quickTimeUserData, [item(.quickTimeUserDataArtist, "Movie Artist"), item(.quickTimeUserDataTrackName, "Movie Track")])
        ])
        XCTAssertEqual(audioTags(asset), ["performer": "Movie Artist", "title": "Movie Track"])
    }

    func testID3LeadPerformerAndTitleRemainSupported() {
        let asset = MetadataAsset([
            (.id3Metadata, [item(.id3MetadataLeadPerformer, "MP3 Artist"), item(.id3MetadataTitleDescription, "MP3 Title")])
        ])
        XCTAssertEqual(audioTags(asset), ["performer": "MP3 Artist", "title": "MP3 Title"])
    }

    func testCommonArtistAndTitleRemainSupported() {
        XCTAssertEqual(tags([
            item(.commonIdentifierArtist, "Common Artist"),
            item(.commonIdentifierTitle, "Common Title")
        ]), ["performer": "Common Artist", "title": "Common Title"])
    }

    func testMissingTagsReturnEmptyStrings() {
        XCTAssertEqual(tags([]), ["performer": "", "title": ""])
    }

    func testTitleOnlyDoesNotInventPerformer() {
        XCTAssertEqual(tags([item(.iTunesMetadataSongName, "Track Title")]), ["performer": "", "title": "Track Title"])
    }

    func testUnrelatedMetadataIsIgnored() {
        XCTAssertEqual(tags([
            item(.iTunesMetadataAlbum, "Album"),
            item(.commonIdentifierDescription, "Description")
        ]), ["performer": "", "title": ""])
    }
}
