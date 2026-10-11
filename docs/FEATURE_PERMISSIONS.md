# Funktionsumfang und Freigaben — 2026-10-11

## Aktueller Nachweis

Administrator-Installation und der ausdrücklich genehmigte CHIE-Aus-/Ein-Test
wurden am 2026-10-11 erfolgreich durchgeführt. Beide Zustände wurden zurückgelesen;
danach waren Netzbetrieb und Laden wieder aktiv. Der Helper ist authentifiziert
und läuft als Root. [Prüfprotokoll](HARDWARE_VALIDATION_2026-10-11.md).

## Funktionsumfang

Die App implementiert zwei Steuerungswege. Native Ladegrenzen bleiben ohne eigenen
Root-Helper nutzbar. Der erweiterte Modus hat eine echte, eng begrenzte
AppleSMC-Anbindung; seine Funktionen werden erst nach Installation und einem
explizit freigegebenen, erfolgreichen Hardwaretest aktiviert. Ein erfolgreicher
Build oder Mock-Test wird nicht als erfolgreicher Eingriff am Gerät dargestellt.

| Funktion | Umsetzung | Erforderliche Freigabe |
|---|---|---|
| Native Ladegrenze | Von macOS gemeldete Werte, hier 80/85/90/95/100 % | App-Schalter; kein Root-Helper |
| Freie Ladegrenze | 20–100 % in 1-%-Schritten, Software-Regelkreis über Netzteileingang CHIE | Administrator-Installation + bestätigter Aus-/Ein-Test + erweiterter Modus |
| Sailing / Temperaturschutz | Eigene Grenzen im erweiterten Modus | Dieselbe Helper-Freigabe |
| Entladeziel | Netzteileingang aus bis zum Ziel, dann normale Regelung | Helper + Bestätigung beim Start |
| Kalibrierung | 100 % → 30 Minuten Stabilisierung → 20 % → 100 % → normale Regelung | Helper + Bestätigung beim Start |
| Statistik | Lokaler 30-Tage-Verlauf, 24h/7d/30d, Ladung/Temperatur/Leistung, CSV | Aufzeichnung in der App; Exportort im Sichern-Dialog |
| Diagnose | Feste SMC-Leseprüfung, Betriebssystem-/Backendstatus, Fehlercodes, Textexport | Keine zusätzliche Systemberechtigung |
| Mitteilungen | Temperaturpause und Steuerungsfehler | macOS-Mitteilungsdialog |
| Autostart | Bei Benutzeranmeldung starten | ServiceManagement / Systemeinstellungen |

Der erweiterte Modus trennt während Ladepausen den Netzteileingang. Der Mac läuft
dann auf Batterie, wodurch zusätzliche Zyklen entstehen. Ohne eigenes Sailing
wird fünf Prozentpunkte unter der Ladegrenze wieder geladen (bei 20 %: 19 %).
Die Grenze ist ein Softwareziel; Messintervalle und Last können zu Abweichungen
führen. Im Schlafmodus gilt diese Softwaregrenze nicht: der Helper stellt den
Netzteileingang wieder her. Nach Schlaf, Helper-Neustart oder Sicherheitsabbruch
wird ein erneuter Schalttest benötigt. Ein Kalibrierungszyklus garantiert keine
Verbesserung der Batteriezustandsanzeige.

## Auf diesem Mac tatsächlich beobachtet

Mac16,12, arm64, macOS 27.0.1 (26A434), Benutzerprozess ohne Root:

- `CHIE`: lesbar, ein Byte `00`, Typ `hex_`; Netzteileingang freigegeben.
- `AC-W`: lesbar; physischer Netzanschluss wird unabhängig vom geschalteten Eingang erkannt.
- `TB0T`: lesbar, Float-Temperatur; etwa 25–28 °C im Entwicklungsbetrieb.
- `bfF0`, `bfD0`, `bfE0`, `CH0J`: `0xE00002C1`, `kIOReturnNotPrivileged`.
- `CHTE`, `CH0B`, `CH0C`, `CH0I`: SMC-Ergebnis `0x84`, kein lesbarer Schlüssel.
- Native PowerUI-Ladegrenzen: reale Einstellung, Rücklesen und Wiederherstellung bereits geprüft.
- Kapazität, Spannung, Strom und Temperatur wurden in der neuen Statistik angezeigt;
  ein CSV-Export wurde direkt aus der App erzeugt und geprüft.

`NotPrivileged` im Benutzerprozess beweist nicht, dass auch Root gesperrt wird.
Für CHIE ist nun nachgewiesen, dass Root ausreicht. Für die anderen verweigerten
Schlüssel wurde kein Root-Test durchgeführt; deren Anforderungen bleiben unbekannt. Apple-interne Entitlements lassen sich nicht mit
einem normalen Berechtigungsdialog erteilen. Battune verändert weder SIP noch
andere Systemschutzregeln. Der implementierte Schreibweg verwendet nur `CHIE`,
nicht die verweigerten direkten Ladeschlüssel. Fehler dieses Schreibwegs werden
mit dem tatsächlichen IOReturn und der Prozess-UID ausgegeben.

## Lokale Installation nach Freigabe

1. `./scripts/build.sh release universal`
2. `./scripts/build-helper-installer.sh release` erzeugt nur das Paket; keine Installation.
3. In `build/release/Battune.app` unter **Einrichtung → Helper installieren** den
   macOS-Installer öffnen. Das passende `BattuneHelper.pkg` bleibt neben der App.
4. Installation im macOS-Dialog ausdrücklich mit Administratorrechten bestätigen.
5. Netzteil anschließen, mindestens 30 % Ladung, Temperatur unter 40 °C.
6. **Hardwarezugriff prüfen** bestätigen. Der Test schaltet den Eingang kurz aus,
   direkt wieder ein und liest beide Zustände zurück. Fehler lassen die Funktionen gesperrt.
7. Erweiterten Modus aktivieren, dann unter **Laden** Ladesteuerung und Wunschwerte speichern.

Das lokale Paket pinnt die exakten Codesignatur-Hashes von App und Helper.
Ein Neubau benötigt ein neues Paket und eine erneute Installation. Es gibt keine
Freigabe für beliebige unsignierte Programme. Ein Apple-Team-signierter Build
verwendet stattdessen den geprüften Team-/Bundle-Identifier-Pfad über SMAppService.
Dieser Distributionspfad ist auf dem lokalen Rechner noch nicht end-to-end geprüft.

## Rückkehr und Entfernen

Erweiterten Modus ausschalten oder Battune normal beenden: Netzteileingang und die
von Battune zuvor übernommene native Grenze werden wiederhergestellt. Die GUI
verändert dabei keine fremden nativen Einstellungen, wenn sie nicht mehr Eigentümer ist.

Zur vollständigen Entfernung des lokalen Helpers erst Steuerung deaktivieren und
App beenden, dann bewusst mit Administratorfreigabe ausführen:

```sh
sudo ./scripts/uninstall-local-helper.sh
```

Das Skript stoppt den Dienst, stellt den von Battune belegten Adapterzustand
wieder her und entfernt erst danach die festen Installationsdateien. Bei einem
Wiederherstellungsfehler bleiben Helper und Journal zur Reparatur erhalten.

Erfolgreich ausgeführt: privilegierte Installation, authentifizierte XPC-Verbindung
und realer CHIE-Aus-/Ein-Test mit Rücklesen und Wiederherstellung. Noch offen sind
physische Entlade-/Kalibrierungszyklen, Schlaf-/Crash-Wiederherstellung und Langzeittests.
Der erweiterte Modus bleibt nach diesem begrenzten Test ausgeschaltet.
