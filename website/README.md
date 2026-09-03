# SplitShare Waitlist

One-Pager zur App-Ankündigung. Der Zähler zeigt live, wie viele gültige E-Mails auf der Waitlist stehen.

## Starten

```bash
python3 website/server.py
```

Danach im Browser: [http://127.0.0.1:8787](http://127.0.0.1:8787)

E-Mails werden lokal in `website/data/waitlist.json` gespeichert (nicht im Git). Der Tracker liest die Anzahl einzigartiger Adressen.
