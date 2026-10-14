# Battune 0.2.0-beta.1

## Deutsch

1. Falls Battune bereits läuft: über das Menüleistensymbol beenden.
2. **Battune-0.2.0-beta.1.pkg** öffnen und die Administrator-Installation bestätigen.
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

### Update von 0.1 / Neuinstallation

Der Helper aus 0.1 passt nicht zur App 0.2 (Protokoll und Codesignaturen). Immer das
vollständige Paket installieren. Für eine saubere Neuinstallation: Battune beenden,
`sudo bash Uninstall-Battune.sh` ausführen (entfernt App, Helper und Paketbelege,
behält Einstellungen und Verlauf), dann das Paket installieren.

### Hardware-Prüfliste 0.2

1. Einrichtung → Helper-Status zeigt „0.2.0-beta.1“; Hardwaretest bestätigen (Deckel offen, Netzteil, ≥ 30 %, < 40 °C).
2. Laden → Grenze 80 %: Popover zeigt „Gehalten · Betrieb über Netzteil“, Energiefluss Netzteil → Mac, Akku ≈ 0 W.
3. Grenze 77 % (erweiterter Modus): Deckel offen → Adapter hält; Deckel mit externem Monitor schließen →
   kein Sperrbildschirm, Netzteil sofort wieder aktiv, Popover zeigt „Geschützt durch macOS-Grenze (80 %)“.
4. Voll laden → macOS-Grenze 100 %; Netzteil abziehen → Grenze springt zurück.
5. Pause bei z. B. 83 % → macOS-Stufe 85 %; Fortsetzen → konfigurierte Grenze.
6. Energie → MagSafe-LED „Ladezustand zeigen“: grün beim Halten, orange beim Laden; Beenden → macOS übernimmt.
7. Energie → Stromsparmodus „Nur im Akkubetrieb“: `pmset -g custom` zeigt `lowpowermode 1` nur im Akkuprofil.
8. Battune beenden → Grenze bleibt (Systemeinstellungen → Batterie), sofern „beibehalten“ aktiv ist.

## English

Upgrading from 0.1 requires the full package: the 0.1 helper does not match the
0.2 app. For a clean reinstall run `sudo bash Uninstall-Battune.sh` first (keeps
settings and history). Quit an existing Battune instance, open **Battune-0.2.0-beta.1.pkg**, approve the
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

## Native limits and standby / Native Grenzen und Standby

Supported limits (80/85/90/95/100% on the tested Mac) always use macOS control,
even with advanced mode unlocked. Battune keeps adapter input enabled and does
not clear the native limit on sleep. Explicit discharge/calibration temporarily
uses the helper and returns to the native limit afterwards. Apple may occasionally
exceed native limits for gauge calibration; this is not a promise of an absolute ceiling.
Other limits still require adapter mode: battery use during holds, no enforcement
while asleep. Physical overnight sleep behavior remains to be measured.

**Deutsch:** Bei unterstützten Grenzen wie 80 % bleibt der Netzteileingang aktiv.
Der erweiterte Modus ersetzt diese Regelung nicht mehr durch Batteriezyklen.
Die native Grenze bleibt im Standby gesetzt; gelegentliche Apple-Vollladungen zur
Messwertkalibrierung bleiben möglich. Andere Grenzen gelten nur im Wachzustand.
