import Cocoa
import CryptoKit
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var libraryAccessController: LibraryAccessController?
  private var restoringFullscreenState = false

  private static let minimumSize = NSSize(width: 960, height: 600)
  private static let preferredSize = NSSize(width: 1200, height: 800)
  private static let windowFrameAutosaveName = "dev.lore.app.mainWindow"
  private static let fullscreenKey = "dev.lore.app.mainWindowFullscreen"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // applySavedFrameOrDefault's setFrame (from autosave or the centered
    // default) also forces the freshly-installed content view to relayout —
    // same role as the stock template's `setFrame(self.frame, display: true)`.
    applySavedFrameOrDefault()
    delegate = self
    registerFullscreenObservers()
    prepareFullscreenRestore()

    RegisterGeneratedPlugins(registry: flutterViewController)
    libraryAccessController = LibraryAccessController(
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Restores the window to its last-used frame when one is saved, otherwise
  /// sizes and centers it for first launch. `minSize` is enforced every launch
  /// so a previously-saved frame still respects the workspace's lower bound.
  /// `setFrameAutosaveName` lets AppKit persist the frame across launches —
  /// the `frameAutosaveName` property is read-only in Swift, so the method
  /// form is required (it returns false if the name is already claimed).
  private func applySavedFrameOrDefault() {
    minSize = Self.minimumSize
    if setFrameAutosaveName(Self.windowFrameAutosaveName),
       setFrameUsingName(Self.windowFrameAutosaveName) {
      return
    }
    configureInitialFrame()
  }

  /// First-launch default: a comfortable writing size centered on the main
  /// screen. The size is clamped to the visible area and the configured
  /// minimum is lowered when necessary for a cramped display, so the launch
  /// window never violates `minSize` or drifts off-screen.
  private func configureInitialFrame() {
    // `visibleFrame` already excludes the menu bar and Dock; fall back to the
    // xib-provided frame if the screen is somehow unavailable at launch.
    let visibleFrame = NSScreen.main?.visibleFrame ?? frame
    let minimumWidth = min(Self.minimumSize.width, visibleFrame.width)
    let minimumHeight = min(Self.minimumSize.height, visibleFrame.height)
    minSize = NSSize(width: minimumWidth, height: minimumHeight)

    // Clamp to the visible area while respecting the adjusted minimum.
    let width = max(
      minimumWidth,
      min(Self.preferredSize.width, visibleFrame.width))
    let height = max(
      minimumHeight,
      min(Self.preferredSize.height, visibleFrame.height))

    // Center within the visible frame, then keep the full rect on-screen.
    let originX = max(
      visibleFrame.minX,
      min(visibleFrame.minX + (visibleFrame.width - width) / 2, visibleFrame.maxX - width))
    let originY = max(
      visibleFrame.minY,
      min(visibleFrame.minY + (visibleFrame.height - height) / 2, visibleFrame.maxY - height))

    setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
  }

  /// Persists the window's fullscreen state so it survives across launches.
  /// `frameAutosaveName` only stores the frame, not fullscreen, so we record
  /// the flag ourselves and restore it before the window first appears.
  private func registerFullscreenObservers() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(handleDidEnterFullscreen),
      name: NSWindow.didEnterFullScreenNotification,
      object: self)
    center.addObserver(
      self,
      selector: #selector(persistFullscreenState),
      name: NSWindow.didExitFullScreenNotification,
      object: self)
    center.addObserver(
      self,
      selector: #selector(snapshotFullscreenOnClose),
      name: NSWindow.willCloseNotification,
      object: self)
  }

  @objc private func persistFullscreenState() {
    UserDefaults.standard.set(styleMask.contains(.fullScreen), forKey: Self.fullscreenKey)
  }

  /// Keeps the normal window hidden while AppKit performs the required native
  /// fullscreen transition, then reveals it only after the fullscreen layout
  /// is ready.
  private func prepareFullscreenRestore() {
    guard UserDefaults.standard.bool(forKey: Self.fullscreenKey) else { return }
    restoringFullscreenState = true
    alphaValue = 0
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(restoreFullscreenStateIfPending),
      name: NSWindow.didBecomeKeyNotification,
      object: self)
  }

  @objc private func restoreFullscreenStateIfPending() {
    guard restoringFullscreenState else { return }
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didBecomeKeyNotification, object: self)
    toggleFullScreen(nil)
  }

  @objc private func handleDidEnterFullscreen() {
    persistFullscreenState()
    finishFullscreenRestore()
  }

  private func finishFullscreenRestore() {
    guard restoringFullscreenState else { return }
    restoringFullscreenState = false
    alphaValue = 1
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didBecomeKeyNotification, object: self)
  }

  /// Snapshots the fullscreen state when the window is about to close and
  /// stops listening to further transitions. macOS can exit fullscreen as part
  /// of tearing a fullscreen window down, so unsubscribing here keeps that
  /// teardown from overwriting the state the user actually ended in.
  @objc private func snapshotFullscreenOnClose() {
    persistFullscreenState()
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: self)
    center.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: self)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

extension MainFlutterWindow: NSWindowDelegate {
  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    UserDefaults.standard.set(false, forKey: Self.fullscreenKey)
    finishFullscreenRestore()
  }
}

final class LibraryAccessController {
  private static let channelName = "dev.lore.app/library_access"
  private static let bookmarkKey = "dev.lore.app.libraryBookmark.v1"

  private let channel: FlutterMethodChannel
  private let defaults: UserDefaults
  private var activeURL: URL?
  private var pendingURL: URL?
  private var pendingBookmark: Data?

  init(
    binaryMessenger: FlutterBinaryMessenger,
    defaults: UserDefaults = .standard
  ) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger)
    self.defaults = defaults
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "bookmark_unavailable",
          message: "书库授权服务不可用。",
          details: nil))
        return
      }
      self.handle(call: call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    discardPending()
    stopActiveAccess()
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "restoreLibraryDirectory":
      restore(result: result)
    case "selectLibraryDirectory":
      select(result: result)
    case "commitLibraryDirectory":
      commit(result: result)
    case "discardLibraryDirectorySelection":
      discardPending()
      result(nil)
    case "clearLibraryDirectory":
      discardPending()
      stopActiveAccess()
      defaults.removeObject(forKey: Self.bookmarkKey)
      result(nil)
    case "renameLibraryEntry":
      renameEntry(call: call, result: result)
    case "replaceLibraryDocument":
      replaceDocument(call: call, result: result)
    case "revealLibraryEntry":
      revealEntry(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func revealEntry(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let rootURL = activeURL else {
      result(flutterError(
        code: "access_denied",
        message: "书库目录授权已失效。"))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let relativePath = arguments["relativePath"] as? String,
      let fileURL = childURL(rootURL: rootURL, relativePath: relativePath)
    else {
      result(flutterError(
        code: "invalid_location",
        message: "路径超出了书库范围。"))
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    result(nil)
  }

  private func replaceDocument(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let rootURL = activeURL else {
      result(flutterError(
        code: "access_denied",
        message: "书库目录授权已失效。"))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let relativePath = arguments["relativePath"] as? String,
      let expectedRevision = arguments["expectedRevision"] as? String,
      let typedData = arguments["bytes"] as? FlutterStandardTypedData,
      let fileURL = childURL(rootURL: rootURL, relativePath: relativePath)
    else {
      result(flutterError(
        code: "invalid_location",
        message: "文档路径超出了书库范围。"))
      return
    }

    var coordinatorError: NSError?
    var operationError: Error?
    var revisionMatches = true
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(
      writingItemAt: fileURL,
      options: .forReplacing,
      error: &coordinatorError
    ) { coordinatedURL in
      do {
        let currentData = try Data(contentsOf: coordinatedURL)
        guard self.sha256(currentData) == expectedRevision else {
          revisionMatches = false
          return
        }
        try typedData.data.write(to: coordinatedURL, options: .atomic)
      } catch {
        operationError = error
      }
    }

    if !revisionMatches {
      result(false)
      return
    }
    if let error = operationError ?? coordinatorError {
      let nsError = error as NSError
      let code = nsError.domain == NSCocoaErrorDomain &&
        nsError.code == NSFileNoSuchFileError
        ? "not_found"
        : "save_failed"
      result(flutterError(code: code, message: "无法安全保存文档。"))
      return
    }
    result(true)
  }

  private func sha256(_ data: Data) -> String {
    return SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func renameEntry(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let rootURL = activeURL else {
      result(flutterError(
        code: "access_denied",
        message: "书库目录授权已失效。"))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      let targetPath = arguments["targetPath"] as? String,
      let sourceURL = childURL(rootURL: rootURL, relativePath: sourcePath),
      let targetURL = childURL(rootURL: rootURL, relativePath: targetPath),
      sourceURL.deletingLastPathComponent() == targetURL.deletingLastPathComponent()
    else {
      result(flutterError(
        code: "invalid_location",
        message: "重命名路径超出了书库范围。"))
      return
    }

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      result(flutterError(code: "not_found", message: "原文件不存在。"))
      return
    }
    guard !fileManager.fileExists(atPath: targetURL.path) else {
      result(flutterError(code: "name_conflict", message: "目标名称已存在。"))
      return
    }

    do {
      try fileManager.moveItem(at: sourceURL, to: targetURL)
      result(nil)
    } catch let error as NSError {
      let code = error.domain == NSCocoaErrorDomain &&
        error.code == NSFileWriteFileExistsError
        ? "name_conflict"
        : "rename_failed"
      result(flutterError(
        code: code,
        message: "无法重命名所选内容。"))
    }
  }

  private func childURL(rootURL: URL, relativePath: String) -> URL? {
    guard !relativePath.hasPrefix("/"), !relativePath.isEmpty else {
      return nil
    }
    let root = rootURL.standardizedFileURL
    let child = root.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard child.path.hasPrefix(rootPrefix) else {
      return nil
    }
    return child
  }

  private func restore(result: @escaping FlutterResult) {
    if let activeURL {
      result(accessResult(for: activeURL))
      return
    }
    guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
      result(nil)
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      guard url.startAccessingSecurityScopedResource() else {
        result(flutterError(
          code: "access_denied",
          message: "无法恢复书库目录访问权限。"))
        return
      }
      if isStale {
        do {
          let refreshedBookmark = try createBookmark(for: url)
          defaults.set(refreshedBookmark, forKey: Self.bookmarkKey)
        } catch {
          url.stopAccessingSecurityScopedResource()
          result(flutterError(
            code: "bookmark_resolution_failed",
            message: "无法刷新书库目录授权，请重新选择目录。"))
          return
        }
      }
      activeURL = url
      result(accessResult(for: url))
    } catch {
      result(flutterError(
        code: "bookmark_resolution_failed",
        message: "书库目录授权已失效，请重新选择目录。"))
    }
  }

  private func select(result: @escaping FlutterResult) {
    discardPending()

    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "选择书库目录"

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      result(nil)
      return
    }

    let url = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
    guard url.path != "/" else {
      result(flutterError(
        code: "invalid_location",
        message: "不能将文件系统根目录设为书库。"))
      return
    }

    do {
      let bookmark = try createBookmark(for: url)
      guard url.startAccessingSecurityScopedResource() else {
        result(flutterError(
          code: "access_denied",
          message: "无法访问所选目录。"))
        return
      }
      pendingURL = url
      pendingBookmark = bookmark
      result(accessResult(for: url))
    } catch {
      result(flutterError(
        code: "selection_failed",
        message: "无法保存所选目录的访问权限。"))
    }
  }

  private func commit(result: @escaping FlutterResult) {
    guard let pendingURL, let pendingBookmark else {
      result(flutterError(
        code: "bookmark_unavailable",
        message: "没有等待保存的书库目录授权。"))
      return
    }
    defaults.set(pendingBookmark, forKey: Self.bookmarkKey)
    stopActiveAccess()
    activeURL = pendingURL
    self.pendingURL = nil
    self.pendingBookmark = nil
    result(nil)
  }

  private func createBookmark(for url: URL) throws -> Data {
    return try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }

  private func discardPending() {
    pendingURL?.stopAccessingSecurityScopedResource()
    pendingURL = nil
    pendingBookmark = nil
  }

  private func stopActiveAccess() {
    activeURL?.stopAccessingSecurityScopedResource()
    activeURL = nil
  }

  private func accessResult(for url: URL) -> [String: String] {
    return [
      "token": url.path,
      "displayPath": url.path,
    ]
  }

  private func flutterError(code: String, message: String) -> FlutterError {
    return FlutterError(code: code, message: message, details: nil)
  }
}
