# TrashSquad Android updater · Beer Party Studio

The game downloads the latest APK into its private `user://updates` directory,
checks the release SHA-256, saves progress and opens the Android installer.
Android 8+ asks once for permission to install updates from TrashSquad.
The player returns from that settings screen and installation continues.
The Android installation confirmation remains required.

The first APK containing this updater must be installed once through the existing
Firebase App Tester distribution. Existing APKs cannot acquire a native plugin
without installing that newer APK. Later updates need no browser or APK file manager.

The plugin only exposes APKs under the app's private `files/updates` directory.
It checks the APK package and version before handing it to Android; Android verifies
the installed app's signing certificate. Release builds must keep the existing key.

Build requirements: JDK 17, Gradle 8.10.2, Android SDK/build tools 34, Godot 4.4.1.
Run `gradle -p android-updater --no-daemon assembleRelease` to build the AAR.
The Android beta workflow installs `android_source.zip` into `source/android/build`,
copies the AAR into `libs/release` and `libs/debug`, exports and signs the game,
and publishes `android-version.json` with APK byte size and SHA-256.
Generated templates and APKs remain ignored by Git.

Checks:

- `tools/verify.sh` includes `source/test/app_updater_test.tscn`: integrity, cached
  APK reuse, connection failure, cancellation, battle pause and return from permissions.
- `source/test/update_popup.tscn` previews the direct-update offer on a phone layout.
- `python3 tools/android_version.py path/to/TrashSquad.apk VERSION_CODE` generates metadata.

Before distributing the signed beta, run an upgrade on an Android device with an
older APK signed by the same release key. Cover first-time permission, cancellation
of the system installer and preservation of the existing profile.
