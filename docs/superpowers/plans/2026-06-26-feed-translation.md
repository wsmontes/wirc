# Feed Translation — Automatic Multi-Language Translation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** All feed content automatically translates to the user's chosen language using Apple's on-device Translation framework, with a translation cache and visual indicator.

**Architecture:** A `TranslationService` actor wraps Apple's `Translation` framework. At ingestion time (FeedToWOMAdapter), content is sent for translation via the service, which caches results by (text, targetLanguage) → translatedText. The translated text is stored in `WOMObject.data["translatedText"]`. FeedCard checks this and renders the translation, adding a small "🌐 Translated" badge. A new language picker in Settings controls the target language, persisted via `@AppStorage`.

**Tech Stack:** Swift 6, Apple `Translation` framework (iOS 17.4+, on-device, offline), `NaturalLanguage` for source language detection, `NSCache`-backed translation cache.

## Global Constraints

- iOS 17.4 minimum (required by Translation framework — if current target is lower, gate behind `#available(iOS 17.4, *)`)
- Swift 6 concurrency safety
- All UI must use `DesignSystem.Colors` and `DesignSystem.Fonts`
- Build must succeed before each commit
- Translation must work offline (on-device, no network calls)
- Never modify the original text — store translation alongside it

---

## File Structure Map

```
Wirc/WircApp/
  Infrastructure/
    Translation/
      TranslationService.swift       ← NEW: actor wrapping Translation framework
      TranslationCache.swift          ← NEW: NSCache-backed cache
  Features/
    Feed/
      FeedCard.swift                  ← MODIFY: show translated text + badge
    Settings/
      SettingsView.swift              ← MODIFY: add language picker
  App/
    AppState.swift                    ← MODIFY: store preferred language, wire translation
  Core/
    DesignSystem.swift                ← MODIFY: add translation badge color if needed
```

---

### Task 1: Create TranslationService actor

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Translation/TranslationService.swift`

**Goal:** Actor that translates text using Apple's Translation framework, with an in-memory cache.

- [ ] **Step 1: Create TranslationService.swift**

```swift
import Foundation
import Translation

/// On-device translation service. Caches results so repeated translations
/// of the same text are instant. All methods are async and thread-safe.
actor TranslationService {
    static let shared = TranslationService()
    
    private var cache: [CacheKey: String] = [:]
    private let maxCacheSize = 500
    
    struct CacheKey: Hashable {
        let text: String
        let targetLanguage: String
    }
    
    /// Translate text to the target language. Returns the original text if
    /// translation fails or the source is already the target language.
    func translate(_ text: String, to targetLanguage: String) async -> String {
        guard !text.isEmpty, text.count > 2 else { return text }
        guard targetLanguage != "off" else { return text }
        
        let key = CacheKey(text: text, targetLanguage: targetLanguage)
        if let cached = cache[key] { return cached }
        
        let result = await performTranslation(text, to: targetLanguage)
        cache[key] = result
        trimCache()
        return result
    }
    
    private func performTranslation(_ text: String, to targetLanguage: String) async -> String {
        guard #available(iOS 17.4, *) else { return text }
        
        do {
            let configuration = TranslationSession.Configuration(
                source: nil, // auto-detect
                target: Locale.Language(identifier: targetLanguage)
            )
            let session = TranslationSession(configuration: configuration)
            let response = try await session.translate(text)
            // If the response is same as input, source likely matches target
            return response.targetText
        } catch {
            os_log(.debug, "TranslationService: translation failed for '%{public}@': %{public}@",
                   text.prefix(50), error.localizedDescription)
            return text
        }
    }
    
    private func trimCache() {
        if cache.count > maxCacheSize {
            // Remove oldest entries (Dictionary keeps insertion order in Swift)
            let toRemove = cache.count - maxCacheSize
            cache.removeFirst(min(toRemove, cache.count))
        }
    }
    
    /// Clear the translation cache (e.g., when language changes).
    func clearCache() {
        cache.removeAll()
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,id=D3A8E60A-D820-4E29-A7E3-BC32DE7AD990' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Translation/TranslationService.swift
git commit -m "feat: add TranslationService actor with on-device translation + cache"
```

### Task 2: Add language preference to AppState + Settings UI

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift` — add `preferredLanguage` property
- Modify: `Wirc/WircApp/Features/Settings/SettingsView.swift` — add language picker

**Goal:** User can select target language in Settings. Stored in `@AppStorage`. Also exposes a `Locale.Language`-compatible identifier.

- [ ] **Step 1: Add preferredLanguage to AppState**

In `AppState.swift`, add:
```swift
@AppStorage("wirc.translation.language") var preferredLanguage: String = "off"
```

- [ ] **Step 2: Add language picker to SettingsView**

In `SettingsView.swift`, add a new section before "Governance Defaults":
```swift
Section("Translation") {
    Picker("Translate feed to", selection: $appState.preferredLanguage) {
        Text("Off").tag("off")
        Text("English").tag("en")
        Text("Português (BR)").tag("pt-BR")
        Text("Español").tag("es")
        Text("Français").tag("fr")
        Text("Deutsch").tag("de")
        Text("Italiano").tag("it")
        Text("日本語").tag("ja")
        Text("中文 (Simplified)").tag("zh-Hans")
    }
} footer: {
    if appState.preferredLanguage != "off" {
        Text("Feed content will be translated on-device. Original text is preserved.")
    } else {
        Text("Content is shown in its original language.")
    }
}
```

- [ ] **Step 3: Clear translation cache when language changes**

In `AppState.swift`, add onChange:
```swift
.onChange(of: preferredLanguage) { _, _ in
    Task { await TranslationService.shared.clearCache() }
}
```

This needs to be wired in `WircApp` or in the `didSet` of the property.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift Wirc/WircApp/Features/Settings/SettingsView.swift
git commit -m "feat: add language preference picker to Settings, stored in AppStorage"
```

### Task 3: Translate content at ingestion time

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift` — translate during convertItem
- Modify: `Wirc/WircApp/Infrastructure/Mastodon/MastodonToWOMAdapter.swift` — translate during convertStatus

**Goal:** After the WOMObject is created, if a target language is set, translate the content text and store the result in `data["translatedText"]`.

- [ ] **Step 1: Add translation call to FeedToWOMAdapter**

In `convertItem()`, after building the WOMObject, check if translation is needed. Add a reference to the preferred language:

```swift
// In FeedToWOMAdapter class, add a property:
var preferredLanguage: String = "off"

// In convertItem(), after building the WOMObject, add:
if preferredLanguage != "off", let originalText = item.description, !originalText.isEmpty {
    let translated = await TranslationService.shared.translate(originalText, to: preferredLanguage)
    if translated != originalText {
        data["translatedText"] = translated
    }
}
```

Pass `preferredLanguage` from `AppState` when creating the adapter. Actually, the adapter is a stored property on `FeedManager`. Let me wire it:

In `FeedManager`, add `var preferredLanguage: String = "off"`. Set it from `AppState.init()`.

In `refreshFeed`, the adapter is already used — but we need to pass the language to the adapter's `convert` method. The adapter already receives items in `convert(items:subscription:store:)`.

Update the adapter's `convert` to accept a language parameter:
```swift
func convert(items: [FeedItem], subscription: FeedSubscription, store: WOMStore,
             preferredLanguage: String = "off") async -> [WOMObject]
```

- [ ] **Step 2: Add translation call to MastodonToWOMAdapter**

Same pattern: add `preferredLanguage` property, translate content after building the WOMObject.

- [ ] **Step 3: Wire preferredLanguage from AppState to adapters**

In `FeedManager`:
```swift
var preferredLanguage: String = "off"
```

In `AppState.init()`:
```swift
feed.preferredLanguage = preferredLanguage
```

And update `refreshFeed` to pass it to the adapter.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift Wirc/WircApp/Infrastructure/Mastodon/MastodonToWOMAdapter.swift Wirc/WircApp/App/FeedManager.swift Wirc/WircApp/App/AppState.swift
git commit -m "feat: translate feed content at ingestion time via TranslationService"
```

### Task 4: Render translated text in FeedCard + translation badge

**Files:**
- Modify: `Wirc/WircApp/Features/Feed/FeedCard.swift`

**Goal:** If `post.data["translatedText"]` exists, show translated text instead of original, and display a small "🌐 Translated" badge.

- [ ] **Step 1: Add translatedText check in FeedCard**

In FeedCard, add a computed property:
```swift
private var displayText: String? {
    post.data["translatedText"] ?? strippedBody
}

private var isTranslated: Bool {
    post.data["translatedText"] != nil
}
```

Replace all `strippedBody` references with `displayText` in the content areas.

- [ ] **Step 2: Add translation indicator badge**

In the provenance badge area (or a subtle inline indicator), add:
```swift
if isTranslated {
    HStack(spacing: 2) {
        Image(systemName: "translate")
            .font(.system(size: 8))
        Text("Translated")
            .font(.system(size: 8))
    }
    .foregroundStyle(DesignSystem.Colors.pencil)
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .background(DesignSystem.Colors.border.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 3))
}
```

Add it inline after the timestamp in `provenanceBadge`.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Feed/FeedCard.swift
git commit -m "feat: show translated text + translation badge on FeedCard"
```

### Task 5: Translate existing content when language is changed

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift`

**Goal:** When the user changes the preferred language, existing womObjects get translated retroactively. This runs in the background.

- [ ] **Step 1: Add onChange handler for preferredLanguage**

In `AppState`, after changing `preferredLanguage`, trigger translation of existing feed objects:

```swift
func retranslateAllFeedContent() {
    let language = preferredLanguage
    guard language != "off" else { return }
    Task.detached(priority: .background) { [weak self] in
        guard let self else { return }
        let objects = await MainActor.run { self.womObjects.filter { $0.type.contains("wom:Post") } }
        for i in 0..<objects.count {
            var obj = objects[i]
            if let text = obj.content?.text, !text.isEmpty {
                let translated = await TranslationService.shared.translate(text, to: language)
                if translated != text {
                    obj.data["translatedText"] = translated
                    try? await self.store.save(obj)
                }
            }
        }
        await MainActor.run {
            self.invalidateIndexes()
        }
    }
}
```

Call `retranslateAllFeedContent()` from the `onChange` of `preferredLanguage` in `WircApp`.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift
git commit -m "feat: retranslate existing content when preferred language changes"
```

---

## Execution Order

Tasks 1-2 can run in parallel. Task 3 depends on Task 1. Task 4 depends on Task 3. Task 5 depends on Task 1-2.

```
T1 (TranslationService) ──┐
                           ├──> T3 (ingestion translate) ──> T4 (FeedCard UI)
T2 (Settings UI) ─────────┤                                    │
                           └────────────────────────────────────┘
                                                                 T5 (retranslate existing)
```

### Estimated effort
- Task 1: 1 hour
- Task 2: 30 minutes
- Task 3: 1 hour
- Task 4: 30 minutes
- Task 5: 30 minutes
- **Total: 5 tasks, ~3.5 hours**
