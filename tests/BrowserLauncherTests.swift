import Foundation

// Test double for Foundation.Process. Because this type is declared in the
// test module, it shadows Foundation.Process for BrowserLauncher.swift, which
// is compiled into the same executable. BrowserLauncher.launch() only assigns
// executableURL and arguments and then calls run(). This spy records those
// values and never starts a process, so no browser is ever spawned.
final class Process {
    static var created: [Process] = []

    var executableURL: URL?
    var arguments: [String]?
    private(set) var runCount = 0

    init() {
        Process.created.append(self)
    }

    func run() throws {
        runCount += 1
    }
}

// Test replacement for src/AppEnvironment.swift, which is excluded from the
// test build. The real BrowserLauncher reads only isSandboxed from it, so the
// test controls the sandbox branch through this variable.
enum AppEnvironment {
    static var isSandboxed = false
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private let safariPath = "/Applications/Safari.app"
private let chromePath = "/Applications/Google Chrome.app"
private let firefoxPath = "/Applications/Firefox.app"
private let customPath = "/Users/example/Apps/Custom Browser.app"

// Contains characters that are special to URLs (query, escapes, fragment).
// It must reach `open` as a single argument, unchanged.
private let complexURL = URL(
    string: "https://example.com/search?q=a%20b&lang=ja&tag=x#results"
)!

private func safariProfile(appPath: String? = safariPath) -> BrowserProfile {
    BrowserProfile(
        browserId: "com.apple.Safari",
        browserName: "Safari",
        directoryName: "Default",
        name: "Safari",
        isProfileSupported: false,
        appPath: appPath
    )
}

private func chromeProfile(appPath: String? = chromePath) -> BrowserProfile {
    BrowserProfile(
        browserId: "com.google.Chrome",
        browserName: "Google Chrome",
        directoryName: "Profile 1",
        name: "Work",
        isProfileSupported: true,
        appPath: appPath
    )
}

// Runs the real BrowserLauncher.launch and returns the single spy process it created.
private func launchAndCapture(
    url: URL,
    profile: BrowserProfile,
    sandboxed: Bool
) throws -> Process {
    Process.created = []
    AppEnvironment.isSandboxed = sandboxed
    BrowserLauncher.launch(url: url, profile: profile)

    guard Process.created.count == 1, let task = Process.created.first else {
        throw TestFailure(
            message: "expected exactly one Process spy, got \(Process.created.count)"
        )
    }
    guard task.runCount == 1 else {
        throw TestFailure(message: "expected run() to be called once, got \(task.runCount)")
    }
    return task
}

private func expectOpenInvocation(_ task: Process, _ expected: [String]) throws {
    let executable = task.executableURL?.path ?? "<nil>"
    guard executable == "/usr/bin/open" else {
        throw TestFailure(message: "expected executable /usr/bin/open, got \(executable)")
    }
    guard task.arguments == expected else {
        throw TestFailure(
            message: "expected arguments \(expected), got \(task.arguments ?? [])"
        )
    }
}

// AC-1 (and AC-6): Safari does not support profile arguments. Outside the
// sandbox, the URL must be passed as an open document: `-n -a <app> <url>`,
// with no `--args`. The complex URL must stay one unchanged argument.
// Currently fails: the non-sandboxed branch always inserts `--args` first.
func testSafariNonSandboxedPassesURLAsDocument() throws {
    let task = try launchAndCapture(
        url: complexURL,
        profile: safariProfile(),
        sandboxed: false
    )
    try expectOpenInvocation(
        task,
        ["-n", "-a", safariPath, complexURL.absoluteString]
    )
}

// AC-2: Chrome supports profiles. Outside the sandbox, `--args` followed by
// `--profile-directory=` and then the URL must be preserved. Regression guard.
func testChromeNonSandboxedKeepsProfileArgumentsBeforeURL() throws {
    let task = try launchAndCapture(
        url: complexURL,
        profile: chromeProfile(),
        sandboxed: false
    )
    try expectOpenInvocation(
        task,
        [
            "-n", "-a", chromePath,
            "--args", "--profile-directory=Profile 1",
            complexURL.absoluteString,
        ]
    )
}

// AC-3: Inside the sandbox, profile arguments are omitted whether or not the
// browser supports them. Only `-n -a <app> <url>` is produced. Regression guard.
func testSandboxedOmitsProfileArgumentsForSupportedAndUnsupportedBrowsers() throws {
    let chromeTask = try launchAndCapture(
        url: complexURL,
        profile: chromeProfile(),
        sandboxed: true
    )
    try expectOpenInvocation(
        chromeTask,
        ["-n", "-a", chromePath, complexURL.absoluteString]
    )

    let safariTask = try launchAndCapture(
        url: complexURL,
        profile: safariProfile(),
        sandboxed: true
    )
    try expectOpenInvocation(
        safariTask,
        ["-n", "-a", safariPath, complexURL.absoluteString]
    )
}

// AC-4: With no stored appPath, launch falls back to
// /Applications/<browserName>.app. The profile arguments are still kept
// outside the sandbox. Regression guard.
func testNilAppPathFallsBackToApplicationsFolder() throws {
    let task = try launchAndCapture(
        url: complexURL,
        profile: chromeProfile(appPath: nil),
        sandboxed: false
    )
    try expectOpenInvocation(
        task,
        [
            "-n", "-a", "/Applications/Google Chrome.app",
            "--args", "--profile-directory=Profile 1",
            complexURL.absoluteString,
        ]
    )
}

// AC-5: Browsers without profile support (Firefox, and a user-added custom
// app) must open the URL as an open document outside the sandbox, with no
// `--args`. Currently fails for both profiles.
func testUnsupportedFirefoxAndCustomBrowserPassURLAsDocument() throws {
    let firefoxProfile = BrowserProfile(
        browserId: "org.mozilla.firefox",
        browserName: "Firefox",
        directoryName: "Default",
        name: "Firefox",
        isProfileSupported: false,
        appPath: firefoxPath
    )
    let firefoxTask = try launchAndCapture(
        url: complexURL,
        profile: firefoxProfile,
        sandboxed: false
    )
    try expectOpenInvocation(
        firefoxTask,
        ["-n", "-a", firefoxPath, complexURL.absoluteString]
    )

    let customProfile = BrowserProfile(
        browserId: "custom-1",
        browserName: "Custom Browser",
        directoryName: "Default",
        name: "Custom Browser",
        isProfileSupported: false,
        appPath: customPath
    )
    let customTask = try launchAndCapture(
        url: complexURL,
        profile: customProfile,
        sandboxed: false
    )
    try expectOpenInvocation(
        customTask,
        ["-n", "-a", customPath, complexURL.absoluteString]
    )
}

// AC-7 (RecentLaunchStore bookkeeping) is not covered here. It is recorded on
// the main queue, and checking it would need a run-loop wait, which would
// make the test timing-dependent.

@main
enum BrowserLauncherTestRunner {
    static func main() {
        let tests: [(name: String, body: () throws -> Void)] = [
            ("AC-1/AC-6 Safari non-sandboxed passes URL as open document", testSafariNonSandboxedPassesURLAsDocument),
            ("AC-2 Chrome non-sandboxed keeps profile args before URL", testChromeNonSandboxedKeepsProfileArgumentsBeforeURL),
            ("AC-3 sandboxed omits profile args (supported and unsupported)", testSandboxedOmitsProfileArgumentsForSupportedAndUnsupportedBrowsers),
            ("AC-4 nil appPath falls back to /Applications", testNilAppPathFallsBackToApplicationsFolder),
            ("AC-5 Firefox and custom browser non-sandboxed pass URL as open document", testUnsupportedFirefoxAndCustomBrowserPassURLAsDocument),
        ]

        var failures = 0
        for test in tests {
            do {
                try test.body()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
