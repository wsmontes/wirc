import XCTest
@testable import Wirc

final class FeedParserTests: XCTestCase {

    func testParseRSSFeed() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Article One</title>
              <link>https://example.com/1</link>
              <description>First article</description>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """
        let data = Data(xml.utf8)
        let result = try FeedParser.parse(data: data, sourceURL: "https://example.com/feed.xml")
        XCTAssertEqual(result.title, "Test Feed")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "Article One")
        XCTAssertEqual(result.items[0].link, "https://example.com/1")
    }

    func testParseAtomFeed() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry>
            <title>Entry One</title>
            <link href="https://example.com/1" rel="alternate"/>
            <summary>Summary text</summary>
            <published>2024-01-01T12:00:00Z</published>
          </entry>
        </feed>
        """
        let data = Data(xml.utf8)
        let result = try FeedParser.parse(data: data, sourceURL: "https://example.com/atom.xml")
        XCTAssertEqual(result.title, "Atom Feed")
        XCTAssertEqual(result.items.count, 1)
    }

    func testItemWithoutTitleFallsBackToDescription() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><item>
          <link>https://example.com/1</link>
          <description>Description only item</description>
        </item></channel></rss>
        """
        let data = Data(xml.utf8)
        let result = try FeedParser.parse(data: data, sourceURL: "https://example.com")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "Description only item")
    }

    func testRelativeURLResolved() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Test</title>
            <link href="/blog/post" rel="alternate"/>
          </entry>
        </feed>
        """
        let data = Data(xml.utf8)
        let result = try FeedParser.parse(data: data, sourceURL: "https://example.com/atom.xml")
        XCTAssertEqual(result.items[0].link, "https://example.com/blog/post")
    }
}
