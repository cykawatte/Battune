# Privacy

Battune operates locally. There are no accounts, telemetry, analytics, tracking,
advertising, cloud services, automatic update checks or runtime network requests.
No battery data is transmitted to a developer or third party.

Preferences and a calibration recovery journal are stored in the app's UserDefaults
domain (`org.battune.app`). Optional battery history is stored under the user's
Application Support/Battune directory, with approximately 30 days / 8,640 samples
maximum. Readings contain timestamps and battery metrics, not account or hardware
identifiers. Disable recording in General and delete existing history in Statistics.

Diagnostics contain app/OS version, architecture, capabilities, charge state and
errors. They omit user names, home paths, serial numbers and UUIDs. Copying a report
is a user action; Battune never sends it anywhere. OSLog uses categories and generic
errors; it does not log sensitive payloads or persistent machine identifiers.

Launch at login, notification permission and helper installation are explicit user
choices. macOS controls its own service-registration and notification metadata.
Deleting the app does not automatically delete preferences/history; remove them
separately if desired after resetting control and unregistering any helper.

Developer tool installation, CI and future signing/notarization may use the network;
these are not runtime application features and must not be confused with telemetry.
