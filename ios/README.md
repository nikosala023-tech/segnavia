# Segnavia per iPhone (SwiftUI)

App nativa iOS 17+: SwiftData, MapKit con tessere OpenTopoMap e sentieri Waymarked Trails, Swift Charts, HealthKit.

## Compilare
1. Xcode 15 o più recente sul Mac.
2. `brew install xcodegen`
3. `cd ios && xcodegen generate && open Segnavia.xcodeproj`
4. In Xcode: target Segnavia → Signing & Capabilities → Team = il tuo Apple ID. Collega l'iPhone e premi Run.

Con un Apple ID gratuito l'app va reinstallata ogni 7 giorni. Con l'Apple Developer Program si distribuisce con TestFlight.
