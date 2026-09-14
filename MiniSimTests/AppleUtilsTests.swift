@testable import MiniSim
import XCTest

class MockNSWorkspace: NSWorkspace {
  var mockRunningApplications: [NSRunningApplication] = []

  override var runningApplications: [NSRunningApplication] {
    mockRunningApplications
  }
}

class MockNSRunningApplication: NSRunningApplication {
  let mockBundleIdentifier: String?

  init(bundleIdentifier: String?) {
    self.mockBundleIdentifier = bundleIdentifier
    super.init()
  }

  override var bundleIdentifier: String? {
    mockBundleIdentifier
  }
}

class AppleUtilsTests: XCTestCase {
  var shellStub: ShellStub!
  var mockWorkspace: MockNSWorkspace!

  override func setUp() {
    super.setUp()
    shellStub = ShellStub()

    mockWorkspace = MockNSWorkspace()
    AppleUtils.shell = shellStub
    AppleUtils.workspace = mockWorkspace
  }

  override func tearDown() {
    shellStub.tearDown()
    AppleUtils.fileExists = { FileManager.default.fileExists(atPath: $0) }
    super.tearDown()
  }

  func testClearDerivedData() {
    let expectation = self.expectation(description: "Completion handler called")

    shellStub.mockedExecute = { command, _, _ in
      if command.contains("du -sh") {
        return "100M    \(DeviceConstants.derivedDataLocation)"
      }
      return ""
    }

    AppleUtils.clearDerivedData { amountCleared, error in
      XCTAssertEqual(amountCleared, "100M")
      XCTAssertNil(error)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 5, handler: nil)

    XCTAssertTrue(shellStub.lastExecutedCommand.contains("rm -rf"))
    XCTAssertTrue(shellStub.lastExecutedCommand.contains(DeviceConstants.derivedDataLocation))
  }

  func testClearDerivedDataWithError() {
    let expectation = self.expectation(description: "Completion handler called")

    shellStub.mockedExecute = { _, _, _ in
      throw NSError(domain: "TestError", code: 1, userInfo: nil)
    }

    AppleUtils.clearDerivedData { amountCleared, error in
      XCTAssertEqual(amountCleared, "")
      XCTAssertNotNil(error)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 5, handler: nil)
  }

  private func stubXcodeSelect(developerDir: String = "/Applications/Xcode.app/Contents/Developer") {
    shellStub.mockedExecute = { command, _, _ in
      if command == DeviceConstants.ProcessPaths.xcodeSelect.rawValue {
        return developerDir
      }
      return ""
    }
  }

  func testLaunchSimulatorAppWhenNotRunning() {
    let uuid = "test-uuid"
    mockWorkspace.mockRunningApplications = [] // Simulator not running
    stubXcodeSelect()
    // Xcode 26 and earlier: Simulator.app is present.
    AppleUtils.fileExists = { $0.hasSuffix("Developer/Applications/Simulator.app") }

    XCTAssertNoThrow(try AppleUtils.launchSimulatorApp(uuid: uuid))

    XCTAssertEqual(shellStub.lastExecutedCommand, DeviceConstants.ProcessPaths.open.rawValue)
    XCTAssertEqual(shellStub.lastPassedArguments, [
      "-a",
      "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
      "--args",
      "-CurrentDeviceUDID",
      uuid
    ])
  }

  func testLaunchSimulatorAppFallsBackToDeviceHubOnXcode27() {
    let uuid = "test-uuid"
    mockWorkspace.mockRunningApplications = []
    stubXcodeSelect()
    // Xcode 27 removed Simulator.app; only Device Hub exists.
    AppleUtils.fileExists = { $0.hasSuffix("Contents/Applications/DeviceHub.app") }

    XCTAssertNoThrow(try AppleUtils.launchSimulatorApp(uuid: uuid))

    XCTAssertEqual(shellStub.lastExecutedCommand, DeviceConstants.ProcessPaths.open.rawValue)
    // Device Hub ignores -CurrentDeviceUDID, so it must not be passed.
    XCTAssertEqual(shellStub.lastPassedArguments, [
      "-a",
      "/Applications/Xcode.app/Contents/Applications/DeviceHub.app"
    ])
  }

  func testLaunchSimulatorAppThrowsWhenNoSimulatorAppInstalled() {
    mockWorkspace.mockRunningApplications = []
    stubXcodeSelect()
    AppleUtils.fileExists = { _ in false }

    XCTAssertThrowsError(try AppleUtils.launchSimulatorApp(uuid: "test-uuid")) { error in
      XCTAssertEqual(error as? DeviceError, DeviceError.xcodeError)
    }
  }

  func testLaunchSimulatorAppWhenAlreadyRunning() {
    let uuid = "test-uuid"
    mockWorkspace.mockRunningApplications = [
      MockNSRunningApplication(bundleIdentifier: DeviceConstants.BundleID.simulator.rawValue)
    ]

    XCTAssertNoThrow(try AppleUtils.launchSimulatorApp(uuid: uuid))

    XCTAssertTrue(shellStub.lastExecutedCommand.isEmpty, "Should not execute any command when simulator is already running")
  }

  func testLaunchSimulatorAppWhenDeviceHubAlreadyRunning() {
    let uuid = "test-uuid"
    mockWorkspace.mockRunningApplications = [
      MockNSRunningApplication(bundleIdentifier: DeviceConstants.BundleID.deviceHub.rawValue)
    ]

    XCTAssertNoThrow(try AppleUtils.launchSimulatorApp(uuid: uuid))

    XCTAssertTrue(shellStub.lastExecutedCommand.isEmpty, "Should not execute any command when Device Hub is already running")
  }

  func testLaunchSimulatorAppWithXcodeError() {
    shellStub.mockedExecute = { _, _, _ in
      throw DeviceError.xcodeError
    }

    XCTAssertThrowsError(try AppleUtils.launchSimulatorApp(uuid: "test-uuid")) { error in
      XCTAssertEqual(error as? DeviceError, DeviceError.xcodeError)
    }
  }
}
