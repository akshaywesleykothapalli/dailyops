import XCTest
import Contacts
@testable import DailyOps

@MainActor
final class WhatsAppContactResolverTests: XCTestCase {
    func testDirectPhoneNumberResolvesWithoutContactsFramework() {
        let resolver = SystemWhatsAppContactResolver()
        let result = resolver.resolve(nameOrQuery: "+14155552671")
        guard case .resolved(let contact) = result else {
            return XCTFail("Expected resolved contact for direct phone number")
        }
        XCTAssertEqual(contact.phoneNumber, "14155552671")
    }

    func testFakeResolverReturnsExactSeededOutcomes() {
        let john = WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")
        let johnSmith = WhatsAppContact(name: "John Smith", phoneNumber: "14155555678")

        let resolver = FakeWhatsAppContactResolver(responses: [
            "John": .ambiguous([john, johnSmith]),
            "Alice": .resolved(WhatsAppContact(name: "Alice", phoneNumber: "14155559999")),
            "DeniedUser": .unavailable(reason: "Permission denied"),
        ])

        XCTAssertEqual(resolver.resolve(nameOrQuery: "Alice"), .resolved(WhatsAppContact(name: "Alice", phoneNumber: "14155559999")))

        if case .ambiguous(let matches) = resolver.resolve(nameOrQuery: "John") {
            XCTAssertEqual(matches.count, 2)
            XCTAssertEqual(matches.map(\.name), ["John Appleseed", "John Smith"])
        } else {
            XCTFail("Expected ambiguous matches for John")
        }

        XCTAssertEqual(resolver.resolve(nameOrQuery: "Bob"), .notFound(query: "Bob"))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "DeniedUser"), .unavailable(reason: "Permission denied"))
    }

    func testDynamicContactNamesResolvedCaseInsensitively() {
        let tarun = WhatsAppContact(name: "Tarun", phoneNumber: "14155551111")
        let rahulKumar = WhatsAppContact(name: "Rahul Kumar", phoneNumber: "14155552222")
        let priyaSharma = WhatsAppContact(name: "Priya Sharma", phoneNumber: "14155553333")
        let mom = WhatsAppContact(name: "Mom", phoneNumber: "14155554444")

        let resolver = FakeWhatsAppContactResolver(responses: [
            "Tarun": .resolved(tarun),
            "Rahul Kumar": .resolved(rahulKumar),
            "Priya Sharma": .resolved(priyaSharma),
            "Mom": .resolved(mom),
        ])

        XCTAssertEqual(resolver.resolve(nameOrQuery: "Tarun"), .resolved(tarun))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "tarun"), .resolved(tarun))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "Rahul Kumar"), .resolved(rahulKumar))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "rahul kumar"), .resolved(rahulKumar))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "Priya Sharma"), .resolved(priyaSharma))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "Mom"), .resolved(mom))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "mom"), .resolved(mom))

        // Non-existent arbitrary contact returns notFound
        XCTAssertEqual(resolver.resolve(nameOrQuery: "Alexander"), .notFound(query: "Alexander"))
        XCTAssertEqual(resolver.resolve(nameOrQuery: "SomeoneWhoDoesNotExist"), .notFound(query: "SomeoneWhoDoesNotExist"))
    }

    // MARK: - Phone Number Priority Tests

    func testPrioritizesMobileOverHome() {
        let home = CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "14155551111"))
        let mobile = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "14155552222"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [home, mobile])
        XCTAssertEqual(result, "14155552222")
    }

    func testPrioritizesMobileOverWork() {
        let work = CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "14155553333"))
        let mobile = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "14155554444"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [work, mobile])
        XCTAssertEqual(result, "14155554444")
    }

    func testPrioritizesiPhoneOverHome() {
        let home = CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "14155555555"))
        let iphone = CNLabeledValue(label: CNLabelPhoneNumberiPhone, value: CNPhoneNumber(stringValue: "14155556666"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [home, iphone])
        XCTAssertEqual(result, "14155556666")
    }

    func testFallbackToHomeOnlyWhenNoMobileAvailable() {
        let home = CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "14155557777"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [home])
        XCTAssertEqual(result, "14155557777")
    }

    func testFallbackToWorkOnlyWhenNoMobileAvailable() {
        let work = CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "14155558888"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [work])
        XCTAssertEqual(result, "14155558888")
    }

    func testMultipleMobileNumbersSelectsFirstMobile() {
        let mobile1 = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "14155550001"))
        let mobile2 = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "14155550002"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [mobile1, mobile2])
        XCTAssertEqual(result, "14155550001")
    }

    func testCustomMobileLabelIsRecognized() {
        let home = CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "14155551111"))
        let customCell = CNLabeledValue(label: "Personal Cell", value: CNPhoneNumber(stringValue: "14155559999"))
        let result = SystemWhatsAppContactResolver.selectPreferredPhoneNumber(from: [home, customCell])
        XCTAssertEqual(result, "14155559999")
    }
}
