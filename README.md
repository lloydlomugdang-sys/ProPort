# GradPort mobile app

GradPort is a Flutter Android/iOS client backed by the Fastify API in
[`backend/`](backend/README.md). Authentication uses short-lived access tokens
in memory and a rotating refresh token in platform secure storage.

---

## Quick First-Time Setup Checklist

Follow this checklist when setting up your development machine for the first time:

- [ ] Install Git
- [ ] Install Flutter SDK
- [ ] Install Android Studio / Android SDK
- [ ] Install Node.js LTS + npm
- [ ] Run `flutter doctor` (ensure Android toolchain is healthy)
- [ ] Clone the repository
- [ ] Run `flutter pub get`
- [ ] Run `npm ci` inside `backend/`
- [ ] Obtain development environment variables privately if needed
- [ ] Update `main` (`git pull origin main`)
- [ ] Create your own task branch (`git checkout -b feature/...`)
- [ ] Start coding
- [ ] Run tests (`flutter analyze`, `flutter test`, etc.)
- [ ] Push your branch (`git push -u origin feature/...`)
- [ ] Create a Pull Request on GitHub

---

## 1. Prerequisites / Required Software

Make sure your machine has the following tools installed:

1. **Git** – Version control system to clone and contribute code.
2. **Flutter SDK** – Framework used to build the GradPort mobile app.
3. **Android Studio** – Official IDE providing the Android SDK, Build-Tools, and Emulator.
4. **Android SDK & Command-line Tools** – Required by Flutter to compile and test Android apps.
5. **Code Editor** – **VS Code** (with the Flutter and Dart extensions) or **Android Studio**.
6. **Node.js LTS & npm** – Runtime and package manager for the Fastify backend in `backend/`.
   > [!NOTE]
   > `npm` comes bundled automatically when you install Node.js. You do not need to install `npm` separately.

---

## 2. Installation Guide (Windows)

### How to Install Git on Windows

1. Download the installer exclusively from the official website:
   - [https://git-scm.com/download/win](https://git-scm.com/download/win)
2. Run the Git for Windows installer.
3. The default settings selected during setup are generally fine for all options.
4. Once installation is finished, open PowerShell or Command Prompt and verify:
   ```powershell
   git --version
   ```

---

### How to Install Flutter SDK on Windows

1. Download the stable Flutter SDK exclusively from the official Flutter website:
   - [https://docs.flutter.dev/get-started/install/windows/mobile](https://docs.flutter.dev/get-started/install/windows/mobile)
2. Extract the downloaded zip file to a simple, dedicated directory such as:
   ```text
   C:\src\flutter
   ```
   > [!WARNING]
   > Do **not** install or extract Flutter inside Program Files or inside the GradPort project repository itself. Keep it in a separate folder like `C:\src\flutter`.
3. Add Flutter to your user environment variables:
   - Press the Windows Key and search for **Environment Variables**.
   - Select **Edit environment variables for your account**.
   - Under **User variables**, select `Path` and click **Edit**.
   - Click **New** and add the path:
     ```text
     C:\src\flutter\bin
     ```
   - Click **OK** to save and close all dialogs.
4. Close and reopen PowerShell, Command Prompt, or VS Code so the new PATH takes effect.
5. Verify the installation:
   ```powershell
   flutter --version
   flutter doctor
   ```

---

### Android Studio / Android SDK Setup

1. Download and install Android Studio from the official developer website:
   - [https://developer.android.com/studio](https://developer.android.com/studio)
2. During the setup wizard (or via **Settings > Languages & Frameworks > Android SDK**), ensure the following components are selected and installed:
   - **Android SDK**
   - **Android SDK Platform** (latest stable API level)
   - **Android SDK Build-Tools**
   - **Android SDK Command-line Tools (latest)** (under the **SDK Tools** tab)
   - **Android Virtual Device / Emulator** (optional, if you do not have a physical Android device)
3. Accept the Android licenses in your terminal:
   ```powershell
   flutter doctor --android-licenses
   ```
   Press `y` to accept each license agreement when prompted.
4. Re-run `flutter doctor` to confirm the Android toolchain has a green checkmark:
   ```powershell
   flutter doctor
   ```

#### Physical Android Device Setup (Recommended)
If you prefer testing on a real Android smartphone instead of an emulator:
1. On your Android phone, open **Settings > About Phone**.
2. Tap **Build Number** 7 times until you see the message "You are now a developer!".
3. Go back to **Settings > System > Developer Options** (or search for "Developer Options").
4. Enable **USB Debugging**.
5. Connect your phone to your PC with a USB cable.
6. A popup prompt will appear on your phone asking "Allow USB debugging?". Check "Always allow from this computer" and tap **Allow**.
7. In PowerShell, verify Flutter detects your device:
   ```powershell
   flutter devices
   ```

---

### How to Install Node.js and npm

1. Download the current **LTS (Long Term Support)** installer from the official website:
   - [https://nodejs.org](https://nodejs.org)
2. Run the installer using the standard recommended options.
3. `npm` is included automatically with the Node.js installation.
4. Open a new terminal window and verify:
   ```powershell
   node --version
   npm --version
   ```

---

## 3. Clone and Initialize the Project

### Clone the Repository

Open your terminal in the directory where you store your programming projects (for example, `C:\Projects` or `Documents`), then run:

```bash
git clone https://github.com/lloydlomugdang-sys/ProPort.git
cd ProPort
```

> [!NOTE]
> `git clone` automatically creates the `ProPort` folder for you. You do **not** need to create the folder manually first.

If you prefer to name your local project folder differently, you can specify a custom local folder name:

```bash
git clone https://github.com/lloydlomugdang-sys/ProPort.git gradport_app
cd gradport_app
```
The local folder name does not need to be identical for every team member.

---

### Install Flutter Dependencies

From the root directory of the cloned repository, run:

```powershell
flutter pub get
```

This command automatically downloads and installs all Flutter packages and dependencies specified in `pubspec.yaml` (such as Google Fonts, HTTP clients, image pickers, etc.). You do **not** need to install packages individually.

---

### Install Backend Dependencies

From the repository root, switch into the `backend/` directory and install the Node.js dependencies:

```powershell
cd backend
npm ci
cd ..
```

> [!NOTE]
> `npm ci` cleanly installs exact dependency versions from `package-lock.json`. If `npm ci` fails or is unavailable on your system, you can run `npm install` as a fallback:
> ```powershell
> npm install
> ```
> All backend dependencies—such as Fastify, TypeScript, Tesseract.js, MongoDB drivers, and Vitest—are installed automatically.

---

### Environment Variables / Secrets

To protect user data and systems, **secrets are never committed to GitHub**.
- If your task involves local backend development requiring environment variables (e.g. MongoDB URI, JWT secret, Cloudflare R2 bucket credentials, Brevo email keys, Gemini AI keys), obtain development values privately from the project maintainer.
- Never write, paste, or commit production credentials or actual secret keys into this `README.md`, source files, or Git history.

---

## 4. Running GradPort

### Check Available Devices

Before running the application, list all detected emulators, simulators, and connected physical devices:

```powershell
flutter devices
```

### Run the App

Start the app on your selected device:

```powershell
flutter run
```

### API_BASE_URL Configuration

`API_BASE_URL` is a compile-time build setting used by the mobile app to communicate with the backend.

1. **Android Emulator (Local Backend):**
   The Android emulator accesses the host computer's localhost via the special IP `10.0.2.2`:
   ```powershell
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
   ```

2. **iOS Simulator / Windows Desktop (Local Backend):**
   Uses standard loopback:
   ```powershell
   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
   ```

3. **Physical Android Device (Local Backend via LAN):**
   Find your computer's local network IP (e.g. via `ipconfig`) and specify:
   ```powershell
   flutter run --dart-define=API_BASE_URL=http://192.168.1.X:3000
   ```
   *(Ensure your phone and computer are connected to the same Wi-Fi network).*

4. **Deployed Production / Staging Backend:**
   Release builds reject loopback and plain HTTP URLs. They require an explicit `https://` endpoint:
   ```powershell
   flutter run --release --dart-define=API_BASE_URL=https://gradport-api.onrender.com
   ```

> [!CAUTION]
> Never place database credentials, JWT secrets, passwords, or provider API keys into `--dart-define` or inside Flutter client files.

---

## 5. How to Get / Install the GradPort Android APK

### Method A: Prebuilt APK from GitHub Releases
> [!NOTE]
> **No prebuilt APK release is currently provided.**
> Build the APK locally using the steps below.

---

### Method B: Build the APK Locally

You can generate the Android application package (APK) directly from your development machine.

#### 1. Build a Release APK (Production)
Release builds require a deployed HTTPS API URL and cannot use loopback addresses:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://gradport-api.onrender.com
```

The compiled release APK will be generated at:
```text
build\app\outputs\flutter-apk\app-release.apk
```

#### 2. Build a Debug APK (Local Testing)
For local testing on a physical phone connecting to your local development backend:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.X:3000
```

The debug APK will be generated at:
```text
build\app\outputs\flutter-apk\app-debug.apk
```

---

### Installing the APK on an Android Phone

#### Beginner Installation (Direct on Phone):
1. Locate the generated APK file on your PC (`build\app\outputs\flutter-apk\app-release.apk` or `app-debug.apk`).
2. Transfer the APK file to your phone (via USB cable, Google Drive, Bluetooth, or messaging app).
3. On your phone, open your **Files** or **File Manager** app and tap the APK file.
4. If Android displays a security warning saying "For your security, your phone is not allowed to install unknown apps from this source", tap **Settings** and toggle on **Allow from this source**.
5. Tap **Install** and wait for installation to complete.
6. Open **GradPort** from your app drawer.

#### Optional ADB Installation (Via Terminal):
If your Android phone is connected to your PC with USB Debugging enabled:

```powershell
adb install build\app\outputs\flutter-apk\app-release.apk
```

---

## 6. For Group Members: Clone and Contribute

Welcome to the GradPort project team! Follow this step-by-step guide to set up your working branch and contribute code safely.

### Quick Collaboration Flow

```
Branch ➔ Edit ➔ Test ➔ Commit ➔ Push Branch ➔ Pull Request ➔ Review ➔ Merge
```

---

### Step 1: Always Update `main` Before Starting

Before starting any new work, make sure your local `main` branch is completely up to date with GitHub:

```bash
git checkout main
git pull origin main
```

> [!IMPORTANT]
> **DO NOT work directly on `main`.**
> Group members must **never** commit or push directly to `main`. Always create a dedicated branch for your task.

---

### Step 2: Create a Separate Branch for Each Task

Create and switch to a new branch specifically for your assigned task:

```bash
git checkout -b feature/your-name-task
```

**Branch naming examples:**
- `feature/maria-dashboard`
- `feature/juan-document-upload`
- `fix/anna-login-error`
- `polish/mark-profile-ui`

---

### Step 3: Verify Your Active Branch Before Editing

Always verify that you are on your task branch (and **not** on `main`) before touching any code:

```bash
git branch --show-current
git status
```

Check that the output displays your feature or fix branch name.

---

### Step 4: Make Changes and Run Checks

Make your code modifications. Before committing, always run the appropriate analyzer and test commands to ensure nothing is broken.

**For Flutter (Mobile App) changes:**
```bash
flutter analyze
flutter test
```

**For Backend changes:**
```bash
cd backend
npm run typecheck
npm run lint
npm test
npm run build
cd ..
```

Resolve any lint errors, compiler issues, or broken tests before moving to the next step.

---

### Step 5: Commit Your Changes

Stage your modified files and write a clear, descriptive commit message:

```bash
git add .
git commit -m "feat: describe your changes"
```

---

### Step 6: Push YOUR Branch (Never `main`)

Push your task branch to GitHub:

```bash
git push -u origin feature/your-name-task
```

> [!CAUTION]
> Always verify the branch name in your push command. Push **your branch**, never `main`.

---

### Step 7: Create a Pull Request (PR) on GitHub

1. Go to the repository on GitHub: [https://github.com/lloydlomugdang-sys/ProPort](https://github.com/lloydlomugdang-sys/ProPort)
2. Click **Compare & pull request** next to your recently pushed branch.
3. Verify the branches:
   - **base**: `main`
   - **compare**: `feature/your-name-task`
4. Add a clear title and description explaining what changes were made.
5. Click **Create pull request**.

---

### Step 8: Code Review and Merge

- **Changes must be reviewed before merging.** Notify your teammates or group lead to review your PR.
- If changes or fixes are requested, make the edits on your local branch, test them, commit, and push again. The open PR will update automatically.
- Once reviewed and approved, the branch will be merged into `main`.

---

### Starting a New Task

Whenever you start working on another feature or bug fix, return to `main`, pull the latest merged updates, and create a brand-new branch:

```bash
git checkout main
git pull origin main
git checkout -b feature/your-name-new-task
```

---

### If `main` Changed While You Were Working

If another team member merged code into `main` while you were working on your branch, update your branch with the latest changes from `main`:

```bash
git checkout main
git pull origin main
git checkout feature/your-name-task
git merge main
```

Resolve any merge conflicts if they arise, run your tests again, and push your updated branch.

---

### ⚠️ Security Rules (Never Commit Secrets)

> [!WARNING]
> **Never commit sensitive credentials, keys, or private environment files to Git or GitHub.**
>
> Always verify `git status` and `git diff` to make sure you do **not** stage or commit:
> - `.env` or local environment configuration files
> - API keys (such as Gemini API keys)
> - MongoDB connection strings or database credentials
> - JWT secrets and signing keys
> - Cloudflare R2 access keys, secret keys, or bucket credentials
> - Brevo or SMTP email-sender credentials
> - Passwords, OTP codes, or private authorization tokens

---

### ⚠️ Avoid Destructive Git Commands

> [!CAUTION]
> **Do NOT use destructive Git commands casually:**
> ```bash
> git reset --hard
> git clean -fd
> git restore .
> ```
> These commands will **permanently delete** your uncommitted changes and cannot be undone. If you get stuck or run into Git errors, ask your teammates or project lead for guidance before attempting hard resets.

---

## 7. Verification & Testing

Run the full verification suite to confirm the client and backend remain sound:

```powershell
flutter analyze
flutter test test/api_client_test.dart test/auth_service_test.dart test/widget_test.dart
flutter test test/api_client_smoke_test.dart -r expanded
```

> [!NOTE]
> `test/api_client_smoke_test.dart` intentionally tests live network calls against a running local backend server. Backend commands, disposable-database safeguards, and auth/deployment details are documented in [`backend/README.md`](backend/README.md).

---

## 8. Deployment Boundary

Android and iOS are the production targets. A deployed HTTPS backend,
production SMTP/provider configuration, final application/bundle identifiers, Android
signing and AAB preparation, and App Store/TestFlight signing and metadata are
separate deployment tasks. The current API contract and token/email
abstractions are designed so those tasks do not require redesigning the auth
flow.

---

## 9. Quick Command Reference

| Task | Command | Notes |
|---|---|---|
| **Clone repo** | `git clone https://github.com/lloydlomugdang-sys/ProPort.git` | Run once |
| **Check Flutter health** | `flutter doctor` | Verifies SDK & Android toolchain |
| **Install Flutter packages** | `flutter pub get` | From repository root |
| **Install backend packages** | `cd backend && npm ci && cd ..` | From repository root |
| **List target devices** | `flutter devices` | Shows emulators and USB phones |
| **Run app (Emulator)** | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` | Host loopback on Android |
| **Run app (iOS / Desktop)** | `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000` | Localhost loopback |
| **Analyze Flutter code** | `flutter analyze` | 0 issues target |
| **Run Flutter tests** | `flutter test` | Offline unit & widget tests |
| **Test backend** | `cd backend && npm test && cd ..` | Vitest test suite |
| **Build release APK** | `flutter build apk --release --dart-define=API_BASE_URL=https://gradport-api.onrender.com` | Output in `build/app/outputs/flutter-apk/` |
| **Build debug APK** | `flutter build apk --debug --dart-define=API_BASE_URL=http://...` | For local network phone testing |
| **Check active branch** | `git branch --show-current` | Verify before editing |
| **Create new task branch** | `git checkout -b feature/your-name-task` | Never work directly on `main` |
| **Update main** | `git checkout main && git pull origin main` | Run before creating a new branch |
| **Push task branch** | `git push -u origin feature/your-name-task` | Push your branch, never `main` |
| **Sync main into branch** | `git merge main` | Run while on your task branch |
