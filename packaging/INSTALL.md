# Battune 0.1.0-beta.1

## Deutsch

1. Falls Battune bereits läuft: über das Menüleistensymbol beenden.
2. **Battune-0.1.0-beta.1.pkg** öffnen und die Administrator-Installation bestätigen.
   Das Paket installiert die App nach `/Applications/Battune.app` und den passenden Helper.
3. Battune unter Programme öffnen. Das kurze Tutorial erklärt die Kernfunktionen.
4. Für freie 20–100-%-Grenzen, Entladeziel und Kalibrierung: unter Einrichtung den
   Hardwaretest bestätigen und den erweiterten Modus einschalten. Netzteil angeschlossen,
   mindestens 30 % Ladung, unter 40 °C. Unter Laden die Steuerung aktivieren und speichern.
   Native macOS-Grenzen benötigen den erweiterten Modus nicht.

**BattuneHelper.pkg** ist nur zur separaten Reparatur/Aktualisierung des Helpers gedacht;
bei einer vollständigen Installation ist dieser bereits enthalten. Bei einem neuen
App-Build auch den passenden Helper installieren: die Codesignaturen sind exakt gekoppelt.

Die Beta ist ad-hoc signiert, nicht mit Developer ID signiert und nicht notarisiert.
macOS kann den Download blockieren. Prüfe Quelle und SHA256SUMS.txt. Eine eventuelle
Ausnahme erteilst du selbst für genau diesen Download in Systemeinstellungen →
Datenschutz & Sicherheit. SIP und Gatekeeper müssen nicht global deaktiviert werden.
[Apple erklärt die Systemabfrage](https://support.apple.com/en-us/102445).
Das Repository und seine Downloads sind derzeit privat; Tester brauchen GitHub-Zugriff.

Adaptermodus nutzt während Ladepausen Batterie und erzeugt zusätzliche Zyklen.
Vor Schlaf wird der Netzteileingang wiederhergestellt; danach ist ein neuer Test nötig.
Bestätigt: reale CHIE-Aus-/Ein-Schaltung auf Mac16,12 / macOS 27.0.1. Vollständige
Kalibrierung, Langzeitbetrieb und Intel-Hardware sind noch nicht physisch geprüft.

Entfernen: Steuerung deaktivieren, Battune normal beenden, dann optional
`sudo bash Uninstall-Helper.sh`. Das Skript stellt eigenen Adapterzustand wieder her
und entfernt den Helper. Die App kann anschließend in den Papierkorb. Persönliche
Einstellungen und Verlauf bleiben erhalten. Autostart vorher in Battune deaktivieren.

## English

Quit an existing Battune instance, open **Battune-0.1.0-beta.1.pkg**, approve the
administrator installation, then launch Battune from Applications. The full package
includes both app and matching helper. Follow the short first-run tour. Advanced
20–100% limits, discharge and calibration require the explicit hardware test and
advanced-mode switch in Setup, then enabling control in Charging.

**BattuneHelper.pkg** is a helper-only repair package. It is unnecessary after the
full installer. Do not mix app/helper builds: exact code signatures must match.
This beta is ad-hoc signed and not notarized. Verify source/checksums; any macOS
security exception must be your explicit decision for this download. Do not disable
system-wide protections. The repository/downloads are private and require access.

Adapter-mode holds consume battery and add cycles; sleep restores the adapter and
requires revalidation. Complete calibration, long-term operation and Intel hardware
are not physically validated. To uninstall: disable control, quit normally, run
`sudo bash Uninstall-Helper.sh`, then remove the app. Local history/settings remain.
