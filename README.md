# IPL Fan Portfolio 🏏

A Flutter web app where cricket fans can build and share their personal IPL 2026 fan portfolio. Sign in, answer a few questions, and get a Gemini-generated AI avatar — then share your profile link with the world.

---

## What it does

- **Landing page** — browse all fan portfolios in a live grid, powered by Firestore
- **Create page** — sign in (Google or Email), fill in your fan details, and generate a personalised AI avatar using Gemini 2.0
- **Portfolio page** — your public profile with a shareable link anyone can open

---

## Tech stack

| Layer | Tool |
|---|---|
| Framework | Flutter (web) |
| Routing | go_router |
| Auth | Firebase Auth (Google + Email/Password) |
| Database | Cloud Firestore |
| File storage | Firebase Storage |
| AI avatar | Gemini 2.0 Flash (image generation) |
| Fonts | Playfair Display · Barlow (Google Fonts) |

---

## Getting started

### 1. Clone and install

```bash
git clone <your-repo-url>
cd apl_project
flutter pub get
```

### 2. Firebase setup

The project is already connected to Firebase (`lib/firebase_options.dart` is generated). You just need to:

1. Go to [console.firebase.google.com](https://console.firebase.google.com) → project **apl-project-prem31**
2. **Firestore Database** → Create database → Start in test mode
3. **Authentication** → Sign-in method → enable **Google** and **Email/Password**
4. **Storage** → Get started (default rules are fine for development)

Firestore rules (paste in the Rules tab):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /fan_profiles/{profileId} {
      allow read: if true;
      allow create: if request.resource.data.keys().hasAll([
        'name', 'handle', 'city', 'favouriteTeam',
        'favouritePlayer', 'bio', 'createdAt'
      ]);
      allow update, delete: if false;
    }
  }
}
```

### 3. Gemini API key

Open `lib/services/gemini_service.dart` and paste your key:

```dart
static const _apiKey = 'YOUR_GEMINI_API_KEY';
```

Get a key at [aistudio.google.com](https://aistudio.google.com).

### 4. Run

```bash
flutter run -d chrome
```

---

## Project structure

```
lib/
├── main.dart                   # app entry + Firebase init
├── router.dart                 # go_router — 3 routes
├── theme.dart                  # IPL colour palette + text styles
├── liquid_glass.dart           # glass-morphism UI components
├── blur_text.dart              # word-by-word blur-in animation
├── firebase_options.dart       # generated Firebase config
├── models/
│   └── fan_profile.dart        # data model
├── services/
│   ├── auth_service.dart       # Google + Email auth
│   ├── firestore_service.dart  # Firestore + Storage helpers
│   └── gemini_service.dart     # Gemini 2.0 avatar generation
├── pages/
│   ├── landing_page.dart       # home — fan grid
│   ├── create_page.dart        # sign in + portfolio form
│   └── portfolio_page.dart     # public fan profile
└── widgets/
    ├── fade_in.dart            # entrance animation
    ├── ipl_navbar.dart         # top navigation bar
    └── profile_card.dart       # fan card on landing grid
```

---


## Deploying

Build for web:

```bash
flutter build web --release
```

The output is in `build/web/`. Deploy to any static host:

- **GitHub Pages** — push `build/web` to a `gh-pages` branch
- **Firebase Hosting** — `firebase deploy`
- **Netlify** — drag and drop `build/web`

After deploying, add your domain to Firebase Console → Authentication → Authorized domains.

---


## Design

- IPL 2026 theme — deep navy background, trophy gold (`#D4AF37`), electric blue accents
- Liquid-glass cards with gradient borders throughout
- Word-by-word blur-in headline animations
- Each team has its own accent colour on cards and profiles
- Fully responsive — works on mobile, tablet, and desktop
