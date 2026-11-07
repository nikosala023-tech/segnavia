# Segnavia

Diario dei trekking in montagna. Web app installabile (PWA), nessun server: i dati restano nel browser del telefono (IndexedDB), con backup JSON esportabile.

- Import GPX/TCX (Garmin, Strava, Komoot, Suunto…), anche più file insieme
- Import dall'export di Apple Salute (`esportazione.zip`, cartella `workout-routes`)
- Registrazione GPS dal vivo (app in primo piano)
- Mappa topografica OpenTopoMap + sentieri Waymarked Trails + satellite Esri
- Profilo altimetrico colorato per pendenza, collegato alla mappa
- Statistiche per mese/anno, record, scala di difficoltà CAI (T, E, EE, EEA)
- Condivisione: card immagine, GPX, testo. Foto per ogni uscita.

Pubblicazione: qualsiasi hosting statico HTTPS (GitHub Pages). Nessuna build: i file vanno serviti così come sono.
