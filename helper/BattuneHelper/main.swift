import BattuneHardware
import Darwin

if CommandLine.arguments.contains("--restore-owned-state") {
  guard geteuid() == 0 else { exit(1) }
  do { try AdapterBackend().recover() } catch { exit(1) }
} else {
  HelperListener.run()
}
