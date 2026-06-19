# Wirc Foundation — Persistence + Offline-First + Service Refactor

Date: 2026-06-19
Status: approved

## 1. Visão

Trocar o storage em memória do Wirc por persistência real (GRDB/SQLite), implementar cache offline-first para feeds, e extrair serviços do AppState (objeto Deus de 500+ linhas). Esta fase não adiciona features novas nem muda UI — é a fundação para tudo que vem depois.

### Princípios
1. **O protocolo WOMStore não muda.** Implementações são trocadas, consumidores não.
2. **Providers não mudam.** IRC, RSS, Mastodon continuam iguais.
3. **UI não muda.** FeedView, StreamView, Messages tabs permanecem idênticas.
4. **Offline-first.** O app abre e mostra conteúdo mesmo sem internet.
5. **Dedup por canonical URL.** Mesmo artigo de 2 feeds ≠ duplicata no feed.

---

## 2. GRDB Persistent Store

### Schema

```sql
CREATE TABLE wom_object (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    createdAt REAL NOT NULL,
    schema TEXT,
    attributedTo TEXT,       -- JSON
    content TEXT,            -- JSON
    data TEXT,               -- JSON
    provenance TEXT,         -- JSON
    governance TEXT,         -- JSON
    classification TEXT,     -- JSON
    bindings TEXT,           -- JSON
    location TEXT,           -- JSON, indexed
    temporal TEXT,           -- JSON, indexed
    canonicalUrl TEXT,       -- indexed (dedup)
    raw JSON NOT NULL        -- full WOMObject as JSON (single source of truth)
);

CREATE INDEX idx_wom_type ON wom_object(type);
CREATE INDEX idx_wom_created ON wom_object(createdAt);
CREATE INDEX idx_wom_canonical ON wom_object(canonicalUrl);
CREATE INDEX idx_wom_expires ON wom_object(temporal);

CREATE TABLE feed_subscription (
    id TEXT PRIMARY KEY,
    feedURL TEXT NOT NULL,
    title TEXT,
    sourceType TEXT NOT NULL,
    tags TEXT,               -- JSON array
    etag TEXT,
    lastModified TEXT,
    lastFetchedAt REAL,
    errorCount INTEGER DEFAULT 0,
    createdAt REAL NOT NULL,
    updatedAt REAL NOT NULL
);

CREATE TABLE feed_item (
    womId TEXT PRIMARY KEY REFERENCES wom_object(id),
    subscriptionId TEXT NOT NULL REFERENCES feed_subscription(id),
    canonicalUrl TEXT NOT NULL,
    fetchedAt REAL NOT NULL
);

CREATE INDEX idx_feed_item_url ON feed_item(canonicalUrl);
CREATE INDEX idx_feed_item_sub ON feed_item(subscriptionId);
```

### WOMStore protocol estendido

```swift
protocol WOMStore: AnyObject, Sendable {
    // Existing (unchanged)
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func get(id: String) async throws -> WOMObject?
    func list(type: String?) async throws -> [WOMObject]
    func delete(id: String) async throws
    func all() async throws -> [WOMObject]
    func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool

    // Foundation additions
    func list(type: String?, since: Date?, limit: Int?) async throws -> [WOMObject]
    func count(type: String?) async throws -> Int
    func pruneExpired() async throws -> Int
    func deleteByCanonicalURL(_ url: String) async throws
}
```

### GRDBWOMStore

```swift
final class GRDBWOMStore: WOMStore, @unchecked Sendable {
    private let db: DatabaseQueue

    init(path: String) throws {
        db = try DatabaseQueue(path: path, configuration: {
            var c = Configuration()
            c.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode=WAL") }
            return c
        }())
        try migrator.migrate(db)
    }
}
```

- WAL mode para leituras não bloquearem escritas
- JSON columns armazenam objetos Codable como texto
- `raw` column guarda o WOMObject completo para reconstrução sem perda
- Migration via GRDB migrator (versionado)

### Migration do JSONFileStore existente

```swift
func migrateFromJSONFileStore(store: JSONFileStore, to grdb: GRDBWOMStore) async throws {
    let objects = try await store.all()
    try await grdb.saveMany(objects)
    // Marca migration como concluída, apaga JSON antigo
}
```

---

## 3. Feed Subscriptions Persistentes + Offline

### Fluxo de refresh

```
refreshFeed(subscription):
  1. HTTP GET com If-None-Match (ETag) / If-Modified-Since
  2. 304 → atualiza lastFetchedAt, retorna WOMs existentes
  3. 200 → parse items
     ├─ saveIfNew(canonicalUrl) para cada item (dedup cross-subscription)
     ├─ INSERT INTO feed_item
     └─ UPDATE feed_subscription (etag, lastModified, lastFetchedAt, errorCount=0)
  4. Erro → incrementa errorCount, mantém cache existente
```

### Cache offline

```
AppState.init():
  1. loadSubscriptions() do GRDB
  2. loadRecentWOMs() do GRDB (type=wom:Post, ORDER BY createdAt DESC, LIMIT 500)
  3. Exibe feed imediatamente (cache, sem rede)
  4. Background: refreshAllFeedsBatched()
     └─ Se sem internet: agenda BGTaskScheduler para próxima tentativa
```

### Dedup cross-subscription

Mesmo artigo de 2 feeds diferentes = mesmo `canonicalUrl`. `saveIfNew` impede duplicata. Mas feed mostra ambos se vieram via subscriptions diferentes (signal social). UI decide se agrupa ou não.

### Limpeza

```
GRDBWOMStore.pruneExpired():
  DELETE FROM wom_object
  WHERE id IN (
    SELECT wom_object.id FROM wom_object
    WHERE json_extract(temporal, '$.expiresAt') IS NOT NULL
    AND json_extract(temporal, '$.expiresAt') < datetime('now')
  )
  
Executado: app launch + BGTaskScheduler a cada 1h
```

### O que NÃO muda

- Providers (IRC, RSS, Mastodon) mantidos intactos
- UI (FeedView, StreamView, Messages) mantida
- `AppState` mantém mesma API pública para Views

---

## 4. Refactor do AppState

### Extração de serviços

```
AppState atual (500+ linhas, 4 responsabilidades):
  ├── Servers CRUD + UserDefaults
  ├── IRC clients + events + channels + DMs
  ├── Feed subscriptions + refresh + OPML
  ├── Mastodon accounts + timeline + post
  └── WOM store + queries

AppState novo (~150 linhas):
  └── UI state + orquestração entre serviços

Serviços extraídos:
  ├── WOMRepository (~80 linhas)
  ├── FeedService (~150 linhas)
  ├── IRCService (~120 linhas)
  └── MastodonService (~80 linhas)
```

### Novos arquivos

| Arquivo | Responsabilidade |
|---------|-----------------|
| `GRDBWOMStore.swift` | Implementação GRDB do protocolo WOMStore |
| `WOMRepository.swift` | Wrapper sobre GRDBWOMStore, queries de feed, dedup, prune |
| `FeedService.swift` | Subscriptions, refresh, batch, OPML, cache offline |
| `IRCService.swift` | Connect/disconnect, event→WOM, channels, DMs |
| `MastodonService.swift` | Accounts, timeline, post, boost |

### Contratos

```swift
protocol WOMRepository: Sendable {
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func fetchFeed(limit: Int, since: Date?) async throws -> [WOMObject]
    func saveIfNew(_ object: WOMObject, canonicalURL: String) async throws -> Bool
    func pruneExpired() async throws -> Int
}

protocol FeedService: Sendable {
    func loadSubscriptions() async throws -> [FeedSubscription]
    func addFeed(url: String) async throws -> FeedSubscription
    func removeFeed(id: UUID) async throws
    func refreshFeed(_ sub: FeedSubscription) async throws -> [WOMObject]
    func refreshAllFeeds() async throws
    func importOPML(data: Data) async throws -> Int
}

protocol IRCService: Sendable {
    func connect(to config: IRCConnectionConfig) async throws
    func disconnect(from id: UUID) async
    func joinChannel(_ channel: String, serverId: UUID) async
    func sendMessage(_ text: String, channel: String, serverId: UUID) async throws -> WOMObject
    func handleEvent(_ event: IRCEvent, serverId: UUID) async throws -> [WOMObject]
}
```

### AppState reduzido

```swift
@Observable @MainActor
final class AppState {
    let womRepo: WOMRepository
    let feedService: FeedService
    let ircService: IRCService
    let mastodonService: MastodonService

    // UI State
    var connectionStates: [UUID: ConnectionStatus] = [:]
    var womObjects: [WOMObject] = []
    var channelUsers: [String: [ChannelUser]] = [:]
    var feedLoading = false

    // Orquestração (delega)
    func connect(to id: UUID) { Task { await ircService.connect(to: config) } }
    func addFeed(url: String) { Task { let sub = try await feedService.addFeed(url: url); await refreshFeedUI() } }
    func sendMessage(_ text: String, channel: String, serverId: UUID) {
        Task { let obj = try await ircService.sendMessage(text, channel: channel, serverId: serverId); womObjects.append(obj) }
    }
}
```

### Sequência de extração (sem quebrar)

1. Criar `GRDBWOMStore` + migration
2. Criar `WOMRepository` wrapper
3. Criar `FeedService` (extraído do AppState)
4. Criar `IRCService` (extraído do AppState)
5. Criar `MastodonService` (extraído do AppState)
6. Atualizar `AppState` para usar serviços
7. Remover código duplicado do AppState

---

## 5. Dependências

- **GRDB** — SQLite wrapper Swift-native (via Swift Package Manager)
- Nenhuma outra dependência nova

## 6. O que NÃO muda

- `WOMStore` protocol (estendido, não quebrado)
- `WOMObject` e todos os modelos Core/WOM
- Providers: `IRCClient`, `FeedParser`, `MastodonClient`
- Adapters: `IRCToWOMAdapter`, `FeedToWOMAdapter`, `MastodonToWOMAdapter`
- UI: `StreamView`, `FeedView`, `FeedCard`, `IRCMessageDeckView`, `SettingsView`
- Navegação: 4 tabs (Stream, Messages, Library, Workshop)

## 7. Métricas de sucesso

- App abre e mostra feed sem internet (cache do último refresh)
- WOMs sobrevivem a app relaunch
- Tempo de abertura do app < 1s (GRDB WAL mode, sem fetch de rede no startup)
- AppState reduzido de 500+ para <200 linhas
- Build + testes passando sem regressão
