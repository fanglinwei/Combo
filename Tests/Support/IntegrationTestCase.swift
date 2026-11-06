import Testing
import AppKit
@testable import ComboTestHost

@Suite(.serialized, IntegrationTestScope())
enum IntegrationTests {}

struct IntegrationTestScope: TestTrait, SuiteTrait, TestScoping {
    let isRecursive = true

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        if test.isSuite {
            try await function()
        } else {
            try await withState(function)
        }
    }

    @MainActor
    private func withState(_ function: @Sendable () async throws -> Void) async throws {
        let state = try IntegrationTestState()
        defer { state.restore() }
        try await function()
    }
}

@MainActor
private final class IntegrationTestState {
    private let preferences: [String: Any]?
    private let mainMenu: NSMenu?
    private let servicesMenu: NSMenu?
    private let servicesMenuItem: NSMenuItem?
    private let servicesMenuTitle: String?
    private let applicationIcon: NSImage?
    private let namedApplicationIcon: NSImage?
    private let activationPolicy: NSApplication.ActivationPolicy

    init() throws {
        guard Bundle.main.bundleIdentifier == "local.combo.integration-host" else {
            throw NSError(domain: "IntegrationTestCase", code: 1)
        }
        // AppKit ignores servicesMenu = nil; establish a restorable native baseline for this host.
        if NSApp.servicesMenu == nil { NSApp.servicesMenu = NSMenu(title: "Services") }
        preferences = UserDefaults.standard.persistentDomain(forName: "local.combo.integration-host")
        activationPolicy = NSApp.activationPolicy()
        mainMenu = NSApp.mainMenu
        let servicesMenu = NSApp.servicesMenu
        self.servicesMenu = servicesMenu
        servicesMenuItem = servicesMenu?.supermenu?.items.first { $0.submenu === servicesMenu }
        servicesMenuTitle = servicesMenu?.title
        applicationIcon = NSApp.applicationIconImage
        namedApplicationIcon = NSImage(named: NSImage.applicationIconName)
    }

    func restore() {
        if let preferences {
            UserDefaults.standard.setPersistentDomain(preferences, forName: "local.combo.integration-host")
        } else {
            UserDefaults.standard.removePersistentDomain(forName: "local.combo.integration-host")
        }
        Localization.shared.refresh()
        if let servicesMenu {
            servicesMenu.supermenu?.items.first { $0.submenu === servicesMenu }?.submenu = nil
            servicesMenu.title = servicesMenuTitle ?? ""
            servicesMenuItem?.submenu = servicesMenu
        }
        NSApp.applicationIconImage = applicationIcon
        if NSImage(named: NSImage.applicationIconName) !== namedApplicationIcon {
            NSImage(named: NSImage.applicationIconName)?.setName(nil)
            namedApplicationIcon?.setName(NSImage.applicationIconName)
        }
        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = servicesMenu
        NSApp.setActivationPolicy(activationPolicy)
    }
}
