# SplitShare

Offline Splitwise-Alternative für iPhone – Gruppen, Ausgaben und Salden werden **peer-to-peer per Bluetooth/WLAN-Direct** synchronisiert. Kein Internet, kein Server.

## Features

- **Gruppen erstellen** und Mitglieder verwalten
- **Ausgaben erfassen** mit gleichmäßiger, exakter oder prozentualer Aufteilung
- **Salden berechnen** inkl. vereinfachter Ausgleichsvorschläge
- **Bluetooth P2P-Sync** über Apples Multipeer Connectivity Framework
- **Komplett offline** – Daten bleiben lokal und werden nur zwischen verbundenen Geräten ausgetauscht

## Voraussetzungen

- macOS mit **Xcode 15+**
- Zwei oder mehr **physische iPhones** (Simulator unterstützt Multipeer Connectivity nicht zuverlässig)
- iOS **17.0+**
- Bluetooth eingeschaltet

## Installation

1. Repository klonen oder Ordner öffnen
2. `SplitShare/SplitShare.xcodeproj` in Xcode öffnen
3. Unter **Signing & Capabilities** dein Team auswählen
4. App auf dein iPhone deployen

## Nutzung

1. **Profil**: Anzeigename setzen
2. **Gruppe erstellen**: Tab „Gruppen“ → Plus
3. **Geräte verbinden**: Tab „In der Nähe“ – beide iPhones öffnen SplitShare und halten sie nah beieinander (automatische Verbindung)
4. **Einladen**: In der Gruppe → „Mitglied einladen“ → verbundenes Gerät wählen
5. **Ausgaben hinzufügen** und unter „Salden“ den Ausgleich prüfen

## Technik

| Komponente | Details |
|---|---|
| UI | SwiftUI |
| P2P | `MultipeerConnectivity` (Bluetooth + Wi-Fi Direct) |
| Service-Typ | `splitshare-p2p` |
| Speicher | JSON in Documents (Gruppen), UserDefaults (Profil) |
| Sync | JSON-Nachrichten (`SyncEnvelope`) mit Merge nach `updatedAt` |

### Sync-Protokoll

- Beim Verbinden: Profil + Gruppen-Snapshot austauschen
- Bei Änderungen: `groupUpdate` an alle verbundenen Peers
- Einladungen: `inviteToGroup` mit vollständiger Gruppe

## Berechtigungen

Die App fragt nach:

- **Bluetooth** – Geräteerkennung und Datentransfer
- **Lokales Netzwerk** – Multipeer-Discovery über Bonjour

## Hinweise

- Teste immer auf **echten Geräten**; der Simulator kann P2P nicht sinnvoll testen.
- Manuell hinzugefügte Mitglieder (ohne Bluetooth) werden nicht live synchronisiert.
- Bei Konflikten gewinnt der Datensatz mit dem neueren `updatedAt`-Zeitstempel; Ausgaben werden nach ID zusammengeführt.

## Projektstruktur

```
SplitShare/
├── SplitShare.xcodeproj
└── SplitShare/
    ├── Models/
    ├── Services/
    ├── Views/
    ├── Assets.xcassets
    └── Info.plist
```

## Lizenz

MIT
