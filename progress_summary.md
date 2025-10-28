# Overview
- `lib/main.dart` bootstraps Firebase, enables Firestore persistence, and wires global providers for theming, user state, and translation before launching the navigator-driven app shell.【F:lib/main.dart†L434-L585】
- Anonymous sign-in is the default; presence, FCM token sync, and translation preferences hydrate immediately after Splash to prep `/home`. Theme settings (dark, seed color, contrast, text scale) persist via `SharedPreferences`.【F:lib/main.dart†L82-L214】【F:lib/main.dart†L245-L325】【F:lib/main.dart†L500-L515】
- Navigation is centralized in `MaterialApp.routes`, with real-time features (rooms, stories, DMs, admin) implemented directly in `main.dart`. Most economy/settings shells remain placeholders pending follow-up work.【F:lib/main.dart†L500-L581】【F:lib/main.dart†L720-L757】

# Navigation Map
| Route | Widget | Entry Params |
| --- | --- | --- |
| `/` | `SplashPage` | `onReady` callback auto-logs in, starts presence/FCM, then pushes `/home`.【F:lib/main.dart†L500-L515】 |
| `/home` | `HomePage` | None; builds 3-tab scaffold (Rooms, Store placeholder, Profile).【F:lib/main.dart†L627-L704】 |
| `/login` | `LoginPage` | None; manual anonymous login button.【F:lib/main.dart†L606-L619】 |
| `/appearance` | `AppearancePage` | None; toggles theme settings.【F:lib/main.dart†L705-L742】 |
| `/translator` | `TranslatorSettingsPage` | None; choose auto-translate target.【F:lib/main.dart†L743-L783】 |
| `/rooms` | `RoomsTab` | None. Streams rooms list with join/create actions.【F:lib/main.dart†L854-L959】 |
| `/room` | `RoomPage` | String `roomId` or map `{roomId}`; defaults to `room_demo`. Chat UI with message composer.【F:lib/main.dart†L1067-L1401】 |
| `/rooms/create` | `CreateRoomPage` | None; collects name/about/public flags.【F:lib/main.dart†L4875-L5007】 |
| `/dm` | `DMPage` | Thread ID string. Resolves other participant and streams messages.【F:lib/main.dart†L3594-L3673】 |
| `/inbox` | `InboxPage` | None; lists DM threads.【F:lib/main.dart†L3520-L3588】 |
| `/stories` | `StoriesHubPage` (default) or `StoryViewerPage` | Accepts user ID or `{uid, index}` to open specific story. Otherwise hub list.【F:lib/main.dart†L531-L551】 |
| `/story_create` | `StoryCreatePage` | None; compose text/image/video story.【F:lib/main.dart†L3092-L3208】 |
| `/store` | `StorePage` | None; placeholder.【F:lib/main.dart†L720-L757】 |
| `/wallet` | `WalletPage` | None; placeholder.【F:lib/main.dart†L720-L757】 |
| `/vip` | `VIPHubPage` | None; placeholder.【F:lib/main.dart†L720-L757】 |
| `/profile` | `ProfilePage` | None; streams current user profile.【F:lib/main.dart†L3718-L3874】 |
| `/profile_edit` | `ProfileEditPage` | None; placeholder shell, real editing lives in `EditProfilePage` navigated elsewhere.【F:lib/main.dart†L720-L757】【F:lib/main.dart†L3881-L4077】 |
| `/people` | `PeopleDiscoverPage` | None; discover/follow/DM others.【F:lib/main.dart†L3333-L3421】 |
| `/search` | `GlobalSearchPage` | None; multi-tab search with filters/history.【F:lib/main.dart†L5901-L6125】 |
| `/privacy` | `PrivacySettingsPage` | Placeholder scaffold.【F:lib/main.dart†L720-L757】 |
| `/settings` | `SettingsHubPage` | Placeholder scaffold.【F:lib/main.dart†L720-L757】 |
| `/notifications` | `NotificationCenterPage` | None; reads Firestore inbox.【F:lib/main.dart†L6492-L6575】 |
| `/notify/prefs` | `NotificationPrefsPage` | None; toggles user notify flags.【F:lib/main.dart†L6577-L6635】 |
| `/admin` | `AdminPortalPage` | None; pick room to manage.【F:lib/main.dart†L4105-L4150】 |
| `/admin/room` | `AdminRoomPanelPage` | String or `{roomId}`. Tabbed moderation console.【F:lib/main.dart†L4152-L4259】 |
| `/post` | `PostDetailPage` | `{roomId, postId}` map. Shows post + comments.【F:lib/main.dart†L5360-L5436】 |
| `/room/settings` | `RoomSettingsPage` | String or `{roomId}`; tabbed settings (basics, rules, roles, invites).【F:lib/main.dart†L4929-L5069】 |
| `/room/board` | `RoomBoardPage` | Room ID string; feed of posts with composer shortcuts.【F:lib/main.dart†L5504-L5567】 |

# Features
- **Room communities**: list, join/leave, create, and manage rooms with Firestore-backed metadata, member roles, invites, and moderation workflows (reports review, actions log, auto-mute rules, announcements).【F:lib/main.dart†L854-L959】【F:lib/main.dart†L4235-L4705】
- **Room chat**: paginated Firestore stream with typing indicator (RTDB), replies, translation, reactions, pin/unpin, deletion, and media uploads (image/video/audio via Storage). Voice notes use the `record` package with permission checks and duration probing via `audioplayers`.【F:lib/main.dart†L1080-L1401】
- **Stories**: hub, viewer (auto-advance, video playback, view counters), and composer for text/image/video stories with background color and visibility flag stored per item in Firestore + Storage. View tracking writes to `stories/{uid}/items/{id}/views`.【F:lib/main.dart†L2415-L3208】
- **Direct messages**: DM threads collection with unread counts, inbox list, thread view, and quick creation from profile/discover flows. Threads update `last` and unread maps per participant.【F:lib/main.dart†L3333-L3673】
- **Profiles**: current profile page with stats, story strip, quick actions, and full edit flow supporting avatar/cover uploads, bio/link/location/birthday fields, and privacy shortcut. Public profiles support follow/unfollow and DM creation.【F:lib/main.dart†L3333-L4077】
- **Global search**: tabbed search for users, rooms, posts, messages with filters (sort, verification, in-my-rooms) and local history persistence.【F:lib/main.dart†L5901-L6254】
- **Room board posts**: text/image/poll composer, like toggling, comments, pinning, reporting, and notifications broadcast helpers for announcements.【F:lib/main.dart†L5360-L5837】
- **Notifications & inbox**: FCM permission/token sync, Firestore inbox collection with mark-read, dismiss, and deep-link actions, plus notification preferences stored under user doc.【F:lib/main.dart†L245-L347】【F:lib/main.dart†L6492-L6635】
- **Admin tools**: room selector, reports triage with filters/search, member role management, actions log, quick moderation actions (mute/kick/ban), and invite management. System posts and notifications support escalations.【F:lib/main.dart†L4105-L4705】

# Services & Packages
- **Core services/providers**: `AppTheme`, `AppUser`, `TranslatorService`, `PresenceService`, `NotificationsService`, and `NotificationBadge` expose ChangeNotifier/async APIs for UI binding, Firebase auth, translation, RT presence, FCM, and inbox badges.【F:lib/main.dart†L82-L347】【F:lib/main.dart†L6440-L6466】
- **Packages in use** (from `pubspec.yaml`):
  - FlutterFire (`firebase_core` 4.2.0, `firebase_auth` 6.1.1, `cloud_firestore` 6.0.3, `firebase_storage` 13.0.3, `firebase_messaging` 16.0.3, `firebase_database` 12.0.0) – backend services.【F:pubspec.yaml†L10-L24】
  - `provider` 6.1.2 – dependency injection/state. `shared_preferences` 2.3.2 – local persistence. `http` 1.2.2 – Google Translate calls.【F:pubspec.yaml†L26-L31】【F:lib/main.dart†L82-L119】【F:lib/main.dart†L353-L427】
  - Media utilities: `image_picker` 1.2.0, `record` 6.1.2, `audioplayers` 6.5.1, `video_player` 2.9.2, `path_provider` 2.1.4 – story and chat media flows.【F:pubspec.yaml†L33-L42】【F:lib/main.dart†L1080-L1402】【F:lib/main.dart†L3098-L3168】
  - Additional dependencies declared (e.g., `camera`, `url_launcher`, `cached_network_image`, ML Kit) are not yet referenced in code and appear planned for later phases.【F:pubspec.yaml†L39-L54】

# Data Model (Firestore/Storage)
- **Firestore collections**:
  - `users/{uid}` with profile, privacy, notify, i18n fields; subcollections `inbox` for notifications and `inbox` documents marked read/unread.【F:lib/main.dart†L183-L214】【F:lib/main.dart†L6492-L6575】
  - `rooms/{roomId}` storing metadata (`members`, `meta`, `config`, `rules`), with subcollections: `messages`, `members`, `reports`, `moderation/actions`, `invites`, `posts` (each with `likes` and `comments`). System helpers add documents for invites, moderation actions, and announcements.【F:lib/main.dart†L854-L5837】
  - `dmThreads/{threadId}` with `participants`, `last`, `unread`, and nested `messages` subcollection.【F:lib/main.dart†L3399-L3673】
  - `stories/{uid}/items/{storyId}` storing story metadata plus nested `views`. Helpers also store aggregated counts.【F:lib/main.dart†L2113-L3199】
  - `follows/{uid}/following|followers/{otherUid}` – follow graph mutations.【F:lib/main.dart†L3282-L3331】
- **Realtime Database**: `presence/{uid}` for online/lastActive heartbeat, `typing/{roomId}/{uid}` for room typing indicators.【F:lib/main.dart†L245-L276】【F:lib/main.dart†L1091-L1407】
- **Storage paths**: `rooms/{roomId}/images|videos|audios|posts/*`, `stories/{uid}/{storyId}/*`, `users/{uid}/avatar_*` & `cover_*` uploads. Files stored with appropriate metadata and download URLs cached in Firestore.【F:lib/main.dart†L1040-L1342】【F:lib/main.dart†L3098-L3168】【F:lib/main.dart†L3930-L3970】

# Permissions
- Microphone access checked before starting audio recording via `record`. Gallery/Video picker rely on platform permissions handled by `image_picker`. FCM requests notification permissions on startup. Translation HTTP calls require network access but no API key (uses Google public endpoint).【F:lib/main.dart†L1289-L1336】【F:lib/main.dart†L3098-L3114】【F:lib/main.dart†L281-L320】【F:lib/main.dart†L353-L427】

# TODOs
- Story visibility still limited to `everyone`; TODO indicates plans for contacts/custom audiences.【F:lib/main.dart†L3104-L3167】
- Message composer has placeholder action for sticker/picker button (`// TODO: open picker if exists`).【F:lib/main.dart†L1703-L1710】
- Several routed pages (`StorePage`, `WalletPage`, `VIPHubPage`, `ProfileEditPage`, `PrivacySettingsPage`, `SettingsHubPage`) are placeholders needing real implementations.【F:lib/main.dart†L720-L757】

# Risks & Next Steps
- [ ] Harden placeholder surfaces (store, wallet, privacy/settings) or hide routes until implemented.
- [ ] Complete story privacy options (contacts/custom audiences) and enforce in fetch queries.
- [ ] Audit Firestore/Storage security rules to align with moderation tools and invite flows.
- [ ] Replace unofficial Google Translate endpoint with quota-managed service or ML Kit integration to avoid rate limits.
- [ ] Expand automated tests/monitoring for moderation actions, notifications, and translation failure handling.
