# SplitShare

<img src="SplitShare/Assets.xcassets/Logo.imageset/Logo.png" alt="SplitShare Logo" width="96" height="96" />

Gemeinsame Ausgaben auf dem iPhone — **muss nie online sein**. Gruppen, Rechnungen und Salden bleiben lokal und wandern per Bluetooth/WLAN-Direct von Gerät zu Gerät. Keine Cloud, kein Account, kein Server.

## Features

- **Gruppen** anlegen; der Ersteller ist Admin
- **Mitglieder per QR-Code einladen** — unbekannte Geräte in der Nähe sehen die Gruppe nicht
- **Ausgaben erfassen, bearbeiten und löschen** mit gleichmäßiger, exakter oder prozentualer Aufteilung
- **Salden** mit vereinfachten Ausgleichsvorschlägen oder Schulden pro Ausgabe
- **Schulden als bezahlt markieren** — erzeugt eine Ausgleichs-Ausgabe
- **Gruppe verlassen** (Archiv auf dem eigenen Gerät); Admins übergeben die Rolle vorher
- **Gruppe für alle löschen** — nur Admin, und nur wenn alle Salden ausgeglichen sind
- **Bluetooth-P2P-Sync** über Apples Multipeer Connectivity — nur mit eingeladenen Mitgliedern
- **Komplett offline** — Daten liegen in JSON auf dem Gerät; Sessions sind verschlüsselt

## Voraussetzungen

- macOS mit **Xcode 15+**
- Zwei oder mehr **physische iPhones** (Simulator unterstützt Multipeer Connectivity und den QR-Scanner nicht zuverlässig)
- iOS **17.0+**
- Bluetooth eingeschaltet
- Kamerazugriff für QR-Einladungen

## Installation

1. Repository klonen
2. `SplitShare.xcodeproj` im Repo-Root in Xcode öffnen
3. Unter **Signing & Capabilities** dein Team auswählen
4. App auf dein iPhone deployen

Bundle-ID: `com.maxseidlitz.splitshare`

## Nutzung

1. **Profil**: Anzeigename setzen — dein QR-Code liegt auf demselben Tab
2. **Gruppe erstellen**: Tab „Gruppen“ → Plus
3. **Einladen**: In der Gruppe → Menü → „Mitglied einladen“ → QR-Code der anderen Person scannen (oder den eigenen Code zeigen)
4. **Sync**: Tab „In der Nähe“ — eingeladene iPhones verbinden sich, sobald sie nah beieinander sind
5. **Ausgaben** hinzufügen oder wischen zum Bearbeiten/Löschen
6. **Salden** prüfen, optional eigene Schulden als bezahlt markieren
7. **Verlassen** legt die Gruppe ins Archiv; der Admin kann sie für alle löschen, wenn nichts mehr offen ist

## Technik

| Komponente | Details |
|---|---|
| UI | SwiftUI, Portrait, iOS 17+ |
| P2P | `MultipeerConnectivity` (Bluetooth + Wi-Fi Direct), `encryptionPreference: .required` |
| Einladung | QR-Code `splitshare:{json}` mit Profil-ID, Geräte-ID und Anzeigename |
| Service-Typ | `splitshare-p2p` (`_splitshare-p2p._tcp` / `._udp`) |
| Speicher | JSON in Documents (`groups.json`), UserDefaults (Profil, Geräte-ID, Peer-ID) |
| Sync | JSON-Nachrichten (`SyncEnvelope`), Union-Merge nach ID |

### Sync-Protokoll

Nachrichten: `profile`, `groupSnapshot`, `groupUpdate`, `inviteToGroup`, `requestSync`, `groupDeleted`

- Einladung nur per QR: das gescannte Profil wird Mitglied; fremde Geräte in der Nähe erhalten keine Gruppendaten
- Beim Verbinden: Profil plus Snapshot **nur der gemeinsamen, nicht archivierten Gruppen**
- Bei Änderungen: `groupUpdate` an verbundene Gruppenmitglieder
- Parallele Ausgaben werden per ID zusammengeführt; gelöschte Ausgaben bleiben über Tombstones gelöscht
- Austritte laufen über `leftMemberIds`; gelöschte Gruppen kommen über `groupDeleted` nicht zurück

## Berechtigungen

Die App fragt nach:

- **Kamera** — QR-Code scannen, um jemanden einzuladen
- **Bluetooth** — Geräteerkennung und Datentransfer
- **Lokales Netzwerk** — Multipeer-Discovery über Bonjour

## Waitlist-Website

Unter `website/` liegt die Landingpage mit Live-Zähler. Lokal starten:

```bash
python3 website/server.py
```

Danach: [http://127.0.0.1:8787](http://127.0.0.1:8787)

E-Mails landen in `website/data/waitlist.json` (nicht im Git). Details: [`website/README.md`](website/README.md)

## Hinweise

- Teste immer auf **echten Geräten**; der Simulator kann P2P und den QR-Scanner nicht sinnvoll testen.
- Unbekannte SplitShare-Nutzer in Bluetooth-Reichweite erhalten keine Gruppendaten.
- Verlassen ist blockiert, solange du noch Schulden hast; Löschen für alle ist blockiert, solange Salden offen sind.
- Archivierte Gruppen sind nur noch lokal lesbar und werden nicht mehr synchronisiert.

## Projektstruktur

```
.
├── SplitShare.xcodeproj
├── README.md
├── SplitShare/
│   ├── SplitShareApp.swift
│   ├── Info.plist
│   ├── Models/
│   ├── Services/          # GroupStore, Multipeer, QR, Salden
│   ├── Views/
│   └── Assets.xcassets
└── website/               # Waitlist-Landingpage
    ├── index.html
    ├── server.py
    ├── css/  js/  assets/
    └── README.md
```

