# Edushelf

**A mobile reading application for digitalized learning materials and syllabus management.**

Students read and download learning materials and syllabi (online or offline). Faculty upload materials and follow their students' reading activity. The admin manages accounts and approves materials. Syllabi are open to every student.

📘 **Manuals:** [User Manual](docs/Edushelf_User_Manual.docx) (students, faculty, admin) · [Installation Manual](docs/Edushelf_Installation_Manual.docx) (installing, updating, server and email setup, building releases)

Built with **Flutter (Dart)** and a **Supabase (PostgreSQL)** backend.

---

## Contents

1. [Quick start: install the app](#1-quick-start-install-the-app)
2. [Accounts and roles](#2-accounts-and-roles)
3. [What each role can do](#3-what-each-role-can-do)
4. [User testing guide](#4-user-testing-guide)
5. [For developers: setup and build](#5-for-developers-setup-and-build) (includes [using a groupmate's laptop](#using-a-groupmates-laptop))
6. [Supabase (backend)](#6-supabase-backend)
7. [Project structure](#7-project-structure)
8. [Troubleshooting](#8-troubleshooting)
9. [Known limitations](#9-known-limitations)

---

## 1. Quick start: install the app

The ready-to-install Android app is **`release/Edushelf.apk`** (about 56 MB).

**On an Android phone**

1. Send `Edushelf.apk` to the phone (Google Drive, Messenger as a file, USB cable, etc.). If a chat app blocks `.apk` files, zip it first or use Drive.
2. Open the file on the phone. When Android asks, allow **"Install unknown apps"** for the app you opened it from (Chrome, Files, Messenger…).
3. If **Google Play Protect** warns that the app is unrecognized, tap **More details → Install anyway**. (It warns because the app isn't from the Play Store.)
4. Open **Edushelf** and log in.

Installing a newer APK over an older one keeps the app's data (downloads, bookmarks).

**From a laptop over USB** (if Flutter is installed, see section 5): turn on *USB debugging* on the phone, plug it in, and run `flutter install` in the project folder.

**On a Windows laptop (no phone needed):** use **`release/Edushelf-Windows.zip`** (about 15 MB).
1. Right-click the zip → **Extract All…** (don't run it from inside the zip).
2. Open the extracted **Edushelf-Windows** folder and double-click **`Edushelf.exe`**.
3. If Windows SmartScreen says *"Windows protected your PC"*, click **More info → Run anyway**.

Keep all the files in that folder together; the `.exe` needs them. Downloaded materials are saved in *Documents\edushelf*. On Windows, "Send to contact" opens the email app (not SMS), and sharing/printing use Windows' own dialogs.

**Android emulator:** start one in Android Studio (*Device Manager → ▶*) and drag `Edushelf.apk` onto the emulator window.

The phone needs **internet** to log in the first time and to browse materials. Downloaded materials can be read offline.

---

## 2. Accounts and roles

There is **no public sign-up**. The **admin creates every account** (one at a time, or many at once from a CSV file) and gives the user their login details.

The **ID number decides the role and department** automatically:

| Role | ID format | Example |
|---|---|---|
| Student | `DD-YY-NNNNN` | `IT-23-01003` |
| Faculty | `DD-T-NNNNN` | `IT-T-00001` |
| Admin | `ADMIN-NNNN` | `ADMIN-0001` |

`DD` = department: **IT** (BSIT), **BA** (BSBA), **AC** (BSA), **OA** (BSOA).

- New accounts get a **temporary password**. Users go straight to their home page and can change it any time in **Settings** (recommended).
- **Admins have a permanent recovery password ("master key"):** an admin account's **first password** never expires. If an admin forgets their current password, they just **log in with the recovery password**; no request needed. It keeps working even after they change their everyday password in Settings.
- **One device at a time:** an account can be signed in on only one device. A second device is refused ("already signed in on a Windows computer…") until the first one logs out, or has had the app closed for 10 minutes. The admin can free an account in **Users → Edit (pencil) → Sign out of device**, e.g. for a lost phone.
- **Forgot password?** (students and faculty) on the login screen sends a request to the admin. The admin resets it (Users → Password Requests) and gives the user a new temporary password.
- Anyone can change their password later in **Settings / Profile → Change Password**.

> 🔒 **The admin password is not written here on purpose.** Ask the project leader for it. Never post passwords in group chats.

---

## 3. What each role can do

These follow the system flowcharts.

### Student
Tabs: **Browse · Updates · My Library · History · Settings**

- **Browse:** search and view materials of your department (needs internet). Filter by year level.
- **Download:** the whole material, or **single pages** (download icon on each page). Progress, size and time left show in the **Download Queue**.
- **Syllabus (curriculum outline):** open to everyone, no permission needed, e.g. to plan subjects or advance one during enrollment. It shows the program's courses as **tables by year and semester** (code, title, units, totals) with **search** by code or title (e.g. `IT 323`) and bigger/smaller text. Read online only, no download. (Older syllabi uploaded as PDF files open as readable text.)
- **My Library:** everything you downloaded, plus materials saved with the ♥ heart. Works **offline**.
- **Reader:** **3D flipbook** (swipe or tap the sides to turn pages) or **continuous vertical scroll** (pinch-zoom on phones; mouse wheel / scrollbar on Windows). **Bookmark** pages; "Resume from page X" continues where you stopped.
- **Read pages (✔):** a page gets a check mark only when you actually open it, so skipping ahead doesn't mark the pages in between. Reading progress = pages read ÷ total pages.
- **Delete downloads** (⋮ menu on a material) asks first, then removes the files **and resets that material's progress and bookmarks**, so a new download starts fresh.
- **History:** recently opened and downloaded materials.
- **Settings:** change password, **notifications** (e.g. *Access Granted*), download queue, log out.

### Faculty
Tabs: **Upload · Notifications · Dashboard · Activity · Profile**

- **Upload (learning material):** pick a PDF, fill in the details, and submit. The app checks the file first (real PDF, max 50 MB, title, subject code like `IT 201`) and lists anything to fix.
- **Upload (syllabus):** a syllabus is entered as **content, not a file**. Choose *Syllabus → Create Syllabus*, then fill the courses (code, title, units) for each year and semester, or tap **Fill from PDF** to read them from a curriculum outline PDF and check them. Only the content is saved. It goes to the admin for approval.
- **Notifications:** admin approvals, and revision notes for materials sent back.
- **Dashboard:** upload statistics and recent uploads (with the admin's revision notes).
- **Activity:** pick a student → **reading progress**, **bookmarked pages**, **accessed materials**.
- **Profile:** change password, log out.

### Admin
Tabs on the **left side**: **Homepage · Users · Materials · Activity · Settings** (icons only on phones; hover or look at the title bar to see which tab is open).

- **Homepage:** a greeting, live totals (tap a card to jump to that tab), the **four department logos** (BSIT, BSA, BSBA, BSOA), **Waiting for review** and **Recent activity**.
- **Department (tap a logo):** the department's totals and five folders:
  - **Students**, grouped by batch (from the ID: `IT-23-…` → Batch 2023).
  - **Faculty**; tap one to see everything they uploaded, grouped by year level.
  - **Syllabus**, with each one's status.
  - **Reading Materials**, one folder per faculty member who uploaded them, then grouped by year level. Tap a material to preview it.
  - **Activity Logs** for that department only.
- **Activity:** everything students do (open, read, stop, bookmark, download), live. **Recent** shows a feed; **By student** shows each student's progress, bookmarks and accessed materials. Filter by department and search by name, ID or material.
- **Users:** **Create Account** (optional email, so the login details can be emailed right away), **Import CSV** (many accounts at once, then print login slips or export a CSV), **edit / reset password**, **delete**, **Password Requests**.
- **Materials:** two lists, **Pending · Approved**.
  - *Pending:* **Approve**, or **Revise** with notes (both notify the faculty member). Either way the material leaves Pending right away; revised ones go back to the faculty member.
  - *Approved:* visible to students.
  - Every material has a 👁 **Preview** button (PDFs open in the reader, syllabi as course tables; previewing doesn't count as reading) and a 🗑 **Delete** button, which asks first and then deletes the material and its file for good.
- **Notifications (all users):** **Clear all** at the top of the list, or swipe one notification left/right to clear just that one.
- **Settings:** change your password, open Activity Logs, system info.

---

## 4. User testing guide

### 4.1 Before testing day
- [ ] Install `release/Edushelf.apk` on every phone you'll use and log in once.
- [ ] Make sure at least one **approved learning material** and one **approved syllabus** exist in each department you'll test (upload as faculty, approve as admin).
- [ ] Prepare **tester accounts** (next section).
- [ ] Prepare the **feedback form** (section 4.5).
- [ ] Bring a charger and check that the venue has Wi-Fi or mobile data.

### 4.2 Creating tester accounts quickly
Testers need IDs in the right format. For people who aren't real students, use made-up IDs that won't clash with real ones, e.g. `IT-26-90001`, `IT-26-90002`, `IT-T-90001`.

1. Make a spreadsheet with the columns **ID Number**, **Full Name** and (optional) **Email**, and save it as **CSV** (Excel: *File → Save As → CSV*). Tip: *Users → Import CSV → Get template* gives an example file.
2. As admin: **Users → Import CSV → Choose CSV file → Create N accounts**.
3. Tap **Print login slips**, or tap the ✉ button next to an account to **email its login details** (only for rows that had an email). You get a PDF with 8 cut-out slips per page (name, ID, temporary password). Print it, cut it, and give one slip to each tester.
4. Testers set their own password on first login.

After testing, delete the tester accounts in **Users** (🗑).

### 4.3 Test scenarios
Give each tester the scenario for their role. Watch, but don't help unless they're stuck; where they get stuck is useful feedback. Tick ✅ or ❌ and write down what happened.

**Student**
| # | Task | Expected result |
|---|---|---|
| S1 | Log in with the slip | Goes straight to My Library; then change the password in Settings |
| S2 | Browse: search for a material by code or title | Material is found |
| S3 | Open it and read with the **flipbook**; switch to **vertical scroll** (on phone **and** Windows) | Pages turn / scroll smoothly, no gray screen |
| S3b | Tap **page 32** in the page list, go back; then open **page 31** and turn to 32 | Only 32 checked, then only 31 and 32 |
| S3c | Read a downloaded material, bookmark a page, then **⋮ → Delete downloads** and download again | Progress 0%, no check marks, no bookmarks |
| S4 | **Bookmark** a page, close the reader, open it again | Bookmark kept, "Resume from page X" |
| S5 | **Download the whole material**; check the **Download Queue** | Progress bar, then it appears in My Library |
| S6 | Download **one page** only | Page shows a green check |
| S7 | Turn on **airplane mode**, open My Library and read the download | Works offline |
| S8 | Open a **syllabus** | Courses in tables by year/semester with unit totals, no permission asked |
| S9 | In the syllabus: **search** a course code (e.g. `IT 323`) | Only matching courses show, highlighted |
| S10 | Change password in Settings, log out, log in with the new one | Works |
| S11 | Log out, tap **Forgot password?**, send a request | "Request sent" |

**Faculty**
| # | Task | Expected result |
|---|---|---|
| F1 | Upload a PDF with an **empty title** or a non-PDF | "Revise File Credentials" lists the problems |
| F2 | Upload a correct PDF | Success screen → Dashboard |
| F2b | Upload → **Syllabus → Create Syllabus → Fill from PDF** (use a curriculum outline PDF), check the tables, submit | All courses filled in; admin gets *New Syllabus to Review* |
| F3 | After the admin sends it back: read the revision notes | Shown in Notifications and on the Dashboard |
| F4 | Activity → pick a student who read your material | Reading progress, bookmarks, accessed materials |
| F5 | Change password in Profile | Works |

**Admin**
| # | Task | Expected result |
|---|---|---|
| A1 | Create one account; try the same ID again | Second try shows "already has an account" |
| A2 | Approve one material and **Revise** another with notes | Both leave Pending at once; faculty member is notified |
| A2b | Tap 👁 **Preview** on a PDF material and on a syllabus | PDF opens in the reader; syllabus as tables |
| A2c | 🗑 **Delete** a test material (Cancel once, then Delete) | Stays after Cancel; gone from Browse after Delete |
| N1 | Any user: open Notifications, swipe one away, then **Clear all** | The list empties and stays empty after reopening |
| A3 | Approve a material: check a student's **Settings → Notifications** | *New Material Available* |
| A5b | Homepage → tap the **BSIT** logo, open each folder (Students, Faculty, Syllabus, Reading Materials → a faculty folder) | Users by batch; materials grouped by uploader and year level |
| A5c | Have a student read a material, then open **Activity** (Recent and By student) | The student's opens/pages/bookmarks appear within seconds |
| A4 | Users → Password Requests: reset a password and give it to the user | User logs in with it, then can change it in Settings |
| A5 | Delete a test account (then Cancel on another) | Deleted / not deleted |

### 4.4 Reporting a bug
Write down:
- **Phone model** and Android version
- **Account role** (student / faculty / admin)
- **What you did** (step by step)
- **What you expected** vs. **what happened**
- A **screenshot** or screen recording if possible

### 4.5 Feedback form (suggested questions)
Make a Google Form with these. Questions 1–8 use a scale from **1 (strongly disagree) to 5 (strongly agree)**.

1. The app was easy to learn.
2. I could find the materials I needed.
3. Reading with the flipbook felt natural.
4. Downloading materials and reading offline worked well.
5. Reading a syllabus as text was clear and easy.
6. The app looks clean and is pleasant to use.
7. The app responded quickly.
8. I would use Edushelf for my classes.
9. What did you like most?
10. What was confusing or didn't work?
11. What would you add or change?
12. Role (student / faculty / admin), department, phone model.

---

## 5. For developers: setup and build

### Requirements
| Tool | Version used |
|---|---|
| Flutter SDK | 3.47.2 (Dart 3.13.2) |
| Android Studio | with Android SDK 36 (for building the APK and the emulator) |
| VS Code | with the Flutter and Dart extensions |

Check with `flutter doctor`. Run `flutter doctor --android-licenses` once and accept everything.

> If `flutter` is "not recognized" in the terminal, add Flutter's `bin` folder (e.g. `C:\Users\<you>\flutter\bin`) to your **Path** environment variable and restart VS Code.

### Copying the project to another computer
Copy the whole folder **except** `build/` (about 2.5 GB) and `.dart_tool/`. They're generated again automatically. The APK is already in `release/`.

### Using a groupmate's laptop
What the laptop needs depends on what you'll do with it:

| Task | What the laptop needs |
|---|---|
| **Open the Supabase dashboard** (check data, run SQL, change settings) | Only a **web browser** and a Supabase login that was **invited to the project** (*Supabase → Organization → Team → Invite*; do this before testing day) |
| **Install the APK on phones** | Nothing: send `release/Edushelf.apk` to the phones directly |
| **Show the app on the laptop / projector** | Nothing extra: extract `release/Edushelf-Windows.zip` and run `Edushelf.exe` (or use an Android emulator) |
| **Change code / rebuild the APK** | Flutter SDK + Android Studio + VS Code (requirements above), then `flutter pub get` and `flutter build apk --release` |

**Set this up the day before**, not at school: installing Flutter and Android Studio downloads several GB.

The team's signing key (`android/app/edushelf-debug.keystore`) is **not in the public repository**. Get it from the project owner privately and put it in `android/app/`. With it, an APK built on any laptop installs over the existing app on the phones, with no uninstalling and no lost downloads. Without it, the build still works, but phones must uninstall the old app first. Never upload the key anywhere public.

**Ready-made APK and Windows app:** download them from the repository's **Releases** page on GitHub.

### Run and build
```bash
flutter pub get                 # download packages (first time)
flutter run                     # run on a connected phone / emulator (live reload)
flutter run -d edge             # run the web version in Microsoft Edge
flutter build apk --release     # build the APK -> build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release # build the Windows app -> build/windows/x64/runner/Release/
                                # (needs Visual Studio with "Desktop development with C++")
flutter install                 # install the built APK on a connected phone
```

After building a new APK, copy it into `release/Edushelf.apk` so it's easy to share.

For a new Windows build, copy `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll` (from *Visual Studio\…\VC\Redist\MSVC\<version>\x64\Microsoft.VC14x.CRT*) into the `Release` folder, rename the `.exe` to `Edushelf.exe`, and zip the folder. This lets it run on laptops without Visual Studio.

### Tests
```bash
flutter test       # 55 automated tests (unit + widget tests)
flutter analyze    # static analysis / lint
```

### Main packages
`supabase_flutter` (backend) · `pdfx` (PDF rendering) · `http` (downloads with progress) · `path_provider` + `shared_preferences` (offline library) · `crypto` (offline-login hash) · `connectivity_plus` (online/offline) · `file_picker` (PDF/CSV picking) · `share_plus`, `pdf`, `printing`, `url_launcher` (sharing/printing login details) · `syncfusion_flutter_pdf` (reading a syllabus's text).

> `syncfusion_flutter_pdf` is free under the **Syncfusion Community License** (students, individuals and organizations with under US$1 million revenue). If the app is ever used commercially, check syncfusion.com/products/communitylicense.

---

## 6. Supabase (backend)

- **Project URL:** `https://ypseyqamygvmhvboieom.supabase.co`. The app's connection settings are in `lib/main.dart`. The *publishable* key there is meant to be in the app; it can only do what the database rules allow.
- **Dashboard access:** ask the project leader to invite you (*Supabase → Organization → Team*). Don't share the account password.

### Database changes (SQL migrations)
All database changes are in `supabase/migrations/`, and **all of them have already been run** on the project. Only run them, **in this order**, if you ever set up a **new** Supabase project (*SQL Editor → New query → paste → Run*):

| File | What it does |
|---|---|
| `20261014000000_move_to_supabase_auth.sql` | Moves login to Supabase Auth; row-level security on users |
| `20261019000000_admin_managed_accounts.sql` | Admin creates and edits accounts |
| `20261020000000_account_and_password_requests.sql` | Password-reset requests, rate limiting, bulk import, first-login password change |
| `20261021000000_admin_temp_passwords_for_requests.sql` | Temporary passwords for resets; contact on file |
| `20261022000000_follow_flowcharts.sql` | Matches the flowcharts: revision notes for materials (its syllabus-permission columns are no longer used) |
| `20261023000000_admin_recovery_password.sql` | Admin recovery password ("master key") |
| `20261024000000_password_request_alerts.sql` | Alerts admins about new forgot-password requests |
| `20261025000000_email_notifications.sql` | Emails every notification to users with an email on file (Brevo) |
| `20261026000000_realtime_tables.sql` | Turns on live updates for every table the app watches |
| `20261027000000_lock_down_tables.sql` | Row Level Security for materials, notifications, permissions and activity logs |
| `20261028000000_syllabus_content.sql` | Stores syllabi as content (courses by semester) instead of files |
| `20261030000000_remove_material_archive.sql` | Removes the archive feature again (archived materials go back to Approved) |
| `20261031000000_one_device_per_account.sql` | One device per account: a second device can't sign in while the first is in use |

### Email notifications (Brevo, free: 300 emails/day)
Every in-app notification is also emailed to the user, if their **contact on file is an email** (set it in *Create Account*, the CSV *Email* column, or *Edit Account*). To turn it on:
1. Create a free account at **brevo.com**.
2. **Senders, Domains & Dedicated IPs → Senders → Add a sender**: use a Gmail address you own and confirm it from your inbox.
3. **SMTP & API → API Keys → Generate a new API key**, then copy it.
4. In Supabase's **SQL Editor**, run (with your own values; don't save these anywhere else):
   ```sql
   select vault.create_secret('xkeysib-YOUR-KEY', 'brevo_api_key');
   select vault.create_secret('your.sender@gmail.com', 'brevo_sender_email');
   ```
5. Check what was sent: `select * from public.email_log order by created_at desc;`

Emails from a Gmail sender may land in **Spam** at first; ask testers to check there and mark them "Not spam". Temporary passwords are **not** sent this way; the admin sends them with **Send to…** (their own mail app).

### Required dashboard settings
*Authentication → Sign In / Providers*:
- **Allow new users to sign up: OFF** (accounts come from the admin)
- **Confirm email: OFF** (login IDs map to internal addresses like `it-23-01003@edushelf.app` that have no real inbox)

⚠️ **Don't create or edit users on Supabase's Authentication page.** Always use the app's admin **Users** tab, so the profile, role and login stay linked.

---

## 7. Project structure

```
lib/
  main.dart                     App start, Supabase connection
  models/                       LearningMaterial, UserSession (ID → role/department)
  services/                     Talking to Supabase and the phone
    auth_service.dart             Login, offline login, change password, reset requests
    admin_service.dart            Create/edit accounts, CSV bulk import, password requests
    syllabus_text.dart            Reads text lines from a PDF (syllabus text, Fill from PDF)
    library_service.dart          My Library, History, bookmarks, progress (on the phone)
    download_service.dart         Download queue (whole document / single pages)
    upload_service.dart           Faculty uploads + file checks
    activity_service.dart         Reading activity logs (faculty and admin)
    credential_slips.dart         Printable login-slip PDF
  screen/
    login_screen.dart, forgot_password_screen.dart
    student/                    Student home (tabs), download queue
    teachers/                   Faculty tabs: upload, notifications, dashboard, activity logs
    admin/                      Admin dashboard, department folders, activity logs, account dialogs, CSV import, password requests
  models/department.dart        The four departments and their logos (assets/logos/)
    book_pages_directory_screen.dart   Learning material details + pages list
    syllabus_screen.dart               Syllabus: course tables (or text for old PDF ones)
    teachers/syllabus_editor_screen.dart  Faculty syllabus editor + Fill from PDF
    physical_flipbook_reader.dart      Reader (flipbook / vertical scroll)
  widgets/                      Reusable pieces (flipbook, book card, forms, dialogs)
supabase/migrations/            Database changes (SQL)
test/                           Automated tests
release/Edushelf.apk            Latest Android build to share
```

---

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| "Invalid ID or password" | Check the ID format (e.g. `IT-23-01003`). Passwords are case-sensitive. Use *Forgot password?* if needed. |
| "Connection failed" / nothing loads | Check internet. Supabase free projects **pause after a week without use**: the leader can restore it on the Supabase dashboard. |
| Can't log in offline | Offline login works only after you've logged in online once on that phone, and not after logging out. |
| Install blocked on the phone | Allow "Install unknown apps" for the app you opened the APK from. On a Play Protect warning: *More details → Install anyway*. |
| "App not installed" when updating | The phone has a version signed with a different key (built before the project had its own key). Uninstall it once, then install the new APK. |
| Web version: "Could not load the page list" | Restart with `flutter run -d edge`. Hot reload doesn't load `web/index.html` changes. |
| `flutter` not recognized | Add Flutter's `bin` folder to Path (section 5) and restart VS Code. |

---

## 9. Known limitations

- **The Windows version** is laid out for phones, so some screens look stretched on a wide window. Resize the window narrower for a phone-like view.
- **The web version is limited:** downloads and the flipbook only work in the Android app; in the browser, materials open in a new tab.
- Downloading **one page** still fetches the whole PDF once (the page is then saved as an image).
- **My Library, bookmarks and reading progress are saved on the phone**, so they don't follow a user to another phone.
- The app name on the phone and the package ID (`com.example…`) should be changed before any public release.
- Builds are signed with a shared **testing key** kept in the project. Fine for testing; a public release needs a private key.
