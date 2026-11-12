@testable import KeyPathAppKit
import XCTest

/// `keypath-cli` is installed as a link in the user's own `~/.local/bin`, so it
/// needs no administrator password and uninstall can remove it.
final class CommandLineToolInstallerTests: XCTestCase {
    private var home: URL!
    private var tool: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("cli-link-\(UUID().uuidString)")
        tool = home.appendingPathComponent("Applications/KeyPath.app/Contents/MacOS/keypath-cli")
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var link: String {
        CommandLineToolInstaller.linkPath(home: home)
    }

    func testTheLinkLivesInTheUsersLocalBin() {
        XCTAssertEqual(link, home.appendingPathComponent(".local/bin/keypath-cli").path)
    }

    func testInstallCreatesTheFolderAndPointsTheLinkAtTheBundledTool() throws {
        try CommandLineToolInstaller.install(toolPath: tool.path, home: home)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), tool.path)
    }

    func testInstallReplacesAnOlderKeyPathLink() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: link).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Old/KeyPath.app/Contents/MacOS/keypath-cli")

        try CommandLineToolInstaller.install(toolPath: tool.path, home: home)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), tool.path)
    }

    func testInstallRefusesToOverwriteSomeoneElsesFile() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: link).deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: link, contents: Data("mine".utf8))

        XCTAssertThrowsError(try CommandLineToolInstaller.install(toolPath: tool.path, home: home))
        XCTAssertEqual(try String(contentsOfFile: link, encoding: .utf8), "mine")
    }

    func testUninstallRemovesOnlyKeyPathsLink() throws {
        try CommandLineToolInstaller.install(toolPath: tool.path, home: home)
        XCTAssertTrue(try CommandLineToolInstaller.uninstall(toolPath: tool.path, home: home))
        var info = stat()
        XCTAssertNotEqual(lstat(link, &info), 0)

        FileManager.default.createFile(atPath: link, contents: Data("mine".utf8))
        XCTAssertFalse(try CommandLineToolInstaller.uninstall(toolPath: tool.path, home: home))
        XCTAssertEqual(try String(contentsOfFile: link, encoding: .utf8), "mine")
    }

    /// Uninstalling a second copy must not break the link to the copy that stays.
    func testUninstallKeepsALinkToAnotherInstalledCopy() throws {
        try CommandLineToolInstaller.install(toolPath: tool.path, home: home)
        let otherCopy = home.appendingPathComponent("Downloads/KeyPath.app/Contents/MacOS/keypath-cli").path

        XCTAssertFalse(try CommandLineToolInstaller.uninstall(toolPath: otherCopy, home: home))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), tool.path)
    }

    func testUninstallRemovesALinkToAKeyPathThatIsGone() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: link).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Gone/KeyPath.app/Contents/MacOS/keypath-cli")

        XCTAssertTrue(try CommandLineToolInstaller.uninstall(toolPath: tool.path, home: home))
    }

    func testInstallRefusesADanglingLinkThatIsNotKeyPaths() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: link).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/somewhere/else")

        XCTAssertThrowsError(try CommandLineToolInstaller.install(toolPath: tool.path, home: home))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), "/somewhere/else")
    }
}
