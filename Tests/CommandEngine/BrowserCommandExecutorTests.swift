import XCTest
@testable import DailyOps

@MainActor
final class BrowserCommandExecutorTests: XCTestCase {
    // MARK: - URL Normalization Tests

    func testNormalizesFullyQualifiedHTTPSURL() {
        let url = URLNormalizer.normalize("https://github.com/torvalds/linux")
        XCTAssertEqual(url?.absoluteString, "https://github.com/torvalds/linux")
    }

    func testNormalizesFullyQualifiedHTTPURL() {
        let url = URLNormalizer.normalize("http://example.com")
        XCTAssertEqual(url?.absoluteString, "http://example.com")
    }

    func testNormalizesBareDomainIntoHTTPS() {
        let url = URLNormalizer.normalize("github.com")
        XCTAssertEqual(url?.absoluteString, "https://github.com")
    }

    func testNormalizesWWWPrefixedDomain() {
        let url = URLNormalizer.normalize("www.example.org")
        XCTAssertEqual(url?.absoluteString, "https://www.example.org")
    }

    func testNormalizesKnownWebsiteShortcuts() {
        XCTAssertEqual(URLNormalizer.normalize("youtube")?.absoluteString, "https://www.youtube.com")
        XCTAssertEqual(URLNormalizer.normalize("google")?.absoluteString, "https://www.google.com")
        XCTAssertEqual(URLNormalizer.normalize("github")?.absoluteString, "https://github.com")
        XCTAssertEqual(URLNormalizer.normalize("reddit")?.absoluteString, "https://www.reddit.com")
        XCTAssertEqual(URLNormalizer.normalize("wikipedia")?.absoluteString, "https://www.wikipedia.org")
    }

    func testRejectsUnsafeSchemes() {
        XCTAssertNil(URLNormalizer.normalize("javascript:alert('pwn')"))
        XCTAssertNil(URLNormalizer.normalize("file:///System/Library"))
        XCTAssertNil(URLNormalizer.normalize("data:text/html,<h1>hi</h1>"))
        XCTAssertNil(URLNormalizer.normalize("apple-theme://something"))
    }

    func testRejectsMalformedAndArbitraryStrings() {
        XCTAssertNil(URLNormalizer.normalize(""))
        XCTAssertNil(URLNormalizer.normalize("   "))
        XCTAssertNil(URLNormalizer.normalize("not a website at all"))
        XCTAssertNil(URLNormalizer.normalize("open the door"))
    }

    // MARK: - Search URL Builder Tests

    func testConstructsGoogleSearchURLWithPercentEncoding() {
        let request = SearchRequest(query: "machine learning & ai", provider: .google)
        let url = WebSearchBuilder.searchURL(for: request)
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("https://www.google.com/search?q=") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("machine%20learning") ?? false)
    }

    func testConstructsYouTubeSearchURLWithPercentEncoding() {
        let request = SearchRequest(query: "worship songs 2026", provider: .youtube)
        let url = WebSearchBuilder.searchURL(for: request)
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("https://www.youtube.com/results?search_query=") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("worship%20songs") ?? false)
    }

    func testSearchURLPreservesReservedCharactersAndPunctuation() {
        let testQueries = [
            "C++",
            "Tom & Jerry",
            "A=B",
            "#Swift",
            "Swift + macOS"
        ]

        for query in testQueries {
            // Google
            let googleReq = SearchRequest(query: query, provider: .google)
            guard let googleURL = WebSearchBuilder.searchURL(for: googleReq),
                  let googleComponents = URLComponents(url: googleURL, resolvingAgainstBaseURL: false) else {
                XCTFail("Failed to build/parse Google URL for query: \(query)")
                continue
            }
            let googleParsedQuery = googleComponents.queryItems?.first(where: { $0.name == "q" })?.value
            XCTAssertEqual(googleParsedQuery, query, "Google search query parameter must match original query exactly")

            // YouTube
            let ytReq = SearchRequest(query: query, provider: .youtube)
            guard let ytURL = WebSearchBuilder.searchURL(for: ytReq),
                  let ytComponents = URLComponents(url: ytURL, resolvingAgainstBaseURL: false) else {
                XCTFail("Failed to build/parse YouTube URL for query: \(query)")
                continue
            }
            let ytParsedQuery = ytComponents.queryItems?.first(where: { $0.name == "search_query" })?.value
            XCTAssertEqual(ytParsedQuery, query, "YouTube search query parameter must match original query exactly")
        }
    }

    func testEmptySearchQueryReturnsNil() {
        let request = SearchRequest(query: "   ", provider: .google)
        XCTAssertNil(WebSearchBuilder.searchURL(for: request))
    }

    // MARK: - Executor Tests

    func testExecutesBrowserOpenURLSuccessfully() throws {
        let control = FakeBrowserControl()
        let executor = BrowserCommandExecutor(control: control)

        let targetURL = URL(string: "https://github.com")!
        let intent = CommandIntent(identifier: .browserOpenURL, arguments: .url(targetURL))

        let feedback = try executor.execute(intent, context: .test())
        XCTAssertEqual(feedback, "Opened github.com")
        XCTAssertEqual(control.openedURLs, [targetURL])
    }

    func testExecutesBrowserSearchSuccessfully() throws {
        let control = FakeBrowserControl()
        let executor = BrowserCommandExecutor(control: control)

        let searchRequest = SearchRequest(query: "swiftui testing", provider: .google)
        let intent = CommandIntent(identifier: .browserSearch, arguments: .search(searchRequest))

        let feedback = try executor.execute(intent, context: .test())
        XCTAssertEqual(feedback, "Searched Google for 'swiftui testing'")
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.contains("swiftui%20testing") ?? false)
    }

    func testExecutorPropagatesControlFailure() {
        let control = FakeBrowserControl()
        control.shouldFail = true
        let executor = BrowserCommandExecutor(control: control)

        let targetURL = URL(string: "https://github.com")!
        let intent = CommandIntent(identifier: .browserOpenURL, arguments: .url(targetURL))

        XCTAssertThrowsError(try executor.execute(intent, context: .test()))
    }

    func testExecutesBrowserOpenDefaultSuccessfully() throws {
        let control = FakeBrowserControl()
        control.defaultBrowserFeedback = "Opened Safari"
        let executor = BrowserCommandExecutor(control: control)

        let intent = CommandIntent(identifier: .browserOpenDefault, arguments: .none)
        let feedback = try executor.execute(intent, context: .test())

        XCTAssertEqual(feedback, "Opened Safari")
        XCTAssertTrue(control.didOpenDefaultBrowser)
    }

    func testExecutesBrowserOpenPrivateSuccessfully() throws {
        let control = FakeBrowserControl()
        control.privateWindowFeedback = "Opened private window in Google Chrome"
        let executor = BrowserCommandExecutor(control: control)

        let intent = CommandIntent(identifier: .browserOpenPrivate, arguments: .none)
        let feedback = try executor.execute(intent, context: .test())

        XCTAssertEqual(feedback, "Opened private window in Google Chrome")
        XCTAssertTrue(control.didOpenPrivateWindow)
    }

    func testExecutesBrowserOpenPrivatePropagatesHonestUnsupportedFailure() {
        let control = FakeBrowserControl()
        control.privateWindowError = .operationFailed("Safari does not support launching private browsing directly.")
        let executor = BrowserCommandExecutor(control: control)

        let intent = CommandIntent(identifier: .browserOpenPrivate, arguments: .none)

        XCTAssertThrowsError(try executor.execute(intent, context: .test())) { error in
            guard case let CommandExecutionError.operationFailed(msg) = error else {
                XCTFail("Expected operationFailed error, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Safari does not support"))
        }
    }
}

