# SplitShare

Offline Splitwise-Alternative für iPhone – Gruppen, Ausgaben und Salden werden **peer-to-peer per Bluetooth/WLAN-Direct** synchronisiert. Kein Internet, kein Server.

## Features

- **Gruppen erstellen** und Mitglieder per QR-Code einladen
- **Ausgaben erfassen** mit gleichmäßiger, exakter oder prozentualer Aufteilung
- **Salden berechnen** inkl. vereinfachter Ausgleichsvorschläge und Schulden pro Ausgabe
- **Bluetooth P2P-Sync** über Apples Multipeer Connectivity Framework – nur mit eingeladenen Mitgliedern
- **Komplett offline** – Daten bleiben lokal und werden nur zwischen verbundenen Geräten ausgetauscht

## Voraussetzungen

- macOS mit **Xcode 15+**
- Zwei oder mehr **physische iPhones** (Simulator unterstützt Multipeer Connectivity und den QR-Scanner nicht zuverlässig)
- iOS **17.0+**
- Bluetooth eingeschaltet
- Kamerazugriff für QR-Einladungen

## Installation

1. Repository klonen oder Ordner öffnen
2. `SplitShare.xcodeproj` im Repo-Root in Xcode öffnen
3. Unter **Signing & Capabilities** dein Team auswählen
4. App auf dein iPhone deployen

## Nutzung

1. **Profil**: Anzeigename setzen und den eigenen QR-Code bereithalten
2. **Gruppe erstellen**: Tab „Gruppen“ → Plus
3. **Einladen**: In der Gruppe → „Mitglied einladen“ → QR-Code der anderen Person scannen (oder den eigenen Code zeigen)
4. **Sync**: Tab „In der Nähe“ – eingeladene iPhones verbinden sich automatisch, sobald sie nah beieinander sind
5. **Ausgaben hinzufügen** und unter „Salden“ den Ausgleich prüfen

## Technik

| Komponente | Details |
|---|---|
| UI | SwiftUI |
| P2P | `MultipeerConnectivity` (Bluetooth + Wi-Fi Direct) |
| Einladung | QR-Code mit Profil-ID und Geräte-ID |
| Service-Typ | `splitshare-p2p` |
| Speicher | JSON in Documents (Gruppen), UserDefaults (Profil) |
| Sync | JSON-Nachrichten (`SyncEnvelope`), Union-Merge nach ID |

### Sync-Protokoll

- Einladung nur per QR: das gescannte Profil wird Mitglied, fremde Geräte in der Nähe sehen die Gruppe nicht
- Beim Verbinden: Profil + Snapshot **nur der gemeinsamen Gruppen**
- Bei Änderungen: `groupUpdate` an verbundene Gruppenmitglieder
- Parallele Ausgaben werden per ID zusammengeführt; gelöschte Ausgaben bleiben über Tombstones gelöscht

## Berechtigungen

Die App fragt nach:

- **Kamera** – QR-Code scannen, um jemanden einzuladen
- **Bluetooth** – Geräteerkennung und Datentransfer
- **Lokales Netzwerk** – Multipeer-Discovery über Bonjour

## Hinweise

- Teste immer auf **echten Geräten**; der Simulator kann P2P und den QR-Scanner nicht sinnvoll testen.
- Unbekannte SplitShare-Nutzer in Bluetooth-Reichweite erhalten keine Gruppendaten.
- Bei Konflikten werden Mitglieder und Ausgaben nach ID vereinigt; gelöschte Ausgaben kommen nicht zurück.

## Projektstruktur

```
.
├── SplitShare.xcodeproj
├── README.md
└── SplitShare/
    ├── Models/
    ├── Services/
    ├── Views/
    ├── Assets.xcassets
    └── Info.plist
```

## Lizenz

MIT
