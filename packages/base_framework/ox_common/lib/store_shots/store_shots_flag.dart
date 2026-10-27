/// Store screenshot mode, for the Google Play screenshots only.
///
/// Built with `--dart-define=STORE_SHOTS=true` (tool/store_shots/capture.sh),
/// the app signs in to a made-up account with made-up family chats and never
/// goes online. Every use sits behind `if (kStoreShots)`, so a normal build,
/// where this is false, compiles all of it away.
const bool kStoreShots = bool.fromEnvironment('STORE_SHOTS');
