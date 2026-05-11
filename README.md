# ColorCam

Flutter app for camera + YOLO color detection (phased build).

## Current Scope

- Firebase bootstrap is ready using free-tier services:
  - Firebase Authentication (email/password)
  - Cloud Firestore
- Auth UI includes:
  - Sign in
  - Sign up with full name, email, password, and password confirmation
- Home supports live camera detection with bounding-box overlays.
- Capture saves an annotated image to gallery and persists detected colors to Firestore.

## 1) Firebase Console Setup (Free Tier)

1. Create a Firebase project in the Firebase Console.
2. Enable **Authentication > Sign-in method > Email/Password**.
3. Create a **Cloud Firestore** database in production mode.
4. Do **not** enable Firebase Storage (you requested free Auth + Firestore only).

## 2) FlutterFire Setup

Install FlutterFire CLI if needed:

```powershell
dart pub global activate flutterfire_cli
```

From project root, run:

```powershell
flutterfire configure
```

This command will generate/replace `lib/firebase_options.dart` with real values for your Firebase project.

## 3) Add YOLO model asset

Place a YOLO TFLite model at:

```txt
assets/models/yolov5n.tflite
```

The live camera page expects this path by default.

## 4) Run the app

```powershell
flutter pub get
flutter run
```

## 5) Firestore Security Rules (starter)

Use these rules so each user can read/write only their own profile document in `users/{uid}`:

```txt
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
	match /users/{userId} {
	  allow read, write: if request.auth != null && request.auth.uid == userId;
	}
  }
}
```

## Notes

- `lib/firebase_options.dart` currently contains placeholders and must be replaced using `flutterfire configure` before running on a real device/emulator.
- If the model asset is missing, camera preview still opens but inference is disabled and a message is shown.
