import Foundation
import Testing
@testable import MoraClean

struct SupportLinksTests {
    @Test func linksPointToTheProjectAccounts() {
        #expect(SupportLinks.githubSponsors.absoluteString == "https://github.com/sponsors/ozanmora")
        #expect(SupportLinks.buyMeACoffee.absoluteString == "https://buymeacoffee.com/ozanmora")
        #expect([SupportLinks.githubSponsors, SupportLinks.buyMeACoffee].allSatisfy { $0.scheme == "https" })
    }
}
