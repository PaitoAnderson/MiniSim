import AppKit

class AppleUtils {
  static var shell: ShellProtocol = Shell()
  static var workspace: NSWorkspace = .shared
  static var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

  static func clearDerivedData(
    completionQueue: DispatchQueue = .main,
    completion: @escaping (String, Error?) -> Void
  ) {
    DispatchQueue.global(qos: .background).async {
      do {
        let amountCleared = try? shell.execute(command: "du -sh \(DeviceConstants.derivedDataLocation)")
          .match(###"\d+\.?\d+\w+"###).first?.first
        try shell.execute(command: "rm -rf \(DeviceConstants.derivedDataLocation)")
        completionQueue.async {
          completion(amountCleared ?? "", nil)
        }
      } catch {
        completionQueue.async {
          completion("", error)
        }
      }
    }
  }

  /// Xcode 27 removed `Contents/Developer/Applications` and replaced Simulator.app
  /// with Device Hub, which ships next to Instruments in `Contents/Applications`.
  /// Returns the GUI app to launch, or nil when neither is installed.
  static func simulatorApp(developerDir: String) -> (path: String, isDeviceHub: Bool)? {
    let simulator = "\(developerDir)/Applications/\(DeviceConstants.BundleURL.simulator.rawValue)"
    if fileExists(simulator) {
      return (simulator, false)
    }

    let deviceHub = URL(fileURLWithPath: developerDir)
      .deletingLastPathComponent()
      .appendingPathComponent("Applications")
      .appendingPathComponent(DeviceConstants.BundleURL.deviceHub.rawValue)
      .path
    if fileExists(deviceHub) {
      return (deviceHub, true)
    }

    return nil
  }

  static func launchSimulatorApp(uuid: String) throws {
    let isSimulatorRunning = workspace.runningApplications
      .contains {
        $0.bundleIdentifier == DeviceConstants.BundleID.simulator.rawValue ||
          $0.bundleIdentifier == DeviceConstants.BundleID.deviceHub.rawValue
      }

    guard !isSimulatorRunning else { return }

    guard let activeDeveloperDir = try? shell.execute(
      command: DeviceConstants.ProcessPaths.xcodeSelect.rawValue,
      arguments: ["-p"]
    )
      .trimmingCharacters(in: .whitespacesAndNewlines),
      let app = simulatorApp(developerDir: activeDeveloperDir) else {
      throw DeviceError.xcodeError
    }

    // Launch through LaunchServices rather than exec'ing the binary: Device Hub is
    // sandboxed and has to be started as an app bundle.
    var arguments = ["-a", app.path]
    if !app.isDeviceHub {
      // Device Hub shows every booted device in a single window and ignores this flag.
      arguments += ["--args", "-CurrentDeviceUDID", uuid]
    }

    try shell.execute(
      command: DeviceConstants.ProcessPaths.open.rawValue,
      arguments: arguments
    )
  }
}
