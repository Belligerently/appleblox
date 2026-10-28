import Foundation
import Testing
@testable import AppleBloxCore

@Test func experienceSearchUsesEncodedPublicQueriesAndValidatesDeduplicatesResults() async throws {
    let search = ExperienceSearch { url in
        #expect(url.host == "apis.roblox.com")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "searchQuery" }?.value == "obby & fun")
        #expect(query?.first { $0.name == "pageToken" }?.value == "a+b/=")
        return Data(#"{"searchResults":[{"contentGroupType":"Game","contents":[{"rootPlaceId":123,"universeId":456,"name":"Game","playerCount":3},{"rootPlaceId":123,"universeId":456,"name":"Duplicate"},{"rootPlaceId":0,"universeId":456,"name":"Invalid"},{"rootPlaceId":2,"universeId":456,"name":"Advertisement","isSponsored":true},{"rootPlaceId":3,"universeId":456,"name":"Other","playerCount":-1}]},{"contentGroupType":"User","contents":[{"name":"User"}]}],"nextPageToken":"next"}"#.utf8)
    }
    let page = try await search.search(" obby & fun ", session: UUID(), page: "a+b/=")
    #expect(page.results.map(\.placeID) == ["123", "3"])
    #expect(page.results.first?.websiteURL.absoluteString == "https://www.roblox.com/games/123")
    #expect(page.results.last?.playing == nil)
    #expect(page.nextPage == "next")
}
@Test func experienceSearchEmptyResultsAndRepeatedTokensEndPagination() async throws {
    let search = ExperienceSearch { _ in Data(#"{"searchResults":[],"nextPageToken":"same"}"#.utf8) }
    let page = try await search.search("nothing", session: UUID(), page: "same")
    #expect(page.results.isEmpty)
    #expect(page.nextPage == nil)
}
@Test func experienceSearchRejectsInvalidQueriesBeforeNetworkAndSurfacesMalformedData() async throws {
    let search = ExperienceSearch { _ in Issue.record("Invalid input sent to Roblox"); return Data() }
    for query in ["", "a", String(repeating: "x", count: 101), "some\nquery"] {
        await #expect(throws: (any Error).self) { try await search.search(query, session: UUID()) }
    }
    let broken = ExperienceSearch { _ in Data("{".utf8) }
    await #expect(throws: (any Error).self) { try await broken.search("test", session: UUID()) }
    let large = ExperienceSearch { _ in Data(repeating: 65, count: 1_000_001) }
    await #expect(throws: (any Error).self) { try await large.search("test", session: UUID()) }
}
@Test func experienceSearchCancellationDiscardsLateResponse() async throws {
    let search = ExperienceSearch { _ in
        try? await Task.sleep(for: .milliseconds(30))
        return Data(#"{"searchResults":[]}"#.utf8)
    }
    let task = Task { try await search.search("test", session: UUID()) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
