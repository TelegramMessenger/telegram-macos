import Foundation

public func appRelaunchProcess(bundleURL: URL = Bundle.main.bundleURL, parentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier, openerURL: URL = URL(fileURLWithPath: "/usr/bin/open")) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
        "-c",
        """
        while /bin/kill -0 "$1" 2>/dev/null; do
            /bin/sleep 0.1
        done
        exec "$2" -n "$3"
        """,
        "telegram-relaunch",
        String(parentProcessIdentifier),
        openerURL.path,
        bundleURL.path
    ]
    return process
}
